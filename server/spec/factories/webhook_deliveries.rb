# frozen_string_literal: true

FactoryBot.define do
  factory :webhook_delivery do
    association :webhook_endpoint
    association :webhook_event
    status { "pending" }
    attempt_number { 1 }
    request_headers { {} }
    response_headers { {} }

    trait :pending do
      status { "pending" }
    end

    trait :successful do
      status { "success" }
      attempted_at { Time.current }
      response_status { 200 }
    end

    trait :failed do
      status { "failed" }
      attempt_number { 2 }
      attempted_at { Time.current }
      error_message { "Connection timeout" }
      next_retry_at { 5.minutes.from_now }
    end
  end
end
