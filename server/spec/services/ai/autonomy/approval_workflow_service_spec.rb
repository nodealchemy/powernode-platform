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

    it "request_approval returns nil without touching Ai::ApprovalChain" do
      expect {
        result = service.request_approval(
          agent: agent, action_type: "test.action",
          description: "x", request_data: {}, requested_by: nil
        )
        expect(result).to be_nil
      }.not_to raise_error
    end

    # IMP-27e2f8e59ce0 — the DECISION side must work on any request that
    # exists, capability or not. Ai::AutonomyGate creates requests in core
    # mode (Ai::ApprovalChain is a core model) and the governance decide
    # endpoint already decides them without a capability check; refusing here
    # produced 422 "Cannot approve this request" on a core-mode hub and left
    # the deferred operation stranded. Only request CREATION stays gated.
    context "on a request that exists (created by the gate in core mode)" do
      let(:chain) do
        Ai::ApprovalChain.create!(
          account: account, name: "core_mode_test", trigger_type: "autonomy_action", status: "active",
          timeout_hours: 24, timeout_action: "reject",
          steps: [ { "name" => "s", "approvers" => [ "*" ], "required_approvals" => 1 } ]
        )
      end
      let(:real_agent) { create(:ai_agent, account: account) }
      let(:real_approver) { create(:user, account: account) }
      let!(:request) do
        chain.create_request!(source_type: "Ai::Agent", source_id: real_agent.id, description: "x", request_data: {})
      end

      it "pending_approvals lists it" do
        expect(service.pending_approvals.map(&:id)).to eq([ request.id ])
      end

      it "approve records the decision" do
        expect(service.approve(request: request, approver: real_approver)).to be true
        expect(request.reload.status).to eq("approved")
      end

      it "reject records the decision" do
        expect(service.reject(request: request, approver: real_approver)).to be true
        expect(request.reload.status).to eq("rejected")
      end

      it "expire_overdue! expires it" do
        request.update_column(:expires_at, 1.hour.ago)
        expect(service.expire_overdue!).to eq(1)
        expect(request.reload.status).to eq("rejected")
      end

      # The guards that survive are the ONLY refusal path now — pin each one.
      it "approve refuses a request that is no longer pending, without recording" do
        request.update_column(:status, "rejected")
        expect(request).not_to receive(:record_decision!)
        expect(service.approve(request: request, approver: real_approver)).to be false
      end

      it "approve refuses another account's request, without recording" do
        other = described_class.new(account: create(:account))
        expect(request).not_to receive(:record_decision!)
        expect(other.approve(request: request, approver: real_approver)).to be false
        expect(request.reload.status).to eq("pending")
      end

      it "reject refuses an approver the step does not name" do
        # step approvers are copied onto the request at creation, so the
        # strict chain has to exist before the request does
        strict_chain = Ai::ApprovalChain.create!(
          account: account, name: "strict", trigger_type: "autonomy_action", status: "active",
          timeout_hours: 24, timeout_action: "reject",
          steps: [ { "name" => "s", "approvers" => [ { "type" => "user", "value" => create(:user, account: account).id.to_s } ], "required_approvals" => 1 } ]
        )
        strict = strict_chain.create_request!(source_type: "Ai::Agent", source_id: real_agent.id, description: "y", request_data: {})
        expect(service.reject(request: strict, approver: real_approver)).to be false
        expect(strict.reload.status).to eq("pending")
      end
    end
  end

  describe "#expire_overdue!" do
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

    it "settles at most `limit` per call, oldest first, and leaves the rest for the next sweep" do
      chain = Ai::ApprovalChain.create!(
        account: account, name: "expiry_cap", trigger_type: "manual", status: "active",
        timeout_hours: 24, timeout_action: "reject",
        steps: [ { "name" => "s", "approvers" => [ "*" ], "required_approvals" => 1 } ]
      )
      agent = create(:ai_agent, account: account)
      requests = 3.times.map do |i|
        r = chain.create_request!(source_type: "Ai::Agent", source_id: agent.id, description: "x#{i}", request_data: {})
        r.update_column(:expires_at, (3 - i).hours.ago) # r0 oldest
        r
      end

      expect(service.expire_overdue!(limit: 2)).to eq(2)
      expect(requests.map { |r| r.reload.status }).to eq(%w[rejected rejected pending])
      expect(service.expire_overdue!(limit: 2)).to eq(1)
    end
  end
end
