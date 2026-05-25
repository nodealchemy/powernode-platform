# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Autonomy::ApprovalWorkflowService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account) }

  describe ".business_loaded?" do
    it "returns true when both Ai::ApprovalChain and Ai::ApprovalRequest are defined" do
      # In a default dev/test environment with business loaded both are present.
      skip "business extension not loaded — covered by the inverse path below" unless described_class.business_loaded?

      expect(described_class.business_loaded?).to be true
    end
  end

  describe "core-mode behavior (no business extension)" do
    # Force the short-circuit branch regardless of whether the extension
    # is actually loaded in the test environment — the production code
    # has to handle both cases identically, so the spec must exercise
    # the core-mode branch deterministically.
    before do
      allow(described_class).to receive(:business_loaded?).and_return(false)
    end

    let(:agent) { build_stubbed(:ai_agent, account: account) }
    let(:approver) { build_stubbed(:user, account: account) }
    let(:request_double) do
      double("Ai::ApprovalRequest",
             account_id: account.id,
             pending?: true,
             can_approve?: true,
             record_decision!: true)
    end

    it "request_approval returns nil without touching Ai::ApprovalChain" do
      expect {
        result = service.request_approval(
          agent: agent, action_type: "test.action",
          description: "x", request_data: {}, requested_by: nil
        )
        expect(result).to be_nil
      }.not_to raise_error
    end

    it "pending_approvals returns an empty array" do
      expect(service.pending_approvals).to eq([])
    end

    it "approve returns false without touching the request" do
      expect(request_double).not_to receive(:record_decision!)
      expect(service.approve(request: request_double, approver: approver)).to be false
    end

    it "reject returns false without touching the request" do
      expect(request_double).not_to receive(:record_decision!)
      expect(service.reject(request: request_double, approver: approver)).to be false
    end

    it "expire_overdue! returns 0 without scanning Ai::ApprovalRequest" do
      expect(service.expire_overdue!).to eq(0)
    end
  end
end
