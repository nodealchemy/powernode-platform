# frozen_string_literal: true

require "rails_helper"

# IMP-e8adfcfcab9b — per-ACTION authorization parity for the agent_autonomy MCP
# surface.
#
# Ai::Tools::BaseTool defines REQUIRED_PERMISSION = nil and AgentAutonomyTool
# never overrode it, so McpPlatformToolRegistrar#enforce_permission! returned at
# its first line — BEFORE the authentication check and the has_permission?
# check. Every action on the tool was therefore reachable
# by any MCP caller with no permission check at all, including
# approve_deferred_operation, which EXECUTES the approved operation. Its REST
# twin requires ai.autonomy.approve.
#
# The invariant these examples hold is parity per ACTION, not per tool: nothing
# reachable over MCP may be more permissive than the REST surface for the same
# operation. One tool-level constant cannot express that — the tool bundles
# reads (ai.agents.read), goal writes (ai.goals.manage), policy CRUD
# (ai.intervention_policies.manage) and approvals (ai.autonomy.approve) — so the
# gate is the ACTION_PERMISSIONS map already used by seven sibling tools,
# enforced against the action that actually RUNS.
#
# Two failure modes are covered deliberately, because a refusal-only test sees
# neither:
#   * under-gating — a permissive compromise constant would leave approval open
#     while looking gated (the "smuggled action" example below is the sharp end:
#     a user principal is NOT pinned to the invoked tool name, so the gate has
#     to key on the executed action);
#   * over-gating — a floor high enough to lock legitimate callers out of goals
#     and introspection. The positive examples are controls: they pass on
#     unmodified HEAD and exist to catch that regression.
RSpec.describe "agent_autonomy MCP per-action authorization" do
  let(:tool_class) { ::Ai::Tools::AgentAutonomyTool }
  let(:account) { create(:account) }

  # The first user created in an account is given the OWNER role, so every actor
  # here declares its permissions explicitly (see spec/factories/users.rb).
  let(:reader)       { create(:user, account: account, permissions: %w[ai.agents.read]) }
  let(:approver)     { create(:user, account: account, permissions: %w[ai.agents.read ai.autonomy.approve]) }
  let(:goal_manager) { create(:user, account: account, permissions: %w[ai.agents.read ai.goals.manage]) }
  let(:policy_admin) { create(:user, account: account, permissions: %w[ai.agents.read ai.intervention_policies.manage]) }
  let(:unprivileged) { create(:user, account: account, permissions: []) }

  let(:agent) { create(:ai_agent, account: account) }

  def run(tool_name, params = {}, user:, mcp_agent: nil)
    ::Ai::Tools::McpPlatformToolRegistrar.execute_tool(
      "platform.#{tool_name}",
      params: params,
      account: account,
      user: user,
      mcp_agent: mcp_agent
    )
  end

  # A refusal is a refusal whether it surfaces as an error result from the tool
  # or as a raise from the registrar. Normalizing both into one shape keeps the
  # acceptance criterion on the OBSERVABLE — the operation did not run — instead
  # of on the layer the gate happens to live in, so these examples stay
  # meaningful if the gate ever moves.
  def run_expecting_refusal(tool_name, params = {}, user:, mcp_agent: nil)
    run(tool_name, params, user: user, mcp_agent: mcp_agent)
  rescue ::Mcp::ProtocolService::PermissionDeniedError => e
    { success: false, error: e.message }
  end

  # A real approval-gated operation, built the way production builds one, so the
  # oracle can be the ROW plus the executor's own side effect rather than the
  # tool's return value.
  before do
    ::Ai::InterventionPolicy.register_category!("test.gated_action")
    ::Ai::InterventionPolicy.create!(
      account: account, action_category: "test.gated_action",
      scope: "global", policy: "require_approval", priority: 5, is_active: true
    )

    stub_const("PermissionSpecExecutor", Class.new do
      class << self
        attr_accessor :ran
      end

      def self.execute(_params, deferred_operation:)
        self.ran = true
        { ok: true }
      end

      def self.preview(_params, deferred_operation: nil)
        { summary: "gated action" }
      end
    end)
    PermissionSpecExecutor.ran = false
  end

  let!(:gate_result) do
    ::Ai::AutonomyGate.evaluate(
      action_category: "test.gated_action",
      executor_class: "PermissionSpecExecutor",
      params: {},
      account: account,
      requested_by: approver,
      description: "a gated action awaiting approval"
    )
  end

  let(:deferred) { gate_result.deferred_operation }
  let(:approval_request) { deferred.approval_request }

  # Ai::Autonomy::ApprovalWorkflowService is capability-gated: without this,
  # approve/reject return false and EVERY assertion below — including the
  # positive control that a permitted caller still succeeds — would be vacuous.
  # Declared after the let! above so the gate itself is evaluated exactly as it
  # is on the ungoverned path (mirrors approval_reveal_once_spec.rb).
  before do
    allow(Shared::FeatureGateService).to receive(:capability_present?).and_call_original
    allow(Shared::FeatureGateService).to receive(:capability_present?).with(:governance).and_return(true)
  end

  it "starts from a genuinely pending, unexecuted operation (premise of the rest)" do
    expect(gate_result.decision).to eq(:pending)
    expect(deferred.reload.status).to eq("pending")
    expect(approval_request).to be_present
    expect(approval_request.status).to eq("pending")
    expect(PermissionSpecExecutor.ran).to be(false)
  end

  describe "the reported bypass: approving without ai.autonomy.approve" do
    it "refuses approve_deferred_operation and leaves the operation unexecuted" do
      result = run_expecting_refusal("approve_deferred_operation", { "deferred_operation_id" => deferred.id }, user: reader)

      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/permission denied/i)
      expect(result[:error]).to include("ai.autonomy.approve")

      expect(approval_request.reload.status).to eq("pending")
      expect(deferred.reload.status).to eq("pending")
      expect(PermissionSpecExecutor.ran).to be(false)
    end

    it "refuses reject_deferred_operation from the same caller" do
      result = run_expecting_refusal("reject_deferred_operation", { "deferred_operation_id" => deferred.id }, user: reader)

      expect(result[:success]).to be(false)
      expect(approval_request.reload.status).to eq("pending")
    end

    # The sharp end. A user principal is deliberately NOT pinned to the invoked
    # tool name (McpPlatformToolRegistrar#action_pinned_to_name?), on the
    # reasoning that one REQUIRED_PERMISSION covers every sibling action so
    # smuggling gains nothing. That reasoning stops holding the moment
    # permissions differ per action, so the gate must key on the action that
    # RUNS, never on the name that was invoked.
    it "refuses an approval smuggled in under a benign tool name" do
      result = run_expecting_refusal(
        "agent_introspect",
        { "action" => "approve_deferred_operation", "deferred_operation_id" => deferred.id },
        user: reader
      )

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("ai.autonomy.approve")
      expect(approval_request.reload.status).to eq("pending")
      expect(deferred.reload.status).to eq("pending")
      expect(PermissionSpecExecutor.ran).to be(false)
    end
  end

  describe "the same shape on the other privileged actions" do
    let!(:policy) do
      ::Ai::InterventionPolicy.create!(
        account: account, action_category: "test.gated_action",
        scope: "global", policy: "silent", priority: 1, is_active: true
      )
    end

    it "refuses delete_intervention_policy and leaves the policy in place" do
      result = run_expecting_refusal("delete_intervention_policy", { "policy_id" => policy.id }, user: reader)

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("ai.intervention_policies.manage")
      expect(::Ai::InterventionPolicy.exists?(policy.id)).to be(true)
    end

    # request_code_change writes an assistant message into a workspace
    # conversation, which platform.send_message gates on ai.conversations.create.
    # The two refusals are distinguishable without any conversation fixture: a
    # permitted caller gets past the gate and fails on the missing session
    # instead, which is what separates "gated" from "broken".
    it "refuses request_code_change without ai.conversations.create" do
      refused = run_expecting_refusal(
        "request_code_change", { "description" => "do the thing" }, user: reader, mcp_agent: agent
      )
      expect(refused[:success]).to be(false)
      expect(refused[:error]).to include("ai.conversations.create")

      permitted_caller = create(:user, account: account, permissions: %w[ai.agents.read ai.conversations.create])
      allowed = run("request_code_change", { "description" => "do the thing" }, user: permitted_caller, mcp_agent: agent)
      expect(allowed[:success]).to be(false)
      expect(allowed[:error]).not_to include("permission denied")
      expect(allowed[:error]).to match(/session/i)
    end

    it "refuses create_agent_goal without ai.goals.manage and writes no goal" do
      expect {
        result = run_expecting_refusal(
          "create_agent_goal",
          { "agent_id" => agent.id, "title" => "unauthorized goal", "goal_type" => "improvement" },
          user: reader
        )
        expect(result[:success]).to be(false)
        expect(result[:error]).to include("ai.goals.manage")
      }.not_to change { ::Ai::AgentGoal.where(account_id: account.id).count }
    end
  end

  describe "authentication, which the nil constant also skipped" do
    it "refuses a call carrying no user at all" do
      expect {
        run("approve_deferred_operation", { "deferred_operation_id" => deferred.id }, user: nil)
      }.to raise_error(::Mcp::ProtocolService::PermissionDeniedError, /Authentication required/)

      expect(approval_request.reload.status).to eq("pending")
      expect(PermissionSpecExecutor.ran).to be(false)
    end

    it "refuses a user holding no permissions at the tool floor" do
      expect {
        run("agent_introspect", { "agent_id" => agent.id }, user: unprivileged)
      }.to raise_error(::Mcp::ProtocolService::PermissionDeniedError, /ai\.agents\.read/)
    end
  end

  # CONTROLS. These pass on unmodified HEAD (where nothing is gated at all), so
  # they are not evidence that the gate exists — they are the guard against
  # over-tightening, which a refusal-only suite cannot see.
  describe "callers who legitimately hold the permission are unaffected" do
    it "still approves for a caller with ai.autonomy.approve, and the operation executes" do
      result = run("approve_deferred_operation", { "deferred_operation_id" => deferred.id }, user: approver)

      expect(result[:success]).to be(true)
      expect(approval_request.reload.status).to eq("approved")
      expect(PermissionSpecExecutor.ran).to be(true)
    end

    it "still manages intervention policies for a caller with ai.intervention_policies.manage" do
      result = run(
        "create_intervention_policy",
        { "scope" => "global", "action_category" => "test.gated_action", "policy" => "silent" },
        user: policy_admin
      )

      expect(result[:success]).to be(true)
    end

    it "still creates and lists goals for a caller with ai.goals.manage" do
      created = run(
        "create_agent_goal",
        { "agent_id" => agent.id, "title" => "legitimate goal", "goal_type" => "improvement" },
        user: goal_manager
      )
      expect(created[:success]).to be(true)

      listed = run("list_agent_goals", { "agent_id" => agent.id }, user: goal_manager)
      expect(listed[:success]).to be(true)
      expect(listed[:data][:goals].map { |g| g[:title] }).to include("legitimate goal")
    end

    it "keeps the read actions usable at the floor" do
      introspect = run("agent_introspect", { "agent_id" => agent.id }, user: reader)
      expect(introspect[:success]).to be(true)

      listed = run("list_deferred_operations", {}, user: reader)
      expect(listed[:success]).to be(true)
      expect(listed[:operations].map { |o| o[:id] }).to include(deferred.id)
    end

    # The agent-voice actions (escalate, report_issue, propose_feature,
    # notifications, code-change requests, session discovery) have no REST twin
    # at all — no human surface creates an escalation — so parity says nothing
    # about them and they stay at the tool floor. Pinned so a later tightening
    # of the map is a deliberate act rather than a side effect.
    it "keeps the agent-voice actions at the floor" do
      result = run("discover_claude_sessions", {}, user: reader, mcp_agent: agent)
      expect(result[:success]).to be(true)
    end

    # An mTLS node principal carries no User at all, so a floor that refused it
    # would hard-deny every fleet node the moment this shipped — the same
    # regression BUG-R recorded for dev_next_task. Its authorization is the
    # name-scoped grant the streamable controller already checked, which
    # enforce_permission! honours above the has_permission? raise and
    # action_permitted? honours in turn.
    it "still serves an instance principal, whose grant is name-scoped" do
      result = ::Ai::Tools::McpPlatformToolRegistrar.execute_tool(
        "platform.list_deferred_operations",
        params: {}, account: account, user: nil, instance_authorized: true
      )

      expect(result[:success]).to be(true)
    end

    # An instance principal has no User, so has_permission? has nothing to ask
    # about and action_permitted? waives the per-action check for it. The bound
    # is the deny overlay, which refuses these names to EVERY instance whatever
    # it was granted (IMP-e8adfcfcab9b extended it to the approval gate itself).
    # Without this the user path would be closed and the mTLS path left open.
    it "refuses an instance principal the approval actions, whatever it was granted" do
      %w[approve_deferred_operation reject_deferred_operation].each do |action|
        expect {
          ::Ai::Tools::McpPlatformToolRegistrar.execute_tool(
            "platform.#{action}",
            params: { "deferred_operation_id" => deferred.id },
            account: account, user: nil, instance_authorized: true
          )
        }.to raise_error(::Mcp::ProtocolService::PermissionDeniedError, /destroy-shaped|not permitted/)
      end

      expect(approval_request.reload.status).to eq("pending")
      expect(PermissionSpecExecutor.ran).to be(false)
    end

    # The sharper half: an intervention policy decides whether anything needs
    # approval at all, so one auto_approve/global row makes every later gate
    # vacuous. delete_ was already covered by *delete*; create_/update_ were not.
    it "refuses an instance principal the intervention-policy writes" do
      %w[create_intervention_policy update_intervention_policy].each do |action|
        expect {
          ::Ai::Tools::McpPlatformToolRegistrar.execute_tool(
            "platform.#{action}",
            params: { "scope" => "global", "action_category" => "test.gated_action", "policy" => "auto_approve" },
            account: account, user: nil, instance_authorized: true
          )
        }.to raise_error(::Mcp::ProtocolService::PermissionDeniedError)
      end

      expect(account.ai_intervention_policies.where(policy: "auto_approve")).to be_empty
    end

    # ...and the reads it legitimately holds are NOT swept up by those patterns
    # (they are plural: list_deferred_operations, list_intervention_policies).
    it "keeps an instance principal's read surface" do
      result = ::Ai::Tools::McpPlatformToolRegistrar.execute_tool(
        "platform.list_intervention_policies",
        params: {}, account: account, user: nil, instance_authorized: true
      )

      expect(result[:success]).to be(true)
    end

    # ...and that grant is still the bound: the registrar pins an instance's
    # action to the name it invoked, so the smuggling route stays shut for the
    # principal whose per-action check is deliberately waived.
    it "refuses an instance principal an action it did not invoke by name" do
      expect {
        ::Ai::Tools::McpPlatformToolRegistrar.execute_tool(
          "platform.list_deferred_operations",
          params: { "action" => "approve_deferred_operation", "deferred_operation_id" => deferred.id },
          account: account, user: nil, instance_authorized: true
        )
      }.to raise_error(::Mcp::ProtocolService::PermissionDeniedError, /not permitted/)

      expect(approval_request.reload.status).to eq("pending")
      expect(PermissionSpecExecutor.ran).to be(false)
    end
  end

  describe "the map itself" do
    it "no longer waves the whole tool through enforce_permission!" do
      expect(tool_class::REQUIRED_PERMISSION).to eq("ai.agents.read")
    end

    it "pins each privileged action to the permission its REST twin requires" do
      map = tool_class::ACTION_PERMISSIONS

      # POST /api/v1/ai/autonomy/approvals/:id/{approve,reject}
      #   → Ai::AutonomyApprovalActions#require_approval_permission
      expect(map.fetch("approve_deferred_operation")).to eq("ai.autonomy.approve")
      expect(map.fetch("reject_deferred_operation")).to eq("ai.autonomy.approve")

      # Api::V1::Ai::InterventionPoliciesController#validate_permissions (all actions)
      %w[list_intervention_policies create_intervention_policy
         update_intervention_policy delete_intervention_policy].each do |action|
        expect(map.fetch(action)).to eq("ai.intervention_policies.manage")
      end

      # Api::V1::Ai::GoalsController / GoalPlansController#validate_permissions
      %w[create_agent_goal list_agent_goals update_agent_goal
         decompose_goal].each do |action|
        expect(map.fetch(action)).to eq("ai.goals.manage")
      end

      # validate_plan / approve_plan were unregistered in IMP-4707960fc610 —
      # both constantized services that exist nowhere, so neither ever did
      # anything but return "service not available".
      expect(map).not_to have_key("validate_plan")
      expect(map).not_to have_key("approve_plan")

      # request_code_change writes a conversation message, which is what
      # Ai::Tools::ConversationTool gates — read from that class rather than
      # restated, so the two cannot drift apart.
      expect(map.fetch("request_code_change")).to eq(::Ai::Tools::ConversationTool::REQUIRED_PERMISSION)
    end

    # Advertisement must not depend on the floor: BaseTool's default would make
    # the whole surface vanish from an agent in an account where no user holds
    # ai.agents.read, taking escalate and report_issue with it.
    it "stays advertised to agents regardless of who holds the floor permission" do
      expect(tool_class.permitted?(agent: agent)).to be(true)

      allow_any_instance_of(User).to receive(:has_permission?).and_return(false)
      expect(tool_class.permitted?(agent: agent)).to be(true)
      expect(::Ai::Tools::PlatformApiToolRegistry.available_tools(agent: agent))
        .to include("escalate" => tool_class)
    end

    it "maps only actions this tool actually serves" do
      expect(tool_class::ACTION_PERMISSIONS.keys - tool_class.action_definitions.keys).to be_empty
    end

    # Asserting that required_perm_for returns SOMETHING for every action would
    # be a tautology: it falls back to the floor, so it is non-nil for every
    # input including a misspelled key or an action nobody remembered to map.
    # The check that can actually fail is the inverse — a write- or
    # approval-shaped action added to the registry later must not land at the
    # floor by default.
    it "leaves no write- or approval-shaped action at the floor" do
      registry_actions = ::Ai::Tools::PlatformApiToolRegistry.all_tools
        .select { |_name, klass| klass == tool_class.name }.keys
      expect(registry_actions).not_to be_empty

      # The agent-voice actions are write-shaped by NAME but have no REST twin,
      # so the floor is their deliberate home (see the map's own comment). This
      # is the one list that has to be maintained by hand; everything else the
      # heuristic catches.
      agent_voice = %w[
        create_proposal propose_feature escalate report_issue request_feedback
        send_proactive_notification request_code_change discover_claude_sessions
      ]

      # HIER-P0 widened the prefix set: set_delegation_policy was the first
      # `set_`-shaped write this tool serves, and the old alternation
      # (create|update|delete|approve|reject) matched nothing for it — the
      # guard would have passed with the verb sitting at the ai.agents.read
      # floor. `assign|grant|revoke` are added for the same reason, before a
      # write arrives wearing one of them.
      write_shaped = registry_actions.grep(/\A(create|update|delete|approve|reject|set|assign|grant|revoke)_/) - agent_voice
      expect(write_shaped).not_to be_empty # premise: the heuristic matches something

      unmapped = write_shaped - tool_class::ACTION_PERMISSIONS.keys
      expect(unmapped).to be_empty, "write-shaped actions left at the tool floor: #{unmapped.join(', ')}"
    end
  end
end
