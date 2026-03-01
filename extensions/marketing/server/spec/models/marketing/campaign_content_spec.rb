# frozen_string_literal: true

require "rails_helper"

RSpec.describe Marketing::CampaignContent, type: :model do
  subject { build(:marketing_campaign_content) }

  describe "associations" do
    it { is_expected.to belong_to(:campaign).class_name("Marketing::Campaign") }
    it { is_expected.to belong_to(:approved_by).class_name("User").optional }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:channel) }
    it { is_expected.to validate_inclusion_of(:channel).in_array(Marketing::CampaignContent::CHANNELS) }
    it { is_expected.to validate_presence_of(:variant_name) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_inclusion_of(:status).in_array(Marketing::CampaignContent::STATUSES) }
    it { is_expected.to validate_presence_of(:body) }
  end

  describe "scopes" do
    let(:campaign) { create(:marketing_campaign) }
    let!(:draft_content) { create(:marketing_campaign_content, campaign: campaign, status: "draft") }
    let!(:approved_content) { create(:marketing_campaign_content, :approved, campaign: campaign) }
    let!(:ai_content) { create(:marketing_campaign_content, :ai_generated, campaign: campaign) }

    it "filters by status" do
      expect(described_class.draft).to include(draft_content)
      expect(described_class.approved).to include(approved_content)
    end

    it "filters by AI generated" do
      expect(described_class.ai_generated).to include(ai_content)
      expect(described_class.ai_generated).not_to include(draft_content)
    end

    it "filters by channel" do
      twitter_content = create(:marketing_campaign_content, :twitter, campaign: campaign)
      expect(described_class.by_channel("twitter")).to include(twitter_content)
    end
  end

  describe "#approve!" do
    let(:content) { create(:marketing_campaign_content) }
    let(:approver) { create(:user) }

    it "sets status to approved with approver" do
      content.approve!(approver)
      expect(content.status).to eq("approved")
      expect(content.approved_by).to eq(approver)
      expect(content.approved_at).to be_present
    end
  end

  describe "#reject!" do
    let(:content) { create(:marketing_campaign_content) }

    it "sets status to rejected" do
      content.reject!
      expect(content.status).to eq("rejected")
    end
  end

  describe "#content_summary" do
    let(:content) { create(:marketing_campaign_content) }

    it "returns summary with expected keys" do
      summary = content.content_summary
      expect(summary).to include(:id, :channel, :variant_name, :status, :ai_generated)
    end
  end

  describe "#content_details" do
    let(:content) { create(:marketing_campaign_content) }

    it "includes body and extended attributes" do
      details = content.content_details
      expect(details).to include(:body, :media_urls, :cta_text, :cta_url, :platform_specific)
    end
  end
end
