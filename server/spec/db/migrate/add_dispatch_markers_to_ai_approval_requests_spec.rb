# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260929121500_add_dispatch_markers_to_ai_approval_requests.rb")

# IMP-0213523480d1 — the backfill marks a request as OWED a dispatch only where
# existing rows prove the dispatch never ran: an approved request with no
# declared outcome whose Ai::DeferredOperation is still pending. Every other
# shape must stay unmarked, because the reconciler FAILS what this marks.
#
# The rows here are legacy rows — written before the stamps existed — so they
# are built by writing the columns such a row carries, not through the
# approval path (which would now stamp them itself).
RSpec.describe AddDispatchMarkersToAiApprovalRequests do
  subject(:migration) { described_class.new }

  let(:account) { create(:account) }
  let(:chain) do
    Ai::ApprovalChain.create!(
      account: account, name: "chain-#{SecureRandom.hex(4)}", trigger_type: "autonomy_action",
      status: "active", is_sequential: true, timeout_hours: 4, timeout_action: "reject",
      steps: [ { "name" => "s", "approvers" => [ "*" ], "required_approvals" => 1 } ]
    )
  end

  before { allow(migration).to receive(:say) }

  def legacy_request(source_type:, source_id:, status:, execution_status: nil)
    request = chain.create_request!(source_type: source_type, source_id: source_id, description: "d")
    request.update_columns(status: status, execution_status: execution_status, completed_at: 1.day.ago)
    request
  end

  def legacy_operation_request(op_status:, status: "approved", execution_status: nil)
    op = Ai::DeferredOperation.create!(account: account, action_category: "test.act", executor_class: "X")
    op.update_columns(status: op_status)
    legacy_request(source_type: "Ai::DeferredOperation", source_id: op.id,
                   status: status, execution_status: execution_status)
  end

  it "marks an approved request whose deferred operation never left pending" do
    stranded = legacy_operation_request(op_status: "pending")

    migration.backfill_owed_dispatches

    expect(stranded.reload.dispatch_scheduled_at).to be_within(1.second).of(stranded.completed_at)
    expect(stranded.dispatch_started_at).to be_nil
  end

  it "leaves every other shape unmarked" do
    ran = legacy_operation_request(op_status: "completed", execution_status: "succeeded")
    noop = legacy_operation_request(op_status: "completed")
    failed = legacy_operation_request(op_status: "pending", execution_status: "failed")
    still_pending = legacy_operation_request(op_status: "pending", status: "pending")
    other_source = legacy_request(source_type: "Ai::CampaignLand", source_id: SecureRandom.uuid, status: "approved")

    migration.backfill_owed_dispatches

    [ ran, noop, failed, still_pending, other_source ].each do |request|
      expect(request.reload.dispatch_scheduled_at).to be_nil
    end
  end
end
