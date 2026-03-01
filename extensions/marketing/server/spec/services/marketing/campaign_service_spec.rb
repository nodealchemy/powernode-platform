# frozen_string_literal: true

require "rails_helper"

RSpec.describe Marketing::CampaignService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:service) { described_class.new(account) }

  describe "#list" do
    let!(:active_campaign) { create(:marketing_campaign, :active, account: account) }
    let!(:draft_campaign) { create(:marketing_campaign, account: account) }
    let!(:other_account_campaign) { create(:marketing_campaign) }

    it "returns campaigns for the account" do
      result = service.list
      expect(result).to include(active_campaign, draft_campaign)
      expect(result).not_to include(other_account_campaign)
    end

    it "filters by status" do
      result = service.list(status: "active")
      expect(result).to include(active_campaign)
      expect(result).not_to include(draft_campaign)
    end

    it "filters by campaign type" do
      social = create(:marketing_campaign, :social, account: account)
      result = service.list(campaign_type: "social")
      expect(result).to include(social)
      expect(result).not_to include(draft_campaign)
    end

    it "searches by name" do
      named = create(:marketing_campaign, name: "Special Promo", account: account)
      result = service.list(search: "Special")
      expect(result).to include(named)
    end
  end

  describe "#create" do
    let(:params) do
      {
        name: "New Campaign",
        campaign_type: "email",
        budget_cents: 50_000
      }
    end

    it "creates a campaign with draft status" do
      campaign = service.create(params, creator: user)
      expect(campaign).to be_persisted
      expect(campaign.status).to eq("draft")
      expect(campaign.creator).to eq(user)
      expect(campaign.account).to eq(account)
    end

    it "raises on invalid params" do
      expect {
        service.create({ name: "" }, creator: user)
      }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe "#update" do
    let(:campaign) { create(:marketing_campaign, account: account) }

    it "updates the campaign" do
      service.update(campaign, { name: "Updated Name" })
      expect(campaign.reload.name).to eq("Updated Name")
    end
  end

  describe "#destroy" do
    let!(:campaign) { create(:marketing_campaign, account: account) }

    it "destroys the campaign" do
      expect { service.destroy(campaign) }.to change(Marketing::Campaign, :count).by(-1)
    end
  end

  describe "status workflow" do
    let(:campaign) { create(:marketing_campaign, account: account) }

    describe "#schedule" do
      it "schedules a draft campaign" do
        result = service.schedule(campaign, 1.week.from_now)
        expect(result.status).to eq("scheduled")
      end

      it "raises error for non-draft campaign" do
        campaign.activate!
        expect { service.schedule(campaign, 1.week.from_now) }.to raise_error(described_class::CampaignError)
      end
    end

    describe "#activate" do
      it "activates a draft campaign" do
        result = service.activate(campaign)
        expect(result.status).to eq("active")
      end
    end

    describe "#pause" do
      it "pauses an active campaign" do
        campaign.activate!
        result = service.pause(campaign)
        expect(result.status).to eq("paused")
      end

      it "raises error for non-active campaign" do
        expect { service.pause(campaign) }.to raise_error(described_class::CampaignError)
      end
    end

    describe "#resume" do
      it "resumes a paused campaign" do
        campaign.activate!
        campaign.pause!
        result = service.resume(campaign)
        expect(result.status).to eq("active")
      end
    end

    describe "#complete" do
      it "completes an active campaign" do
        campaign.activate!
        result = service.complete(campaign)
        expect(result.status).to eq("completed")
      end
    end

    describe "#archive" do
      it "archives a completed campaign" do
        campaign.activate!
        campaign.complete!
        result = service.archive(campaign)
        expect(result.status).to eq("archived")
      end
    end
  end

  describe "#execute" do
    let(:campaign) { create(:marketing_campaign, account: account) }

    it "activates and dispatches the campaign" do
      result = service.execute(campaign)
      expect(result.status).to eq("active")
    end

    it "raises error for invalid status" do
      campaign.activate!
      campaign.complete!
      expect { service.execute(campaign) }.to raise_error(described_class::CampaignError)
    end
  end

  describe "#clone" do
    let(:campaign) { create(:marketing_campaign, :with_content, account: account) }

    it "creates a copy of the campaign" do
      cloned = service.clone(campaign)
      expect(cloned).to be_persisted
      expect(cloned.name).to include("(Copy)")
      expect(cloned.status).to eq("draft")
      expect(cloned.id).not_to eq(campaign.id)
    end

    it "clones content" do
      cloned = service.clone(campaign)
      expect(cloned.campaign_contents.count).to eq(campaign.campaign_contents.count)
    end

    it "allows custom name" do
      cloned = service.clone(campaign, new_name: "Custom Clone")
      expect(cloned.name).to eq("Custom Clone")
    end
  end

  describe "#statistics" do
    before do
      create(:marketing_campaign, account: account, status: "draft")
      create(:marketing_campaign, :active, account: account, budget_cents: 10_000, spent_cents: 3_000)
      create(:marketing_campaign, :completed, account: account)
    end

    it "returns aggregate statistics" do
      stats = service.statistics
      expect(stats[:total]).to eq(3)
      expect(stats[:by_status][:draft]).to eq(1)
      expect(stats[:by_status][:active]).to eq(1)
      expect(stats[:by_status][:completed]).to eq(1)
      expect(stats[:total_budget_cents]).to be > 0
    end
  end
end
