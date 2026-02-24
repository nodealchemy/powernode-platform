# frozen_string_literal: true

require "rails_helper"

RSpec.describe Marketing::CampaignEmailList, type: :model do
  subject { build(:marketing_campaign_email_list) }

  describe "associations" do
    it { is_expected.to belong_to(:campaign).class_name("Marketing::Campaign") }
    it { is_expected.to belong_to(:email_list).class_name("Marketing::EmailList") }
  end

  describe "validations" do
    it "prevents duplicate campaign-list associations" do
      campaign = create(:marketing_campaign)
      email_list = create(:marketing_email_list)
      create(:marketing_campaign_email_list, campaign: campaign, email_list: email_list)

      duplicate = build(:marketing_campaign_email_list, campaign: campaign, email_list: email_list)
      expect(duplicate).not_to be_valid
    end
  end
end
