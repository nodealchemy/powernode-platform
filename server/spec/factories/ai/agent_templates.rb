# frozen_string_literal: true

FactoryBot.define do
  factory :ai_agent_template, class: "Ai::AgentTemplate" do
    association :publisher, factory: :ai_publisher_account
    sequence(:name) { |n| "Agent Template #{n}" }
    sequence(:slug) { |n| "agent-template-#{n}" }
    description { Faker::Lorem.sentence }
    status { "draft" }
    pricing_type { "free" }
    visibility { "private" }
    version { "1.0.0" }
    category { "general" }
    agent_config { {} }
    default_settings { {} }
    features { [] }
    limitations { [] }
    tags { [] }
    required_tools { [] }
    required_credentials { [] }
    supported_providers { [] }
    sample_prompts { [] }
    screenshots { [] }
    installation_count { 0 }
    review_count { 0 }
    is_featured { false }
    is_verified { false }

    trait :published do
      status { "published" }
      published_at { Time.current }
      visibility { "public" }
    end

    trait :featured do
      is_featured { true }
      featured_at { Time.current }
    end

    trait :paid do
      pricing_type { "one_time" }
      price_usd { 9.99 }
    end
  end
end
