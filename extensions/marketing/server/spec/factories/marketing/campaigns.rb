# frozen_string_literal: true

FactoryBot.define do
  factory :marketing_campaign, class: "Marketing::Campaign" do
    account
    creator { association :user, account: account }
    sequence(:name) { |n| "Campaign #{n}" }
    campaign_type { "email" }
    status { "draft" }
    budget_cents { 100_000 }
    spent_cents { 0 }
    target_audience { { age_range: "25-45", interests: ["technology"] } }
    settings { { send_time: "09:00", timezone: "UTC" } }
    channels { ["email"] }
    tags { ["promotion"] }

    trait :scheduled do
      status { "scheduled" }
      scheduled_at { 1.week.from_now }
    end

    trait :active do
      status { "active" }
      started_at { 1.day.ago }
    end

    trait :paused do
      status { "paused" }
      started_at { 3.days.ago }
      paused_at { 1.day.ago }
    end

    trait :completed do
      status { "completed" }
      started_at { 2.weeks.ago }
      completed_at { 1.day.ago }
    end

    trait :archived do
      status { "archived" }
    end

    trait :email do
      campaign_type { "email" }
      channels { ["email"] }
    end

    trait :social do
      campaign_type { "social" }
      channels { %w[twitter linkedin] }
    end

    trait :multi_channel do
      campaign_type { "multi_channel" }
      channels { %w[email twitter linkedin] }
    end

    trait :with_content do
      after(:create) do |campaign|
        create(:marketing_campaign_content, campaign: campaign)
      end
    end

    trait :with_metrics do
      after(:create) do |campaign|
        create(:marketing_campaign_metric, campaign: campaign)
      end
    end

    trait :with_email_lists do
      after(:create) do |campaign|
        email_list = create(:marketing_email_list, account: campaign.account)
        create(:marketing_campaign_email_list, campaign: campaign, email_list: email_list)
      end
    end
  end
end
