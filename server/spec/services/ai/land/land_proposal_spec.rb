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
