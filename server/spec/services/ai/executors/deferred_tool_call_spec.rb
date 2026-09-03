# frozen_string_literal: true

require "rails_helper"

# APO-1b (IMP-ce0dcca3f19a). A declared mutating action that the AutonomyGate parks
# must be replayable on approval AS THE ORIGINAL PRINCIPAL, with the caller's params
# (operation_id, blast-radius name prefix, …) intact through the JSONB round trip —
# and must REFUSE, as a result rather than a raise, when that principal has since
# lost the permission that authorised it.
#
# Design note: docs/concepts/deferred-tool-call-replay.md
RSpec.describe Ai::Executors::DeferredToolCall do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }

  # Records every body invocation together with the provenance the rebuilt tool
  # was carrying, so a replay under the wrong principal is visible.
  let(:sightings) { [] }

  let(:tool_class) do
    seen = sightings
    klass = Class.new(::Ai::Tools::BaseTool) do
      def self.definition
        {
          name: "spec_replay_tool",
          description: "Replay seam probe",
          parameters: { action: { type: "string", required: false } }
        }
      end

      declare_action "spec_replay_write",
                     mutating: true,
                     action_category: "spec.replay.write",
                     executor_class: "Ai::Executors::DeferredToolCall",
                     gate_context: :deferred_tool_call_context,
                     on_proceed: :deferred_tool_call_result

      define_method(:call) do |params|
        seen << {
          params: params,
          user_id: user&.id,
          agent_id: agent&.id,
          instance_authorized: instance_authorized?,
          node_instance_id: node_instance&.id,
          internal: internal?
        }
        success_result(ran: true, operation_id: params[:operation_id])
      end
    end
    klass.const_set(:REQUIRED_PERMISSION, "ai.agents.manage")
    stub_const("SpecReplayTool", klass)
  end

  let(:call_params) do
    { action: "spec_replay_write", operation_id: "op-7f3", name_prefix: "proj-alpha-" }
  end

  before do
    Ai::InterventionPolicy.register_category!("spec.replay.write")
    Ai::InterventionPolicy.create!(
      account: account, action_category: "spec.replay.write",
      scope: "global", policy: "require_approval", priority: 5, is_active: true
    )
    tool_class
  end

  after { ::Mcp::Principal.reset! }

  def park!(tool)
    result = tool.execute(params: call_params)
    expect(result[:success]).to be(true)
    expect(result[:data][:pending]).to be(true)
    Ai::DeferredOperation.find(result[:data][:deferred_operation_id])
  end

  describe "parking (BaseTool#deferred_tool_call_context)" do
    let(:user) { create(:user, account: account, permissions: [ "ai.agents.manage" ]) }

    it "records the tool, the routed action, the caller params and the principal" do
      operation = park!(SpecReplayTool.new(account: account, user: user))

      expect(operation.status).to eq("pending")
      expect(operation.executor_class).to eq("Ai::Executors::DeferredToolCall")
      expect(operation.params["tool_class"]).to eq("SpecReplayTool")
      expect(operation.params["action"]).to eq("spec_replay_write")
      expect(operation.params["tool_params"]).to include(
        "operation_id" => "op-7f3", "name_prefix" => "proj-alpha-"
      )
      expect(operation.params["principal"]).to include("kind" => "user", "user_id" => user.id)
      expect(sightings).to be_empty
    end
  end

  describe "replay as the original principal" do
    let(:user) { create(:user, account: account, permissions: [ "ai.agents.manage" ]) }

    it "runs the tool body once, as that user, with the caller params intact" do
      operation = park!(SpecReplayTool.new(account: account, user: user))

      operation.execute_now!

      expect(sightings.size).to eq(1)
      expect(sightings.first[:user_id]).to eq(user.id)
      expect(sightings.first[:params][:operation_id]).to eq("op-7f3")
      expect(sightings.first[:params][:name_prefix]).to eq("proj-alpha-")
      expect(operation.reload.status).to eq("completed")
    end

    it "does not park a second approval for the same call" do
      operation = park!(SpecReplayTool.new(account: account, user: user))

      expect { operation.execute_now! }.not_to change(Ai::DeferredOperation, :count)
    end

    it "replays an agent-principal call under that agent" do
      create(:user, account: account, permissions: [ "ai.agents.manage" ])
      agent = create(:ai_agent, account: account)
      operation = park!(SpecReplayTool.new(account: account, agent: agent))

      expect(operation.params["principal"]).to include("kind" => "agent", "agent_id" => agent.id)
      operation.execute_now!

      expect(sightings.size).to eq(1)
      expect(sightings.first[:agent_id]).to eq(agent.id)
    end
  end

  describe "refusal when the principal has lost the permission" do
    let(:user) { create(:user, account: account, permissions: [ "ai.agents.manage" ]) }

    it "refuses as a RESULT, does not raise, and never runs the body" do
      operation = park!(SpecReplayTool.new(account: account, user: user))
      user.roles = []

      result = nil
      expect { result = operation.execute_now! }.not_to raise_error

      expect(result[:success]).to be(false)
      expect(result[:refused]).to be(true)
      expect(result[:reason]).to eq("permission_revoked")
      expect(sightings).to be_empty
      expect(operation.reload.status).to eq("completed")
      expect(operation.result["refused"]).to be(true)
    end

    it "refuses when the recorded user is no longer in the operation's account" do
      operation = park!(SpecReplayTool.new(account: account, user: user))
      operation.update!(params: operation.params.merge(
        "principal" => { "kind" => "user", "user_id" => create(:user, account: other_account).id }
      ))

      result = operation.execute_now!

      expect(result[:refused]).to be(true)
      expect(result[:reason]).to eq("principal_unresolvable")
      expect(sightings).to be_empty
    end
  end

  describe "instance principal" do
    let(:node_instance) { double("NodeInstance", id: "aa11bb22-0000-4000-8000-000000000001", account: account) }
    let(:granted) { [ "platform.spec_replay_*" ] }

    before do
      create(:user, account: account) # an approver for the chain the gate opens
      ::Mcp::Principal.instance_resolver = ->(cn) { cn == node_instance.id ? node_instance : nil }
      ::Mcp::Principal.tool_grant_resolver = ->(_i) { granted }
    end

    def instance_tool
      tool = SpecReplayTool.new(account: account)
      tool.instance_authorized = true
      tool.node_instance = node_instance
      tool
    end

    it "records the node instance and replays with the instance provenance re-armed" do
      operation = park!(instance_tool)

      expect(operation.params["principal"]).to include(
        "kind" => "instance", "node_instance_id" => node_instance.id
      )

      operation.execute_now!

      expect(sightings.size).to eq(1)
      expect(sightings.first[:instance_authorized]).to be(true)
      expect(sightings.first[:node_instance_id]).to eq(node_instance.id)
      expect(sightings.first[:user_id]).to be_nil
    end

    it "refuses when the instance's grant no longer covers the action" do
      operation = park!(instance_tool)
      ::Mcp::Principal.tool_grant_resolver = ->(_i) { [] }

      result = operation.execute_now!

      expect(result[:refused]).to be(true)
      expect(result[:reason]).to eq("permission_revoked")
      expect(sightings).to be_empty
    end

    it "refuses when the node instance no longer resolves" do
      operation = park!(instance_tool)
      ::Mcp::Principal.instance_resolver = ->(_cn) { nil }

      result = operation.execute_now!

      expect(result[:refused]).to be(true)
      expect(result[:reason]).to eq("principal_unresolvable")
      expect(sightings).to be_empty
    end
  end

  describe "fail-closed on a malformed parked call" do
    let(:user) { create(:user, account: account, permissions: [ "ai.agents.manage" ]) }

    def operation_with(executor_params)
      Ai::DeferredOperation.create!(
        account: account, action_category: "spec.replay.write",
        executor_class: "Ai::Executors::DeferredToolCall", params: executor_params
      )
    end

    it "refuses a tool_class that is not an Ai::Tools::BaseTool" do
      result = operation_with(
        "tool_class" => "String", "action" => "spec_replay_write",
        "tool_params" => {}, "principal" => { "kind" => "user", "user_id" => user.id }
      ).execute_now!

      expect(result[:refused]).to be(true)
      expect(result[:reason]).to eq("unreplayable_tool")
    end

    it "refuses a tool_class that does not resolve" do
      result = operation_with(
        "tool_class" => "Ai::Tools::NoSuchToolWhatsoever", "action" => "spec_replay_write",
        "tool_params" => {}, "principal" => { "kind" => "user", "user_id" => user.id }
      ).execute_now!

      expect(result[:refused]).to be(true)
      expect(result[:reason]).to eq("unreplayable_tool")
    end

    it "refuses when the parked params would route to a different action than the approved one" do
      result = operation_with(
        "tool_class" => "SpecReplayTool", "action" => "spec_replay_write",
        "tool_params" => { "action" => "spec_replay_something_else" },
        "principal" => { "kind" => "user", "user_id" => user.id }
      ).execute_now!

      expect(result[:refused]).to be(true)
      expect(result[:reason]).to eq("action_mismatch")
      expect(sightings).to be_empty
    end

    it "refuses an unattributed principal rather than replaying it as an internal caller" do
      result = operation_with(
        "tool_class" => "SpecReplayTool", "action" => "spec_replay_write",
        "tool_params" => {}, "principal" => { "kind" => "unattributed" }
      ).execute_now!

      expect(result[:refused]).to be(true)
      expect(result[:reason]).to eq("principal_unresolvable")
      expect(sightings).to be_empty
    end
  end

  # The gate's OTHER branch. On auto_approve/notify_and_proceed AutonomyGate calls
  # #execute_now! itself and BaseTool#deferred_tool_call_result serializes what the
  # executor returned. Nothing else in this file enters it, and it is the only place
  # the "on_proceed must not repeat the work" invariant can fail — a double execution
  # of a gated destructive action would otherwise leave the suite green.
  describe "auto-approve branch (:proceed)" do
    let(:user) { create(:user, account: account, permissions: [ "ai.agents.manage" ]) }

    def set_policy!(policy)
      Ai::InterventionPolicy.find_by(account: account, action_category: "spec.replay.write")
                            .update!(policy: policy)
    end

    %w[auto_approve notify_and_proceed].each do |policy|
      it "runs the body exactly ONCE under #{policy} and returns the tool's own envelope" do
        set_policy!(policy)

        result = SpecReplayTool.new(account: account, user: user).execute(params: call_params)

        expect(sightings.size).to eq(1)
        expect(sightings.first[:user_id]).to eq(user.id)
        expect(result[:success]).to be(true)
        expect(result[:data]).to include(ran: true, operation_id: "op-7f3")
        expect(result[:data][:pending]).to be_nil
      end
    end
  end

  # A nested hop is routinely BOTH an agent call and an in-process one: a skill
  # executor builds every tool it nests with `internal: internal_caller?` while still
  # forwarding the caller's agent. Rebuilding without the flag makes the replay a
  # SHALLOWER call than the one approved, and a tool whose per-action check opens
  # `return true if internal?` then refuses what the operator just granted.
  describe "an internal nested hop carrying an agent" do
    it "records the internal flag and rebuilds the tool with it" do
      create(:user, account: account, permissions: [ "ai.agents.manage" ])
      agent = create(:ai_agent, account: account)
      operation = park!(SpecReplayTool.new(account: account, agent: agent, internal: true))

      expect(operation.params["principal"]).to include(
        "kind" => "agent", "agent_id" => agent.id, "internal" => true
      )

      operation.execute_now!

      expect(sightings.size).to eq(1)
      expect(sightings.first[:internal]).to be(true)
      expect(sightings.first[:agent_id]).to eq(agent.id)
    end

    it "does not invent the flag for a plain agent call" do
      create(:user, account: account, permissions: [ "ai.agents.manage" ])
      agent = create(:ai_agent, account: account)
      operation = park!(SpecReplayTool.new(account: account, agent: agent))

      expect(operation.params["principal"]).to include("internal" => false)
      operation.execute_now!

      expect(sightings.first[:internal]).to be(false)
    end
  end

  # An "unattributed" caller can never be replayed, so it must not be able to PARK
  # an approval an operator then has to dispose of for nothing.
  describe "an unattributed caller" do
    it "is refused at park time and creates no operation" do
      tool = SpecReplayTool.new(account: account)
      tool.instance_authorized = true # federation shape: restricted, no node instance

      result = nil
      expect { result = tool.execute(params: call_params) }
        .not_to change(Ai::DeferredOperation, :count)

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("unattributed")
      expect(sightings).to be_empty
    end
  end

  describe "cross-tenant clauses" do
    let(:user) { create(:user, account: account, permissions: [ "ai.agents.manage" ]) }

    it "refuses an instance principal that resolves into another account" do
      create(:user, account: account)
      node_instance = double("NodeInstance", id: "aa11bb22-0000-4000-8000-000000000009",
                                             account: account)
      ::Mcp::Principal.instance_resolver = ->(cn) { cn == node_instance.id ? node_instance : nil }
      ::Mcp::Principal.tool_grant_resolver = ->(_i) { [ "platform.spec_replay_*" ] }

      tool = SpecReplayTool.new(account: account)
      tool.instance_authorized = true
      tool.node_instance = node_instance
      operation = park!(tool)

      # Same CN, but the instance now belongs to a different tenant.
      foreign = double("NodeInstance", id: node_instance.id, account: other_account)
      ::Mcp::Principal.instance_resolver = ->(_cn) { foreign }

      result = operation.execute_now!

      expect(result[:refused]).to be(true)
      expect(result[:reason]).to eq("principal_unresolvable")
      expect(sightings).to be_empty
    end

    it "refuses an agent_id belonging to another account" do
      operation = park!(SpecReplayTool.new(account: account, user: user))
      operation.update!(params: operation.params.merge(
        "principal" => { "kind" => "agent", "agent_id" => create(:ai_agent, account: other_account).id }
      ))

      result = operation.execute_now!

      expect(result[:refused]).to be(true)
      expect(result[:reason]).to eq("principal_unresolvable")
      expect(sightings).to be_empty
    end
  end

  # BaseTool#approved_replay? is the gate bypass. Each clause is asserted by the
  # OBSERVABLE it protects: a row that does not license the bypass must park a
  # second approval rather than run the body.
  describe "BaseTool#approved_replay? clauses" do
    let(:user) { create(:user, account: account, permissions: [ "ai.agents.manage" ]) }

    def operation_in(target_account, executor_class: "Ai::Executors::DeferredToolCall",
                     status: "approved")
      op = Ai::DeferredOperation.create!(
        account: target_account, action_category: "spec.replay.write",
        executor_class: executor_class, params: {}
      )
      op.update_column(:status, status)
      op
    end

    it "does not bypass the gate for a row from another account" do
      tool = SpecReplayTool.new(account: account, user: user)
      tool.replaying_operation = operation_in(other_account)

      result = tool.execute(params: call_params)

      expect(result[:data][:pending]).to be(true)
      expect(sightings).to be_empty
    end

    it "does not bypass the gate for a row naming a different executor" do
      tool = SpecReplayTool.new(account: account, user: user)
      tool.replaying_operation = operation_in(account, executor_class: "Ai::Executors::SomethingElse")

      result = tool.execute(params: call_params)

      expect(result[:data][:pending]).to be(true)
      expect(sightings).to be_empty
    end

    it "does not bypass the gate for a row that is still pending a decision" do
      tool = SpecReplayTool.new(account: account, user: user)
      tool.replaying_operation = operation_in(account, status: "pending")

      result = tool.execute(params: call_params)

      expect(result[:data][:pending]).to be(true)
      expect(sightings).to be_empty
    end
  end

  # The instance grant was read against the advertised REGISTRY KEY, and
  # McpPlatformToolRegistrar pins the action to the alias TARGET — so for the 25
  # aliased keys the routed action is NOT the granted name.
  describe "the instance re-check is keyed on the granted tool name" do
    let(:node_instance) { double("NodeInstance", id: "aa11bb22-0000-4000-8000-000000000002", account: account) }

    before do
      create(:user, account: account)
      ::Mcp::Principal.instance_resolver = ->(cn) { cn == node_instance.id ? node_instance : nil }
    end

    def parked_with_granted_name(name)
      ::Mcp::Principal.tool_grant_resolver = ->(_i) { [ "platform.*" ] }
      tool = SpecReplayTool.new(account: account)
      tool.instance_authorized = true
      tool.node_instance = node_instance
      operation = park!(tool)
      operation.update!(params: operation.params.deep_merge(
        "principal" => { "granted_tool_name" => name }
      ))
      operation
    end

    it "inverts ACTION_ALIASES so an aliased action records the name the grant was read against" do
      tool = SpecReplayTool.new(account: account)

      expect(tool.send(:granted_tool_name_for, "upsert_node")).to eq("code_upsert_node")
      expect(tool.send(:granted_tool_name_for, "spec_replay_write")).to eq("spec_replay_write")
    end

    # The inversion above is only well defined while the alias TARGETS are
    # unique — Hash#key silently returns the first of a duplicate pair, which
    # would re-check the grant against the wrong tool name. Pin it here rather
    # than leave the next alias addition to discover it in production.
    it "keeps ACTION_ALIASES invertible (targets unique)" do
      targets = ::Ai::Tools::McpPlatformToolRegistrar::ACTION_ALIASES.values

      expect(targets.tally.select { |_k, v| v > 1 }).to eq({})
    end

    it "replays when the grant covers the RECORDED name but not the routed action" do
      operation = parked_with_granted_name("code_upsert_node")
      ::Mcp::Principal.tool_grant_resolver = ->(_i) { [ "platform.code_upsert_node" ] }

      operation.execute_now!

      expect(sightings.size).to eq(1)
    end

    it "refuses when the grant covers only the routed action and not the recorded name" do
      operation = parked_with_granted_name("code_upsert_node")
      ::Mcp::Principal.tool_grant_resolver = ->(_i) { [ "platform.spec_replay_write" ] }

      result = operation.execute_now!

      expect(result[:refused]).to be(true)
      expect(result[:reason]).to eq("permission_revoked")
      expect(sightings).to be_empty
    end
  end

  describe ".preview" do
    it "names the action without dumping the caller params" do
      preview = described_class.preview(
        { "tool_class" => "SpecReplayTool", "action" => "spec_replay_write",
          "tool_params" => { "secret" => "s3kr1t" },
          "principal" => { "kind" => "user", "user_id" => "u-1" } },
        deferred_operation: Ai::DeferredOperation::PreviewContext.new(account)
      )

      expect(preview[:summary]).to include("spec_replay_write")
      expect(preview.values.join(" ")).not_to include("s3kr1t")
    end
  end
end
