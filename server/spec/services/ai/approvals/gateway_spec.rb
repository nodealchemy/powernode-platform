# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Approvals::Gateway do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:approvable) { create(:ai_agent, account: account) }

  subject(:gateway) { described_class.new(account: account) }

  describe "#request! in core mode (no governance)" do
    before { allow(Ai::Autonomy::ApprovalWorkflowService).to receive(:governance_enabled?).and_return(false) }

    it "auto-proceeds without creating an approval request" do
      result = nil
      expect { result = gateway.request!(approvable: approvable, kind: "merge_approval") }
        .not_to change(Ai::ApprovalRequest, :count)

      expect(result).to be_proceed
      expect(result.approval_request).to be_nil
    end
  end

  describe "#request! with governance enabled" do
    before { allow(Ai::Autonomy::ApprovalWorkflowService).to receive(:governance_enabled?).and_return(true) }

    it "creates a pending approval request targeting the approvable" do
      result = gateway.request!(approvable: approvable, kind: "merge_approval", description: "Land it")

      expect(result).to be_pending
      req = result.approval_request
      expect(req.source_type).to eq("Ai::Agent")
      expect(req.source_id).to eq(approvable.id)
      expect(req.request_data["action_type"]).to eq("merge_approval")
      expect(req).to be_pending
    end

    it "reuses one chain per kind" do
      gateway.request!(approvable: approvable, kind: "merge_approval")
      gateway.request!(approvable: approvable, kind: "merge_approval")

      expect(Ai::ApprovalChain.where(account: account, name: "gateway_merge_approval").count).to eq(1)
    end

    it "supports second-signature gates via required_approvals" do
      result = gateway.request!(approvable: approvable, kind: "release", required_approvals: 2)

      expect(result.approval_request.approval_chain.steps.first["required_approvals"]).to eq(2)
    end
  end

  describe "#resolve!" do
    before { allow(Ai::Autonomy::ApprovalWorkflowService).to receive(:governance_enabled?).and_return(true) }

    let(:request) { gateway.request!(approvable: approvable, kind: "merge_approval").approval_request }

    it "records an approval decision through the workflow service" do
      expect(gateway.resolve!(request: request, decision: "approved", by: user)).to be true
      expect(request.reload.status).to eq("approved")
    end

    it "records a rejection" do
      expect(gateway.resolve!(request: request, decision: "rejected", by: user)).to be true
      expect(request.reload.status).to eq("rejected")
    end

    it "raises on an invalid decision" do
      expect { gateway.resolve!(request: request, decision: "maybe", by: user) }.to raise_error(ArgumentError)
    end
  end
end
