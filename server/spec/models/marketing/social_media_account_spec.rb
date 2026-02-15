# frozen_string_literal: true

require "rails_helper"

RSpec.describe Marketing::SocialMediaAccount, type: :model do
  subject { build(:marketing_social_media_account) }

  describe "associations" do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:connected_by).class_name("User").optional }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:platform) }
    it { is_expected.to validate_inclusion_of(:platform).in_array(Marketing::SocialMediaAccount::PLATFORMS) }
    it { is_expected.to validate_presence_of(:platform_account_id) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_inclusion_of(:status).in_array(Marketing::SocialMediaAccount::STATUSES) }
  end

  describe "scopes" do
    let(:account) { create(:account) }

    it "filters connected accounts" do
      connected = create(:marketing_social_media_account, account: account, status: "connected")
      disconnected = create(:marketing_social_media_account, :disconnected, account: account)

      expect(described_class.connected).to include(connected)
      expect(described_class.connected).not_to include(disconnected)
    end

    it "filters by platform" do
      twitter = create(:marketing_social_media_account, :twitter, account: account)
      linkedin = create(:marketing_social_media_account, :linkedin, account: account)

      expect(described_class.by_platform("twitter")).to include(twitter)
      expect(described_class.by_platform("twitter")).not_to include(linkedin)
    end

    it "finds expiring soon accounts" do
      expiring = create(:marketing_social_media_account, :expiring_soon, account: account)
      normal = create(:marketing_social_media_account, account: account, token_expires_at: 30.days.from_now)

      expect(described_class.expiring_soon).to include(expiring)
      expect(described_class.expiring_soon).not_to include(normal)
    end
  end

  describe "#connected?" do
    it "returns true when status is connected" do
      account = build(:marketing_social_media_account, status: "connected")
      expect(account).to be_connected
    end

    it "returns false when status is not connected" do
      account = build(:marketing_social_media_account, status: "disconnected")
      expect(account).not_to be_connected
    end
  end

  describe "#token_expired?" do
    it "returns true when token is past expiry" do
      account = build(:marketing_social_media_account, token_expires_at: 1.day.ago)
      expect(account).to be_token_expired
    end

    it "returns false when token is still valid" do
      account = build(:marketing_social_media_account, token_expires_at: 1.day.from_now)
      expect(account).not_to be_token_expired
    end
  end

  describe "#account_summary" do
    let(:social_account) { create(:marketing_social_media_account) }

    it "returns summary with expected keys" do
      summary = social_account.account_summary
      expect(summary).to include(:id, :platform, :platform_username, :status, :post_count)
    end
  end

  describe "#account_details" do
    let(:social_account) { create(:marketing_social_media_account) }

    it "includes extended details" do
      details = social_account.account_details
      expect(details).to include(:platform_account_id, :scopes, :rate_limit_remaining)
    end
  end
end
