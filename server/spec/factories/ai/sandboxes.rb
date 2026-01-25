# frozen_string_literal: true

FactoryBot.define do
  factory :ai_sandbox, class: "Ai::Sandbox" do
    account
    association :created_by, factory: :user
    sequence(:name) { |n| "Test Sandbox #{n}" }
    description { "A test sandbox environment for AI testing" }
    sandbox_type { "standard" }
    status { "active" }
    is_isolated { true }
    recording_enabled { false }
    configuration { {} }
    environment_variables { {} }
    mock_providers { {} }
    resource_limits { { "max_tokens" => 10000, "max_api_calls" => 100 } }
    total_executions { 0 }
    test_runs_count { 0 }
    expires_at { nil }
    last_used_at { nil }

    trait :inactive do
      status { "inactive" }
    end

    trait :paused do
      status { "paused" }
    end

    trait :expired do
      status { "expired" }
      expires_at { 1.day.ago }
    end

    trait :isolated do
      sandbox_type { "isolated" }
      is_isolated { true }
    end

    trait :production_mirror do
      sandbox_type { "production_mirror" }
      is_isolated { false }
    end

    trait :performance do
      sandbox_type { "performance" }
    end

    trait :security do
      sandbox_type { "security" }
    end

    trait :with_recording do
      recording_enabled { true }
    end

    trait :with_expiration do
      expires_at { 7.days.from_now }
    end

    trait :with_usage do
      total_executions { 50 }
      test_runs_count { 10 }
      last_used_at { 1.hour.ago }
    end

    trait :with_mock_providers do
      mock_providers do
        {
          "openai" => {
            "enabled" => true,
            "responses" => [
              { "pattern" => ".*", "response" => "Mocked response" }
            ]
          }
        }
      end
    end
  end
end
