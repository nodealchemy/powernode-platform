# frozen_string_literal: true

FactoryBot.define do
  factory :ai_mock_response, class: "Ai::MockResponse" do
    account
    association :sandbox, factory: :ai_sandbox
    sequence(:name) { |n| "Mock Response #{n}" }
    provider_type { "openai" }
    match_type { "exact" }
    is_active { true }
    priority { 0 }
    latency_ms { 100 }
    error_rate { 0.0 }
    hit_count { 0 }
    response_data { { "content" => "Mocked response" } }
    match_criteria { {} }

    trait :inactive do
      is_active { false }
    end

    trait :regex do
      match_type { "regex" }
    end

    trait :always_match do
      match_type { "always" }
    end

    trait :with_errors do
      error_rate { 0.5 }
      error_type { "timeout" }
      error_message { "Simulated timeout" }
    end
  end
end
