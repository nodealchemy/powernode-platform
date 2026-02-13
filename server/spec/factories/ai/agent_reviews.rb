# frozen_string_literal: true

FactoryBot.define do
  factory :ai_agent_review, class: "Ai::AgentReview" do
    account
    association :agent_template, factory: :ai_agent_template
    association :user
    rating { 4 }
    title { Faker::Lorem.sentence(word_count: 5) }
    content { Faker::Lorem.paragraph }
    status { "published" }
    is_verified_purchase { false }
    helpful_count { 0 }
    report_count { 0 }
    pros { [] }
    cons { [] }
    metadata { {} }

    trait :verified do
      is_verified_purchase { true }
      verified_at { Time.current }
    end

    trait :hidden do
      status { "hidden" }
    end

    trait :flagged do
      status { "flagged" }
      report_count { 3 }
    end
  end
end
