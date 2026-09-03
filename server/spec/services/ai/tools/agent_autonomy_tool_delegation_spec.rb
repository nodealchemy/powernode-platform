# frozen_string_literal: true

require "rails_helper"

# HIER-P0 — the two MCP delegation verbs on Ai::Tools::AgentAutonomyTool.
#
#   platform.describe_delegation   (read)  — the agent's own delegation policy
#                                            plus its resolved effective
#                                            authority (DelegationAuthorityService)
#   platform.set_delegation_policy (write) — PROPOSE a delegation policy for an
#                                            agent; gated by Ai::AutonomyGate
#                                            under the core category
#                                            `ai.delegation_policy.update`.
#
# Why AgentAutonomyTool and not AgentManagementTool: the read's REST twin
# (GET /api/v1/ai/autonomy/delegation_policies/:agent_id) is gated on
# ai.agents.read — exactly this tool's REQUIRED_PERMISSION floor — while
# AgentManagementTool's floor is ai.agents.execute, which would OVER-gate a
# read. The write maps to ai.agents.update through ACTION_PERMISSIONS, the
# same per-action ladder the tool's other privileged verbs use.
#
# The escalation rule (guidance-agent-escalation): an agent may PROPOSE its
# own authority, never grant it. So with no intervention policy row for the
# category, the gate's default (require_approval) parks the write as a pending
# approval and writes NO policy row; only an explicit auto_approve row (an
# operator decision) lets the write land synchronously — and it lands through
# the DeferredToolCall replay seam, not the action body.
RSpec.describe "agent_autonomy MCP delegation verbs" do
  let(:account)  { create(:account) }
  let(:reader)   { create(:user, account: account, permissions: %w[ai.agents.read]) }
  let(:updater)  { create(:user, account: account, permissions: %w[ai.agents.read ai.agents.update]) }
  let(:manager)  { create(:user, account: account, permissions: %w[ai.agents.read ai.agents.update ai.autonomy.manage]) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:agent)    { create(:ai_agent, account: account, name: "Ops Worker", agent_type: "assistant", creator: reader, provider: provider) }
  let(:other_agent) { create(:ai_agent, account: account, name: "Other", creator: reader, provider: provider) }

  def run(tool_name, params = {}, user:, mcp_agent: agent)
    ::Ai::Tools::McpPlatformToolRegistrar.execute_tool(
      "platform.#{tool_name}",
      params: params,
      account: account,
      user: user,
      mcp_agent: mcp_agent
    )
  end

  def run_expecting_refusal(tool_name, params = {}, user:, mcp_agent: agent)
    run(tool_name, params, user: user, mcp_agent: mcp_agent)
  rescue ::Mcp::ProtocolService::PermissionDeniedError => e
    { success: false, error: e.message }
  end

  # The approval-chain workflow is capability-gated; the gate's :pending arm
  # needs Ai::ApprovalChain, which core ships, but the workflow service checks
  # the governance capability (mirrors agent_autonomy_tool_action_permission_spec).
  before do
    allow(Shared::FeatureGateService).to receive(:capability_present?).and_call_original
    allow(Shared::FeatureGateService).to receive(:capability_present?).with(:governance).and_return(true)
  end

  describe "registration and declarations" do
    it "registers both verbs on AgentAutonomyTool" do
      expect(::Ai::Tools::PlatformApiToolRegistry::TOOLS["describe_delegation"]).to eq("Ai::Tools::AgentAutonomyTool")
      expect(::Ai::Tools::PlatformApiToolRegistry::TOOLS["set_delegation_policy"]).to eq("Ai::Tools::AgentAutonomyTool")
    end

    it "declares the read as non-mutating and the write as gated under the core category" do
      read  = ::Ai::Tools::AgentAutonomyTool.declared_action("describe_delegation")
      write = ::Ai::Tools::AgentAutonomyTool.declared_action("set_delegation_policy")

      expect(read).to include(mutating: false)
      expect(write).to include(
        mutating: true,
        action_category: "ai.delegation_policy.update",
        executor_class: "Ai::Executors::DeferredToolCall",
        gate_context: :deferred_tool_call_context,
        on_proceed: :deferred_tool_call_result
      )
    end

    it "registers ai.delegation_policy.update as a core intervention category" do
      expect(::Ai::InterventionPolicy.category_registered?("ai.delegation_policy.update")).to be(true)
    end

    it "maps the write to ai.agents.update and leaves the read at the floor" do
      expect(::Ai::Tools::AgentAutonomyTool::ACTION_PERMISSIONS["set_delegation_policy"]).to eq("ai.agents.update")
      expect(::Ai::Tools::AgentAutonomyTool::ACTION_PERMISSIONS).not_to have_key("describe_delegation")
    end
  end

  describe "describe_delegation" do
    it "reports no policy and the resolved effective authority for the calling agent" do
      result = run("describe_delegation", {}, user: reader)

      expect(result[:success]).to be(true), result.inspect
      data = result[:data]
      expect(data[:agent]).to include(id: agent.id, name: "Ops Worker")
      expect(data[:policy]).to be_nil
      expect(data[:effective_authority]).to include(:tier, :capabilities)
      expect(data[:effective_authority][:delegation_policy]).to be_nil
    end

    it "returns the agent's own policy when one exists" do
      create(:ai_delegation_policy, account: account, agent: agent, max_depth: 2,
                                    allowed_delegate_types: %w[assistant], delegatable_actions: %w[read_data])

      result = run("describe_delegation", {}, user: reader)

      expect(result[:success]).to be(true), result.inspect
      expect(result[:data][:policy]).to include(
        agent_id: agent.id, max_depth: 2, allowed_delegate_types: %w[assistant], delegatable_actions: %w[read_data]
      )
      expect(result[:data][:effective_authority][:delegation_policy]).to include(max_depth: 2)
    end

    it "describes another agent in the account by id" do
      result = run("describe_delegation", { "agent_id" => other_agent.id }, user: reader)

      expect(result[:success]).to be(true), result.inspect
      expect(result[:data][:agent][:id]).to eq(other_agent.id)
    end

    it "refuses an agent outside the account" do
      foreign = create(:ai_agent, account: create(:account))
      result = run("describe_delegation", { "agent_id" => foreign.id }, user: reader)

      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/not found/i)
    end
  end

  describe "set_delegation_policy" do
    let(:proposal) do
      { "max_depth" => 2, "allowed_delegate_types" => %w[assistant],
        "delegatable_actions" => %w[read_data], "budget_delegation_pct" => 0.25,
        "inheritance_policy" => "conservative" }
    end

    it "is refused without ai.agents.update and writes nothing" do
      expect {
        result = run_expecting_refusal("set_delegation_policy", proposal, user: reader)
        expect(result[:success]).to be(false)
        expect(result[:error]).to include("ai.agents.update")
      }.not_to change { ::Ai::DelegationPolicy.count }
    end

    it "parks the proposal as a pending approval under the default require_approval policy" do
      result = nil
      expect {
        result = run("set_delegation_policy", proposal, user: updater)
      }.not_to change { ::Ai::DelegationPolicy.count }

      expect(result[:success]).to be(true), result.inspect
      data = result[:data]
      expect(data[:pending]).to be(true)
      expect(data[:action_category]).to eq("ai.delegation_policy.update")
      expect(data[:deferred_operation_id]).to be_present
      expect(data[:approval_request_id]).to be_present

      deferred = ::Ai::DeferredOperation.find(data[:deferred_operation_id])
      expect(deferred.status).to eq("pending")
      expect(deferred.executor_class).to eq("Ai::Executors::DeferredToolCall")
      expect(deferred.params.dig("tool_params", "max_depth")).to eq(2)
      expect(deferred.ai_agent_id).to eq(agent.id)
    end

    context "when an operator has set the category to auto_approve" do
      before do
        ::Ai::InterventionPolicy.create!(
          account: account, action_category: "ai.delegation_policy.update",
          scope: "global", policy: "auto_approve", priority: 5, is_active: true
        )
      end

      it "writes the policy for the calling agent through the replay seam" do
        result = nil
        expect {
          result = run("set_delegation_policy", proposal, user: updater)
        }.to change { ::Ai::DelegationPolicy.where(account_id: account.id, agent_id: agent.id).count }.from(0).to(1)

        expect(result[:success]).to be(true), result.inspect
        row = ::Ai::DelegationPolicy.find_by!(account_id: account.id, agent_id: agent.id)
        expect(row.max_depth).to eq(2)
        expect(row.allowed_delegate_types).to eq(%w[assistant])
        expect(row.delegatable_actions).to eq(%w[read_data])
        expect(row.budget_delegation_pct).to eq(0.25)
        expect(result[:data]).to include(policy: a_hash_including(id: row.id, max_depth: 2))
      end

      it "updates the existing row rather than creating a second one" do
        existing = create(:ai_delegation_policy, account: account, agent: agent, max_depth: 5)

        expect {
          run("set_delegation_policy", proposal.merge("max_depth" => 1), user: updater)
        }.not_to change { ::Ai::DelegationPolicy.count }

        expect(existing.reload.max_depth).to eq(1)
      end

      it "returns a validation error envelope instead of raising" do
        result = run("set_delegation_policy", proposal.merge("max_depth" => 99), user: updater)

        expect(result[:success]).to be(false)
        expect(result[:error]).to match(/max_depth|Max depth/i)
      end

      it "writes ANOTHER agent's row only for a caller holding ai.autonomy.manage" do
        expect {
          result = run("set_delegation_policy", proposal.merge("agent_id" => other_agent.id), user: manager)
          expect(result[:success]).to be(true), result.inspect
        }.to change { ::Ai::DelegationPolicy.where(account_id: account.id, agent_id: other_agent.id).count }.from(0).to(1)
      end
    end

    # The operator ruling priced this verb at ai.agents.update because an agent
    # PROPOSES ITS OWN authority. A proposal aimed at a THIRD agent is a
    # different act: under an operator's auto_approve row for the category it
    # rewrites that agent's delegation authority laterally, which is exactly
    # what the REST twin charges ai.autonomy.manage for
    # (Ai::AutonomyWriteActions:330). The refusal lands BEFORE the gate, so a
    # foreign proposal is not even parked as a pending approval.
    context "when the proposal targets ANOTHER agent" do
      it "is refused for a caller holding only ai.agents.update, and parks nothing" do
        result = nil
        expect {
          result = run("set_delegation_policy", proposal.merge("agent_id" => other_agent.id), user: updater)
        }.not_to change { [ ::Ai::DelegationPolicy.count, ::Ai::DeferredOperation.count ] }

        expect(result[:success]).to be(false), result.inspect
        expect(result[:error]).to include("ai.autonomy.manage")
      end

      it "is allowed for a caller holding ai.autonomy.manage, and is still gated" do
        result = run("set_delegation_policy", proposal.merge("agent_id" => other_agent.id), user: manager)

        expect(result[:success]).to be(true), result.inspect
        expect(result[:data][:pending]).to be(true)
        expect(::Ai::DelegationPolicy.count).to eq(0)
      end

      it "does not escalate when agent_id names the calling agent itself" do
        result = run("set_delegation_policy", proposal.merge("agent_id" => agent.id), user: updater)

        expect(result[:success]).to be(true), result.inspect
        expect(result[:data][:pending]).to be(true)
      end
    end
  end
end
