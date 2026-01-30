# frozen_string_literal: true

FactoryBot.define do
  factory :usage_event do
    association :account
    association :usage_meter
    sequence(:event_id) { |n| "evt_#{SecureRandom.hex(8)}_#{n}" }
    quantity { 1.0 }
    timestamp { Time.current }
    source { "api" }
    is_processed { false }
    properties { {} }
    metadata { {} }

    trait :processed do
      is_processed { true }
      processed_at { Time.current }
    end

    trait :from_webhook do
      source { "webhook" }
    end

    trait :from_system do
      source { "system" }
    end

    trait :high_quantity do
      quantity { 100.0 }
    end

    trait :with_user do
      association :user
    end
  end
end
