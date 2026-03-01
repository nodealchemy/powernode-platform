# frozen_string_literal: true

FactoryBot.define do
  factory :devops_integration_instance, class: 'Devops::IntegrationInstance' do
    association :account
    association :template, factory: :devops_integration_template
    association :created_by_user, factory: :user

    sequence(:name) { |n| "Test Instance #{n}" }
    sequence(:slug) { |n| "test-instance-#{n}" }
    status { "active" }
    health_status { "healthy" }
    configuration { {} }
    runtime_state { {} }
    health_metrics { {} }

    execution_count { 0 }
    success_count { 0 }
    failure_count { 0 }
    consecutive_failures { 0 }
    average_duration_ms { 0 }

    trait :with_credential do
      association :credential, factory: :devops_integration_credential
    end

    trait :pending do
      status { "pending" }
      health_status { "unknown" }
    end

    trait :paused do
      status { "paused" }
    end

    trait :errored do
      status { "error" }
      health_status { "unhealthy" }
      consecutive_failures { 5 }
      last_error { "Integration failed to execute" }
    end

    trait :disabled do
      status { "disabled" }
    end

    trait :degraded do
      health_status { "degraded" }
      consecutive_failures { 2 }
    end

    trait :unhealthy do
      health_status { "unhealthy" }
      consecutive_failures { 4 }
    end

    trait :with_executions do
      execution_count { 10 }
      success_count { 8 }
      failure_count { 2 }
      average_duration_ms { 1500 }
      last_executed_at { 1.hour.ago }
      last_success_at { 1.hour.ago }
    end

    trait :frequently_used do
      execution_count { 100 }
      success_count { 95 }
      failure_count { 5 }
      average_duration_ms { 800 }
      last_executed_at { 10.minutes.ago }
      last_success_at { 10.minutes.ago }
    end

    trait :with_configuration do
      configuration do
        {
          "api_endpoint" => "https://api.example.com",
          "timeout" => 60
        }
      end
    end
  end
end
