# frozen_string_literal: true

require "rails_helper"

# secreview §21 G3. A timeout is no person. On a chain whose timeout_action is
# "approve", a request that needs a person's own session (category-marked by
# Ai::Approvals::HumanSessionPolicy, or a human-only tool action) is rejected
# when it times out, so it never runs, as the requester or anyone. An unmarked
# request on the same kind of chain still times out to approved and runs.
RSpec.describe "A timeout never satisfies a human-session requirement (secreview §21 G3)" do
  let(:account) { create(:account) }
  let!(:requester) { create(:user, account: account) }
  let(:runs) { [] }
  let(:sightings) { [] }

  let(:human_tool_class) do
    seen = sightings
    klass = Class.new(::Ai::Tools::BaseTool) do
      def self.definition
        { name: "spec_timeout_human_tool", description: "human-only probe",
          parameters: { action: { type: "string", required: false } } }
      end

      declare_action "spec_timeout_write",
                     mutating: true, human_only: true,
                     action_category: "spec.timeout.human",
                     executor_class: "Ai::Executors::DeferredToolCall",
                     gate_context: :deferred_tool_call_context,
                     on_proceed: :deferred_tool_call_result

      define_method(:call) do |_params|
        seen << { user_id: user&.id }
        success_result(ran: true)
      end
    end
    klass.const_set(:REQUIRED_PERMISSION, "ai.agents.manage")
    stub_const("SpecTimeoutHumanTool", klass)
  end

  before do
    seen = runs
    stub_const("SpecTimeoutExecutor", Class.new do
      define_singleton_method(:execute) do |_params, deferred_operation:|
        seen << deferred_operation.id
        { success: true }
      end
    end)
    %w[spec.node_decommission spec.timeout.plain spec.timeout.human].each do |category|
      Ai::InterventionPolicy.register_category!(category)
    end
  end

  def park!(category)
    gate = Ai::AutonomyGate.evaluate(action_category: category, executor_class: "SpecTimeoutExecutor",
                                     params: {}, account: account, requested_by: requester)
    expect(gate.decision).to eq(:pending)
    gate.approval_request
  end

  def time_out!(request)
    request.approval_chain.update!(timeout_action: "approve")
    request.update_column(:expires_at, 1.hour.ago)
    request.reload.check_expiration!
    request.reload
  end

  it "rejects a category-marked request on an approve-on-timeout chain, and runs nothing" do
    request = park!("spec.node_decommission")
    expect(request.requires_human_session?).to be(true)

    expect(time_out!(request).status).to eq("rejected")
    expect(runs).to be_empty
  end

  it "rejects a human-only tool action on an approve-on-timeout chain, and runs nothing" do
    tool = human_tool_class.new(account: account, user: requester)
    tool.call_origin = "mcp_oauth"
    parked = tool.execute(params: { action: "spec_timeout_write" })
    expect(parked[:data]).to include(pending: true, requires_human_session: true)
    operation = Ai::DeferredOperation.find(parked[:data][:deferred_operation_id])

    expect(time_out!(operation.approval_request).status).to eq("rejected")
    expect(operation.reload.status).to eq("rejected")
    expect(sightings).to be_empty
  end

  it "still times an unmarked request out to approved on the same kind of chain, and runs it (the other arm)" do
    request = park!("spec.timeout.plain")
    expect(request.requires_human_session?).to be(false)

    expect(time_out!(request).status).to eq("approved")
    expect(runs).to eq([ request.source_id ])
  end
end
