# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Campaign land proposal + operator approval (Phase 2)" do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:campaign) { create(:ai_campaign, account: account, created_by: user) }

  def land(status: "pending_approval")
    Ai::CampaignLand.create!(
      campaign: campaign, account: account, status: status,
      source_branch: "campaign/#{campaign.id}", target_branch: "develop"
    )
  end

  describe "Ai::CampaignLand#operator_approve! / #operator_reject! (core mode)" do
    it "enqueues a pending land on approve" do
      l = land
      l.operator_approve!(user: user)
      expect(l.reload.status).to eq("queued")
    end

    it "rejects a pending land on reject" do
      l = land
      l.operator_reject!(user: user, reason: "not now")
      expect(l.reload).to have_attributes(status: "rejected", error_message: "not now")
    end

    it "is a no-op once past pending_approval" do
      l = land(status: "queued")
      l.operator_reject!(user: user)
      expect(l.reload.status).to eq("queued")
    end
  end

  # IMP-7836ec7a974d. The operator-decision methods document themselves as
  # "routes through the governance ApprovalRequest when present (which cascades
  # back here via on_approval_decision)". These pin that the REQUEST ROW is
  # resolved, not merely that the land moves: asserting only the land's status
  # passes while the request dangles as an outstanding approvals-surface item
  # that no longer governs anything.
  describe "Ai::CampaignLand#operator_approve! / #operator_reject! (governed mode)" do
    let(:chain) { create(:ai_approval_chain, account: account) }

    def governed_land(status: "pending_approval")
      l = land(status: status)
      req = chain.create_request!(
        source_type: "Ai::CampaignLand", source_id: l.id,
        description: "Land #{l.source_branch} → #{l.target_branch}", requested_by: user
      )
      [ l, req ]
    end

    def pending_requests_for(l)
      Ai::ApprovalRequest.for_source("Ai::CampaignLand", l.id).pending
    end

    it "leaves no pending ApprovalRequest after an operator approves" do
      l, req = governed_land
      l.operator_approve!(user: user)

      expect(pending_requests_for(l)).to be_empty
      expect(req.reload.status).to eq("approved")
    end

    it "leaves no pending ApprovalRequest after an operator rejects" do
      l, req = governed_land
      l.operator_reject!(user: user, reason: "not now")

      expect(pending_requests_for(l)).to be_empty
      expect(req.reload.status).to eq("rejected")
    end

    # CONTROL (green on HEAD by the direct-enqueue branch): pins that resolving
    # the request still moves the land, i.e. the cascade actually arrives.
    it "queues the land through the approval cascade" do
      l, = governed_land
      l.operator_approve!(user: user)

      expect(l.reload.status).to eq("queued")
    end

    # CONTROL + parity guard: routing through the request must not cost the
    # operator's own words. The cascade stamps a generic "approval rejected".
    it "keeps the operator's reason on the land when rejecting" do
      l, = governed_land
      l.operator_reject!(user: user, reason: "not now")

      expect(l.reload).to have_attributes(status: "rejected", error_message: "not now")
    end

    # The governed branch means "there is an OPEN gate to resolve". A request
    # that has already been decided must not be re-flipped, and must not strand
    # the land: re-calling approve! on an approved row is a no-op status write,
    # so no after_update cascade fires and nothing would ever enqueue it.
    it "acts directly when the latest request is already resolved" do
      l, req = governed_land
      req.update_columns(status: "approved", completed_at: Time.current)

      l.operator_approve!(user: user)

      expect(l.reload.status).to eq("queued")
      expect(req.reload.status).to eq("approved")
    end
  end

  describe "Ai::Land::ProposalService.deliver" do
    it "notifies the campaign creator with actionable metadata" do
      l = land
      expect { Ai::Land::ProposalService.deliver(l) }
        .to change { Notification.where(user: user, notification_type: "campaign_land_approval").count }.by(1)

      n = Notification.where(user: user, notification_type: "campaign_land_approval").last
      expect(n.metadata["campaign_land_id"]).to eq(l.id)
      expect(n.metadata["action_type"]).to eq("approve_campaign_land")
    end
  end

  describe "Ai::Land::ApprovalBinding delivers a proposal for a non-autonomous campaign" do
    it "creates a pending land and a notification" do
      allow_any_instance_of(Ai::Land::ApprovalBinding).to receive(:governance_available?).and_return(false)
      expect { Ai::Land::ApprovalBinding.request_land_approval(campaign: campaign) }
        .to change { Notification.where(notification_type: "campaign_land_approval").count }.by_at_least(1)
    end
  end

  describe "ConciergeService approve/reject handlers" do
    let(:conversation) { create(:ai_conversation, account: account) }
    let(:service) { Ai::ConciergeService.new(conversation: conversation, user: user) }

    it "approve_campaign_land queues the land" do
      l = land
      service.send(:approve_campaign_land, "campaign_land_id" => l.id)
      expect(l.reload.status).to eq("queued")
    end

    it "reject_campaign_land rejects the land" do
      l = land
      service.send(:reject_campaign_land, "campaign_land_id" => l.id, "reason" => "no")
      expect(l.reload.status).to eq("rejected")
    end

    it "handles a missing land gracefully" do
      expect { service.send(:approve_campaign_land, "campaign_land_id" => "019f0000-0000-7000-8000-0000000000ff") }
        .not_to raise_error
    end
  end
end
