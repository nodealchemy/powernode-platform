# frozen_string_literal: true

FactoryBot.define do
  factory :webhook_event do
    association :account
    provider { "stripe" }
    sequence(:event_type) { |n| "payment.completed" }
    sequence(:event_id) { |n| "evt_id_#{SecureRandom.hex(12)}" }
    sequence(:external_id) { |n| "evt_#{SecureRandom.hex(12)}" }
    payload { { "id" => "evt_123", "type" => "payment.completed", "data" => {} } }
    status { "pending" }
    retry_count { 0 }
    occurred_at { Time.current }

    trait :stripe do
      provider { "stripe" }
    end

    trait :paypal do
      provider { "paypal" }
    end

    trait :pending do
      status { "pending" }
    end

    trait :processing do
      status { "processing" }
    end

    trait :processed do
      status { "processed" }
      processed_at { Time.current }
    end

    trait :failed do
      status { "failed" }
      error_message { "Processing error occurred" }
      retry_count { 1 }
    end

    trait :skipped do
      status { "skipped" }
    end

    trait :max_retries do
      status { "failed" }
      retry_count { 10 }
    end
  end
end
