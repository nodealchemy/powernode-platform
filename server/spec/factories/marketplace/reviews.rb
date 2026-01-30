# frozen_string_literal: true

FactoryBot.define do
  factory :marketplace_review, class: "MarketplaceReview" do
    association :account
    association :user
    reviewable { association(:ai_workflow_template) }
    rating { rand(1..5) }
    title { Faker::Lorem.sentence(word_count: 5) }
    content { Faker::Lorem.paragraph }
    helpful_count { 0 }
    moderation_status { "approved" }
    verified_purchase { false }

    trait :approved do
      moderation_status { "approved" }
    end

    trait :pending do
      moderation_status { "pending" }
    end

    trait :flagged do
      moderation_status { "flagged" }
    end

    trait :five_star do
      rating { 5 }
    end

    trait :one_star do
      rating { 1 }
    end

    trait :verified do
      verified_purchase { true }
    end

    trait :helpful do
      helpful_count { rand(1..50) }
    end
  end
end
