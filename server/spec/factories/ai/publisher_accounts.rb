# frozen_string_literal: true

FactoryBot.define do
  factory :ai_publisher_account, class: "Ai::PublisherAccount" do
    account
    association :primary_user, factory: :user
    sequence(:publisher_name) { |n| "Publisher #{n}" }
    sequence(:publisher_slug) { |n| "publisher-#{n}" }
    description { "A test publisher account for AI marketplace" }
    status { "active" }
    verification_status { "verified" }
    revenue_share_percentage { 70 }
    lifetime_earnings_usd { 0.0 }
    pending_payout_usd { 0.0 }
    total_templates { 0 }
    total_installations { 0 }
    average_rating { nil }
    branding { {} }
    payout_settings { {} }
    support_email { "support@publisher.example.com" }
    website_url { "https://publisher.example.com" }
    stripe_account_id { nil }
    stripe_account_status { "pending" }
    stripe_onboarding_completed { false }
    stripe_payout_enabled { false }
    verified_at { nil }
    last_payout_at { nil }

    trait :pending do
      status { "pending" }
      verification_status { "unverified" }
    end

    trait :suspended do
      status { "suspended" }
    end

    trait :terminated do
      status { "terminated" }
    end

    trait :unverified do
      verification_status { "unverified" }
      verified_at { nil }
    end

    trait :pending_verification do
      verification_status { "pending" }
      verified_at { nil }
    end

    trait :verified do
      verification_status { "verified" }
      verified_at { 1.week.ago }
    end

    trait :rejected do
      verification_status { "rejected" }
      verified_at { nil }
    end

    trait :with_earnings do
      lifetime_earnings_usd { 1500.00 }
      pending_payout_usd { 250.00 }
      last_payout_at { 1.month.ago }
    end

    trait :with_stripe do
      stripe_account_id { "acct_test_#{SecureRandom.hex(8)}" }
      stripe_account_status { "active" }
      stripe_onboarding_completed { true }
      stripe_payout_enabled { true }
    end

    trait :with_templates do
      total_templates { 10 }
      total_installations { 150 }
      average_rating { 4.5 }
    end

    trait :with_branding do
      branding do
        {
          "logo_url" => "https://cdn.example.com/logo.png",
          "banner_url" => "https://cdn.example.com/banner.png",
          "primary_color" => "#007bff",
          "tagline" => "Building the future of AI"
        }
      end
    end
  end
end
