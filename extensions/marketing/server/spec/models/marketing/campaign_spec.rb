# frozen_string_literal: true

require "rails_helper"

RSpec.describe Marketing::Campaign, type: :model do
  subject { build(:marketing_campaign) }

  describe "associations" do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:creator).class_name("User") }
    it { is_expected.to have_many(:campaign_contents).dependent(:destroy) }
    it { is_expected.to have_many(:campaign_metrics).dependent(:destroy) }
    it { is_expected.to have_many(:campaign_email_lists).dependent(:destroy) }
    it { is_expected.to have_many(:email_lists).through(:campaign_email_lists) }
    it { is_expected.to have_many(:calendar_entries).dependent(:nullify) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(255) }
    # slug is auto-generated via before_validation callback
    it { is_expected.to validate_presence_of(:campaign_type) }
    it { is_expected.to validate_inclusion_of(:campaign_type).in_array(Marketing::Campaign::CAMPAIGN_TYPES) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_inclusion_of(:status).in_array(Marketing::Campaign::STATUSES) }
    it { is_expected.to validate_numericality_of(:budget_cents).is_greater_than_or_equal_to(0).allow_nil }
    it { is_expected.to validate_numericality_of(:spent_cents).is_greater_than_or_equal_to(0).allow_nil }
  end

  describe "scopes" do
    let(:account) { create(:account) }
    let!(:draft) { create(:marketing_campaign, account: account, status: "draft") }
    let!(:active) { create(:marketing_campaign, :active, account: account) }
    let!(:completed) { create(:marketing_campaign, :completed, account: account) }

    it "filters by status" do
      expect(described_class.draft).to include(draft)
      expect(described_class.active).to include(active)
      expect(described_class.completed).to include(completed)
    end

    it "filters by type" do
      social = create(:marketing_campaign, :social, account: account)
      expect(described_class.by_type("social")).to include(social)
      expect(described_class.by_type("social")).not_to include(draft)
    end
  end

  describe "status transitions" do
    let(:campaign) { create(:marketing_campaign) }

    describe "#schedule!" do
      it "transitions from draft to scheduled" do
        campaign.schedule!(1.week.from_now)
        expect(campaign.status).to eq("scheduled")
        expect(campaign.scheduled_at).to be_present
      end

      it "raises error if not in draft status" do
        campaign.update!(status: "active", started_at: Time.current)
        expect { campaign.schedule!(1.week.from_now) }.to raise_error(RuntimeError)
      end
    end

    describe "#activate!" do
      it "transitions from draft to active" do
        campaign.activate!
        expect(campaign.status).to eq("active")
        expect(campaign.started_at).to be_present
      end
    end

    describe "#pause!" do
      it "transitions from active to paused" do
        campaign.activate!
        campaign.pause!
        expect(campaign.status).to eq("paused")
      end
    end

    describe "#resume!" do
      it "transitions from paused to active" do
        campaign.activate!
        campaign.pause!
        campaign.resume!
        expect(campaign.status).to eq("active")
      end
    end

    describe "#complete!" do
      it "transitions from active to completed" do
        campaign.activate!
        campaign.complete!
        expect(campaign.status).to eq("completed")
      end
    end

    describe "#archive!" do
      it "transitions from completed to archived" do
        campaign.activate!
        campaign.complete!
        campaign.archive!
        expect(campaign.status).to eq("archived")
      end
    end
  end

  describe "helpers" do
    let(:campaign) { build(:marketing_campaign, budget_cents: 10_000, spent_cents: 3_000) }

    it "calculates budget remaining" do
      expect(campaign.budget_remaining_cents).to eq(7_000)
    end

    it "detects over budget" do
      campaign.spent_cents = 15_000
      expect(campaign).to be_over_budget
    end

    it "detects multi_channel type" do
      campaign.campaign_type = "multi_channel"
      expect(campaign).to be_multi_channel
    end
  end

  describe "#campaign_summary" do
    let(:campaign) { create(:marketing_campaign) }

    it "returns summary hash with expected keys" do
      summary = campaign.campaign_summary
      expect(summary).to include(:id, :name, :slug, :campaign_type, :status, :channels, :created_at)
    end
  end

  describe "#campaign_details" do
    let(:campaign) { create(:marketing_campaign) }

    it "returns detailed hash with creator info" do
      details = campaign.campaign_details
      expect(details).to include(:target_audience, :settings, :creator, :content_count, :email_list_count)
      expect(details[:creator]).to include(:id, :name, :email)
    end
  end

  describe "slug generation" do
    it "auto-generates slug from name" do
      campaign = create(:marketing_campaign, name: "My Great Campaign")
      expect(campaign.slug).to eq("my-great-campaign")
    end

    it "handles duplicate slugs" do
      create(:marketing_campaign, name: "Test Campaign", slug: "test-campaign")
      campaign2 = create(:marketing_campaign, name: "Test Campaign")
      expect(campaign2.slug).to start_with("test-campaign")
    end
  end
end
