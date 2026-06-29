# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::AgentProposal, type: :model do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:agent) { create(:ai_agent, account: account) }

  def pending_proposal
    account.ai_agent_proposals.create!(
      ai_agent_id: agent.id,
      target_user: user,
      title: "Improve onboarding",
      proposal_type: "process_improvement",
      priority: "medium",
      status: "pending_review"
    )
  end

  describe "associations" do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:agent).class_name("Ai::Agent") }
  end

  # Approval-unification cascade target. Invoked by
  # Ai::ApprovalRequest#notify_source_of_decision when a gateway-routed proposal
  # gate resolves. Exercised here through the real Ai::Approvals::Gateway so the
  # full cascade (resolve! -> record_decision! -> notify_source_of_decision ->
  # on_approval_decision) is covered.
  describe "#on_approval_decision (gateway cascade)" do
    before do
      allow(Ai::Approvals::Gateway).to receive(:governance_enabled?).and_return(true)
      allow(Ai::Autonomy::ApprovalWorkflowService).to receive(:governance_enabled?).and_return(true)
    end

    let(:gateway) { Ai::Approvals::Gateway.new(account: account) }
    let(:proposal) { pending_proposal }
    let(:request) { gateway.request!(approvable: proposal, kind: "agent_proposal").approval_request }

    it "flips pending_review -> approved when the request is approved" do
      request # open the gate
      gateway.resolve!(request: request, decision: "approved", by: user)

      expect(proposal.reload.status).to eq("approved")
      expect(proposal.reload.reviewed_by).to eq(user)
    end

    it "flips pending_review -> rejected when the request is rejected" do
      request
      gateway.resolve!(request: request, decision: "rejected", by: user)

      expect(proposal.reload.status).to eq("rejected")
      expect(proposal.reload.reviewed_by).to eq(user)
    end

    it "no-ops when the proposal is no longer pending" do
      proposal.update!(status: "withdrawn")
      req = gateway.request!(approvable: proposal, kind: "agent_proposal").approval_request

      expect { gateway.resolve!(request: req, decision: "approved", by: user) }
        .not_to change { proposal.reload.status }
      expect(proposal.reload.status).to eq("withdrawn")
    end
  end

  describe "#on_approval_decision (direct)" do
    it "no-ops when called on a non-pending proposal" do
      proposal = pending_proposal
      proposal.update!(status: "implemented")
      request = instance_double(Ai::ApprovalRequest, status: "approved")

      expect { proposal.on_approval_decision(request) }.not_to change { proposal.reload.status }
    end
  end
end
