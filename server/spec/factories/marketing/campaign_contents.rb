# frozen_string_literal: true

FactoryBot.define do
  factory :marketing_campaign_content, class: "Marketing::CampaignContent" do
    association :campaign, factory: :marketing_campaign
    channel { "email" }
    sequence(:variant_name) { |n| "Variant #{n}" }
    subject { "Check out our latest offer" }
    preview_text { "Don't miss this opportunity" }
    body { "<h1>Hello!</h1><p>Check out our amazing offer.</p>" }
    cta_text { "Learn More" }
    cta_url { "https://example.com/offer" }
    status { "draft" }
    ai_generated { false }
    media_urls { [] }
    platform_specific { {} }

    trait :approved do
      status { "approved" }
      approved_at { Time.current }
      association :approved_by, factory: :user
    end

    trait :rejected do
      status { "rejected" }
    end

    trait :ai_generated do
      ai_generated { true }
    end

    trait :twitter do
      channel { "twitter" }
      body { "Check out our latest product! #innovation #tech" }
      platform_specific { { max_length: 280, hashtags: %w[innovation tech] } }
    end

    trait :linkedin do
      channel { "linkedin" }
      body { "We're excited to announce our latest product launch. Read more about how it can transform your workflow." }
      platform_specific { { max_length: 3000, article_mode: false } }
    end

    trait :facebook do
      channel { "facebook" }
      platform_specific { { link_preview: true } }
    end

    trait :instagram do
      channel { "instagram" }
      body { "Amazing new product! #launch #innovation #tech" }
      platform_specific { { max_hashtags: 30, story_mode: false } }
    end
  end
end
