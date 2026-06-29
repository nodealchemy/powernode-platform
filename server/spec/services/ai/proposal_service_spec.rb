# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::ProposalService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:agent) { create(:ai_agent, account: account) }
  let(:service) { described_class.new(account: account) }
  let(:params) { { title: "Improve onboarding", proposal_type: "process_improvement", priority: "medium" } }

  before do
    # Outreach is an orthogonal side effect; stub it so the spec focuses on the
    # approval-gate wiring.
    allow_any_instance_of(Ai::AgentOutreachService).to receive(:notify_proposal).and_return(true)
  end

  describe "#create" do
    it "creates a pending proposal" do
      proposal = service.create(agent: agent, params: params, target_user: user)
      expect(proposal).to be_persisted
      expect(proposal.status).to eq("pending_review")
    end
  end

  # Approval-unification: flag-gated default-OFF gate opening on creation.
  describe "#create gateway routing" do
    context "governance present but flag off (default)" do
      before { allow(Ai::Approvals::Gateway).to receive(:governance_enabled?).and_return(true) }

      it "opens no ApprovalRequest" do
        expect { service.create(agent: agent, params: params, target_user: user) }
          .not_to change(Ai::ApprovalRequest, :count)
      end
    end

    context "governance absent (flag on)" do
      before do
        allow(Ai::Approvals::Gateway).to receive(:governance_enabled?).and_return(false)
        account.update!(settings: { "ai" => { "approvals_via_gateway" => true } })
      end

      it "opens no ApprovalRequest" do
        expect { service.create(agent: agent, params: params, target_user: user) }
          .not_to change(Ai::ApprovalRequest, :count)
      end
    end

    context "governance present and flag on" do
      before do
        allow(Ai::Approvals::Gateway).to receive(:governance_enabled?).and_return(true)
        account.update!(settings: { "ai" => { "approvals_via_gateway" => true } })
      end

      it "opens exactly one ApprovalRequest targeting the proposal" do
        proposal = nil
        expect {
          proposal = service.create(agent: agent, params: params, target_user: user)
        }.to change(Ai::ApprovalRequest, :count).by(1)

        req = Ai::ApprovalRequest.for_source("Ai::AgentProposal", proposal.id).order(:created_at).last
        expect(req).to be_present
        expect(req.status).to eq("pending")
        expect(req.request_data["action_type"]).to eq("agent_proposal")
      end
    end
  end
end
