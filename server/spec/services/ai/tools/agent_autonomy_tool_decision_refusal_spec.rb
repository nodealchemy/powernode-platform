# frozen_string_literal: true

require "rails_helper"

# The MCP approval door. A tool result is appended to the conversation and sent
# to the model provider, so a refused decision is success: false with a fixed
# message (it used to be success: true, workflow: false), and a raised error
# reaches the result without its class or driver text (it used to echo both).
RSpec.describe "agent_autonomy MCP decisions: refusals and errors" do
  let(:account) { create(:account) }
  let(:perm) { "system.infra_tasks.control" }
  let!(:approver) { create(:user, account: account, permissions: [ "ai.agents.read", "ai.autonomy.approve", perm ]) }
  let!(:request_row) do
    Ai::ApprovalChain.create!(
      account: account, name: "chain-#{SecureRandom.hex(4)}",
      trigger_type: "autonomy_action", status: "active",
      is_sequential: true, timeout_hours: 4, timeout_action: "reject",
      steps: [ { "name" => "Two keys", "approvers" => [ { "type" => "permission", "value" => perm } ],
                 "required_approvals" => 2 } ]
    ).create_request!(source_type: "X", source_id: SecureRandom.uuid, description: "d")
  end
  let(:leak) { /RecordNotUnique|StatementInvalid|PG::|UniqueViolation|duplicate key|constraint|idx_/i }

  def run(action)
    ::Ai::Tools::McpPlatformToolRegistrar.execute_tool(
      "platform.#{action}",
      params: { "deferred_operation_id" => request_row.id },
      account: account,
      user: approver
    )
  end

  it "approves on the first call and refuses the same approver's second with a fixed message" do
    first = run("approve_deferred_operation")
    expect(first[:success]).to be(true)
    expect(first[:request_status]).to eq("pending")

    second = run("approve_deferred_operation")
    expect(second).to include(success: false, error: "Cannot approve this request")
    expect(second).not_to have_key(:workflow)
    expect(second.to_s).not_to match(leak)
    expect(request_row.decisions.count).to eq(1)
  end

  it "rejects on the first call" do
    result = run("reject_deferred_operation")

    expect(result[:success]).to be(true)
    expect(result[:request_status]).to eq("rejected")
  end

  it "refuses a rejection from the approver who already approved, with a fixed message" do
    run("approve_deferred_operation")

    result = run("reject_deferred_operation")
    expect(result).to include(success: false, error: "Cannot reject this request")
    expect(request_row.reload.status).to eq("pending")
  end

  { "approve" => "Approval failed", "reject" => "Rejection failed" }.each do |verb, message|
    it "keeps a raised error's class and driver text out of a failed #{verb}, and logs them" do
      error = ActiveRecord::StatementInvalid.new(
        'PG::UniqueViolation: ERROR: duplicate key value violates unique constraint "idx_probe"'
      )
      allow_any_instance_of(Ai::Autonomy::ApprovalWorkflowService).to receive(verb.to_sym).and_raise(error)
      allow(Rails.logger).to receive(:error).and_call_original

      result = run("#{verb}_deferred_operation")

      expect(result).to include(success: false, error: message)
      expect(result.to_s).not_to match(leak)
      expect(Rails.logger).to have_received(:error)
        .with(/#{verb}_deferred_operation failed: ActiveRecord::StatementInvalid: PG::UniqueViolation/)
    end
  end
end
