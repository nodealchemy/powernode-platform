# frozen_string_literal: true

FactoryBot.define do
  factory :marketing_campaign_email_list, class: "Marketing::CampaignEmailList" do
    association :campaign, factory: :marketing_campaign
    association :email_list, factory: :marketing_email_list
  end
end
