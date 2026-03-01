# frozen_string_literal: true

FactoryBot.define do
  factory :ai_shared_knowledge, class: "Ai::SharedKnowledge" do
    account
    sequence(:title) { |n| "Knowledge Entry #{n}" }
    content { Faker::Lorem.paragraph(sentence_count: 3) }
    content_type { "text" }
    access_level { "team" }
    source_type { "agent" }
    source_id { SecureRandom.uuid }
    tags { [] }
    provenance { {} }
    quality_score { 0.8 }
    usage_count { 0 }

    trait :markdown do
      content_type { "markdown" }
    end

    trait :code do
      content_type { "code" }
    end

    trait :private_access do
      access_level { "private" }
    end

    trait :global_access do
      access_level { "global" }
    end

    trait :account_access do
      access_level { "account" }
    end

    trait :high_quality do
      quality_score { 0.9 }
    end

    trait :low_quality do
      quality_score { 0.3 }
    end

    trait :with_tags do
      tags { ["ruby", "rails", "testing"] }
    end

    trait :frequently_used do
      usage_count { 50 }
      last_used_at { 1.hour.ago }
    end
  end
end
