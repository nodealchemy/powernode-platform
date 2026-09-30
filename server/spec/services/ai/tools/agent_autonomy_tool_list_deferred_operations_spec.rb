# frozen_string_literal: true

require "rails_helper"

# IMP-510a142014cc — list_deferred_operations listed the whole account's queue
# to every caller, while its single-row twin get_approval_request already
# limits an instance principal to the requests it originated. The list now
# answers an instance principal with ONLY the operations whose recorded
# principal block names that instance, through the same predicate as the
# single read, applied in SQL so `limit` and `count` describe the filtered set.
RSpec.describe "agent_autonomy list_deferred_operations" do
  let(:account) { create(:account) }
  let(:reader)  { create(:user, account: account, permissions: %w[ai.agents.read]) }
  let(:decider) { create(:user, account: account, permissions: %w[ai.agents.read ai.autonomy.approve]) }

  let(:instance_a) { Struct.new(:id).new(SecureRandom.uuid) }
  let(:instance_b) { Struct.new(:id).new(SecureRandom.uuid) }

  before do
    ::Ai::InterventionPolicy.register_category!("test.gated_action")
    ::Ai::InterventionPolicy.create!(
      account: account, action_category: "test.gated_action",
      scope: "global", policy: "require_approval", priority: 5, is_active: true
    )
    stub_const("ListDeferredSpecExecutor", Class.new do
      def self.execute(_params, deferred_operation:) = { ok: true }
      def self.preview(_params, deferred_operation: nil) = { summary: "gated action" }
    end)
  end

  def park(principal:, agent: nil)
    ::Ai::AutonomyGate.evaluate(
      action_category: "test.gated_action",
      executor_class: "ListDeferredSpecExecutor",
      params: { "tool_class" => "Ai::Tools::SdwanTool", "action" => "x",
                "tool_params" => {}, "principal" => principal },
      account: account,
      agent: agent,
      requested_by: decider,
      description: "a gated action awaiting approval"
    ).deferred_operation
  end

  def instance_principal(node_instance)
    { "kind" => "instance", "node_instance_id" => node_instance.id }
  end

  def run(params = {}, user: reader)
    ::Ai::Tools::McpPlatformToolRegistrar.execute_tool(
      "platform.list_deferred_operations", params: params, account: account, user: user
    )
  end

  def run_as_instance(params = {}, node_instance:)
    ::Ai::Tools::McpPlatformToolRegistrar.execute_tool(
      "platform.list_deferred_operations", params: params, account: account, user: nil,
                                           instance_authorized: true, node_instance: node_instance
    )
  end

  def ids_of(result) = result[:operations].map { |op| op[:id] }

  describe "instance principal scoping" do
    let!(:a_ops)   { Array.new(2) { park(principal: instance_principal(instance_a)) } }
    let!(:b_ops)   { Array.new(3) { park(principal: instance_principal(instance_b)) } }
    let!(:user_op) { park(principal: { "kind" => "user", "user_id" => decider.id }) }

    it "lists only the operations each instance itself parked, and counts only those" do
      as_a = run_as_instance(node_instance: instance_a)
      as_b = run_as_instance(node_instance: instance_b)

      expect(as_a[:success]).to be(true)
      expect(ids_of(as_a)).to match_array(a_ops.map(&:id))
      expect(as_a[:count]).to eq(2)
      expect(ids_of(as_b)).to match_array(b_ops.map(&:id))
      expect(as_b[:count]).to eq(3)
    end

    it "still lists the whole account's queue to a user" do
      as_user = run

      expect(ids_of(as_user)).to match_array((a_ops + b_ops + [ user_op ]).map(&:id))
      expect(as_user[:count]).to eq(6)
    end

    it "applies limit AFTER the filter, so newer operations of another instance do not crowd out its own" do
      # b_ops are the newest rows; a filter applied after the limit would hand
      # instance A an empty page.
      page = run_as_instance({ "limit" => 1 }, node_instance: instance_a)

      expect(ids_of(page)).to eq([ a_ops.last.id ])
      expect(page[:count]).to eq(1)
    end

    it "composes the instance filter with the status filter" do
      a_ops.first.update!(status: "rejected")

      pending = run_as_instance({ "status" => "pending" }, node_instance: instance_a)

      expect(ids_of(pending)).to eq([ a_ops.last.id ])
      expect(pending[:count]).to eq(1)
    end

    it "lists nothing for a restricted principal with no node instance" do
      result = run_as_instance(node_instance: nil)

      expect(result).to include(success: true, count: 0, operations: [])
    end

    it "does not list a row whose principal block is not a Hash" do
      stray = park(principal: instance_principal(instance_a))
      stray.update_columns(params: stray.params.merge("principal" => instance_a.id))

      expect(ids_of(run_as_instance(node_instance: instance_a))).not_to include(stray.id)
    end
  end

  describe "agent filter" do
    let(:provider) { create(:ai_provider, account: account) }
    let(:agent)    { create(:ai_agent, account: account, provider: provider, creator: reader) }

    it "composes the instance filter with the agent filter" do
      mine  = park(principal: instance_principal(instance_a), agent: agent)
      park(principal: instance_principal(instance_a))
      park(principal: instance_principal(instance_b), agent: agent)

      result = run_as_instance({ "agent_id" => agent.id }, node_instance: instance_a)

      expect(ids_of(result)).to eq([ mine.id ])
      expect(result[:count]).to eq(1)
    end
  end

  # The examples above hand-build the principal block. These park through a
  # REAL gated action, so a tool-gate park that stops stamping the instance
  # breaks the list's scoping here rather than passing unseen.
  describe "instance principal scoping, parked through a real gated action" do
    let(:provider) { create(:ai_provider, account: account) }
    let(:target)   { create(:ai_agent, account: account, name: "Ops Worker", provider: provider, creator: reader) }

    before do
      allow(Shared::FeatureGateService).to receive(:capability_present?).and_call_original
      allow(Shared::FeatureGateService).to receive(:capability_present?).with(:governance).and_return(true)
    end

    def park_as_instance(node_instance)
      ::Ai::Tools::McpPlatformToolRegistrar.execute_tool(
        "platform.set_delegation_policy",
        params: { "agent_id" => target.id, "max_depth" => 2 },
        account: account, user: nil, instance_authorized: true, node_instance: node_instance,
        origin: "mcp_instance"
      )
    end

    it "lists the parking instance's operation to it and not to another instance" do
      parked = park_as_instance(instance_a)
      expect(parked[:success]).to be(true), parked.inspect
      operation_id = parked.dig(:data, :deferred_operation_id)
      expect(operation_id).to be_present

      expect(ids_of(run_as_instance(node_instance: instance_a))).to eq([ operation_id ])
      expect(run_as_instance(node_instance: instance_b)).to include(count: 0, operations: [])
      expect(ids_of(run)).to include(operation_id)
    end
  end
end
