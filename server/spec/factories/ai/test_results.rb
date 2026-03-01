# frozen_string_literal: true

FactoryBot.define do
  factory :ai_test_result, class: "Ai::TestResult" do
    association :test_run, factory: :ai_test_run
    association :scenario, factory: :ai_test_scenario
    result_id { SecureRandom.uuid }
    status { "passed" }
    input_used { {} }
    actual_output { {} }
    assertion_results { [] }
    metrics { {} }
    error_details { {} }
    logs { [] }
    tokens_used { 0 }
    cost_usd { 0.0 }
    retry_attempt { 0 }

    trait :passed do
      status { "passed" }
      started_at { 5.minutes.ago }
      completed_at { Time.current }
      duration_ms { 5000 }
    end

    trait :failed do
      status { "failed" }
      started_at { 5.minutes.ago }
      completed_at { Time.current }
      duration_ms { 3000 }
      error_details { { "message" => "Assertion failed" } }
    end

    trait :skipped do
      status { "skipped" }
    end

    trait :error do
      status { "error" }
      error_details { { "message" => "Runtime error" } }
    end
  end
end
