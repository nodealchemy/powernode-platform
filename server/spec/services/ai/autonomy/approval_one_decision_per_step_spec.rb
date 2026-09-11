# frozen_string_literal: true

require "rails_helper"

# Separation of duty: one person, one decision per step of an approval request.
# Against the REAL services that decide requests: a second "approved" from the
# same approver used to count toward required_approvals, so one person could
# turn both keys of a two-approval step.
RSpec.describe "Approval decisions: one per approver per step" do
  let(:account) { create(:account) }
  let(:perm) { "system.infra_tasks.control" }
  let!(:first_key) { create(:user, account: account, permissions: [ perm ]) }
  let!(:second_key) { create(:user, account: account, permissions: [ perm ]) }
  let(:request) do
    Ai::ApprovalChain.create!(
      account: account, name: "chain-#{SecureRandom.hex(4)}",
      trigger_type: "autonomy_action", status: "active",
      is_sequential: true, timeout_hours: 4, timeout_action: "reject",
      steps: [ { "name" => "Two keys", "approvers" => [ { "type" => "permission", "value" => perm } ],
                 "required_approvals" => 2 } ]
    ).create_request!(source_type: "X", source_id: SecureRandom.uuid, description: "d")
  end

  # Two racing calls both read the request before either decision landed, so
  # both passed can_approve?. This copy's check is made to see no decision.
  def racing_copy
    Ai::ApprovalRequest.find(request.id).tap do |racing|
      allow(racing).to receive(:decided_current_step?).and_return(false)
    end
  end

  describe Ai::Autonomy::ApprovalWorkflowService do
    let(:service) { described_class.new(account: account) }

    it "refuses the same approver's second approval, so one person cannot turn both keys" do
      expect(service.approve(request: request, approver: first_key)).to be(true)

      expect(service.approve(request: request.reload, approver: first_key)).to be(false)
      expect(request.reload.status).to eq("pending")
      expect(request.step_statuses[0]["current_approvals"]).to eq(1)
      expect(request.decisions.where(approver_id: first_key.id).count).to eq(1)
      # The check itself refuses, not only the index behind it.
      expect(request.can_approve?(first_key)).to be(false)
      expect(request.can_approve?(second_key)).to be(true)
    end

    it "refuses a rejection from an approver who already approved the step" do
      service.approve(request: request, approver: first_key)

      expect(service.reject(request: request.reload, approver: first_key)).to be(false)
      expect(request.reload.status).to eq("pending")
    end

    it "lets a different approver's second approval complete the two-approval step" do
      service.approve(request: request, approver: first_key)

      expect(service.approve(request: request.reload, approver: second_key)).to be(true)
      expect(request.reload.status).to eq("approved")
    end

    it "counts ANY earlier decision as the approver's one decision: abstain, then approve, is refused" do
      request.record_decision!(approver: first_key, decision: "abstained")

      expect(service.approve(request: request.reload, approver: first_key)).to be(false)
      expect(request.decisions.where(approver_id: first_key.id).pluck(:decision)).to eq([ "abstained" ])
    end

    it "counts a delegation as the delegator's one decision: delegate, then approve, is refused" do
      request.record_decision!(approver: first_key, decision: "delegated")

      expect(service.approve(request: request.reload, approver: first_key)).to be(false)
      expect(request.decisions.where(approver_id: first_key.id).pluck(:decision)).to eq([ "delegated" ])
    end

    it "completes 2 of 2 when two different approvers act at once — no lost key" do
      # Both callers loaded the request before either decided, so each holds
      # current_approvals = 0 in memory. Unserialized, the second write of the
      # in-memory tally (1) overwrote the first and left the step stuck at 1 of 2.
      first_view = Ai::ApprovalRequest.find(request.id)
      second_view = Ai::ApprovalRequest.find(request.id)

      expect(service.approve(request: first_view, approver: first_key)).to be(true)
      expect(service.approve(request: second_view, approver: second_key)).to be(true)

      request.reload
      expect(request.decisions.count).to eq(2)
      expect(request.step_statuses[0]["current_approvals"]).to eq(2)
      expect(request.status).to eq("approved")
    end

    it "turns a same-approver race past the check into the same refusal, through the unique index" do
      service.approve(request: request, approver: first_key)

      expect(service.approve(request: racing_copy, approver: first_key)).to be(false)
      expect(request.decisions.where(approver_id: first_key.id).count).to eq(1)
      expect(request.reload.step_statuses[0]["current_approvals"]).to eq(1)
    end

    it "refuses a decision on a copy loaded before another approver rejected the request — the lock re-reads the row" do
      stale = Ai::ApprovalRequest.find(request.id)
      expect(service.reject(request: request, approver: first_key)).to be(true)

      # The stale copy still says pending, so it passes every check made before the lock.
      expect(service.approve(request: stale, approver: second_key)).to be(false)
      expect(request.reload.status).to eq("rejected")
      expect(request.decisions.where(approver_id: second_key.id)).to be_empty
    end

    it "tallies the step's approval rows, not the stored counter" do
      # A counter that claims one approval with no row behind it.
      statuses = request.step_statuses.deep_dup
      statuses[0]["current_approvals"] = 1
      request.update_columns(step_statuses: statuses)

      expect(service.approve(request: request.reload, approver: first_key)).to be(true)
      expect(request.reload.status).to eq("pending")
      expect(request.step_statuses[0]["current_approvals"]).to eq(1)
    end
  end

  describe Ai::GovernanceService do
    let(:service) { described_class.new(account) }

    it "refuses the same approver's second decision" do
      expect(service.process_approval_decision(request: request, user: first_key, decision: "approved")[:success]).to be(true)

      expect(service.process_approval_decision(request: request.reload, user: first_key, decision: "approved")[:success]).to be(false)
      expect(request.decisions.where(approver_id: first_key.id).count).to eq(1)
    end

    it "reports a same-approver race past the check as a refusal, never as a success" do
      service.process_approval_decision(request: request, user: first_key, decision: "approved")

      result = service.process_approval_decision(request: racing_copy, user: first_key, decision: "approved")
      expect(result[:success]).to be(false)
      expect(request.decisions.where(approver_id: first_key.id).count).to eq(1)
    end
  end
end
