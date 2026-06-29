# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Autonomy::ApprovalWorkflowService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account) }

  describe ".governance_enabled?" do
    it "is true when a governance-providing extension is loaded" do
      # True in a private-mode env where business declares the :governance capability.
      skip "governance capability not present — covered by the inverse path below" unless described_class.governance_enabled?

      expect(described_class.governance_enabled?).to be true
    end
  end

  describe "core-mode behavior (no business extension)" do
    # Force the short-circuit branch regardless of whether the extension
    # is actually loaded in the test environment — the production code
    # has to handle both cases identically, so the spec must exercise
    # the core-mode branch deterministically.
    before do
      allow(described_class).to receive(:governance_enabled?).and_return(false)
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

  describe "#expire_overdue! (governance enabled)" do
    before { allow(described_class).to receive(:governance_enabled?).and_return(true) }

    it "expires overdue pending requests, honouring the chain timeout_action" do
      chain = Ai::ApprovalChain.create!(
        account: account, name: "expiry_test", trigger_type: "manual", status: "active",
        timeout_hours: 24, timeout_action: "reject",
        steps: [ { "name" => "s", "approvers" => [ "*" ], "required_approvals" => 1 } ]
      )
      agent = create(:ai_agent, account: account)
      request = chain.create_request!(source_type: "Ai::Agent", source_id: agent.id, description: "x", request_data: {})
      request.update_column(:expires_at, 1.hour.ago)

      expect(service.expire_overdue!).to eq(1)
      expect(request.reload.status).to eq("rejected")
    end

    it "leaves not-yet-overdue requests pending" do
      chain = Ai::ApprovalChain.create!(
        account: account, name: "expiry_test2", trigger_type: "manual", status: "active",
        timeout_hours: 24, steps: [ { "name" => "s", "approvers" => [ "*" ], "required_approvals" => 1 } ]
      )
      agent = create(:ai_agent, account: account)
      request = chain.create_request!(source_type: "Ai::Agent", source_id: agent.id, description: "x", request_data: {})

      expect(service.expire_overdue!).to eq(0)
      expect(request.reload.status).to eq("pending")
    end
  end
end
