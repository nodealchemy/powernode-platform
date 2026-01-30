# frozen_string_literal: true

FactoryBot.define do
  factory :gateway_connection_job do
    gateway { "stripe" }
    operation { "test_connection" }
    status { "pending" }
    payload { {} }
    response { nil }

    trait :stripe do
      gateway { "stripe" }
    end

    trait :paypal do
      gateway { "paypal" }
    end

    trait :pending do
      status { "pending" }
    end

    trait :processing do
      status { "processing" }
    end

    trait :completed do
      status { "completed" }
      completed_at { Time.current }
      response { { "success" => true } }
    end

    trait :failed do
      status { "failed" }
      completed_at { Time.current }
      response { { "success" => false, "error" => "Connection failed" } }
    end

    trait :with_config do
      payload { { "api_key" => "test_key", "environment" => "test" } }
    end
  end
end
