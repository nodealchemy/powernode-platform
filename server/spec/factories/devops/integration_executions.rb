# frozen_string_literal: true

FactoryBot.define do
  factory :devops_integration_execution, class: 'Devops::IntegrationExecution' do
    association :instance, factory: :devops_integration_instance
    association :account
    association :triggered_by_user, factory: :user

    execution_id { "exec_#{SecureRandom.hex(12)}" }
    status { "pending" }
    trigger_type { "manual" }
    trigger_source { "api" }
    trigger_metadata { {} }
    input_data { {} }
    output_data { {} }
    error_details { {} }
    resource_usage { {} }
    attempt_number { 1 }
    max_attempts { 3 }

    trait :running do
      status { "running" }
      started_at { Time.current }
    end

    trait :completed do
      status { "completed" }
      started_at { 5.minutes.ago }
      completed_at { 1.minute.ago }
      duration_ms { 240000 }
      output_data do
        {
          "status" => "success",
          "result" => "Operation completed successfully"
        }
      end
    end

    trait :failed do
      status { "failed" }
      started_at { 5.minutes.ago }
      completed_at { 1.minute.ago }
      duration_ms { 120000 }
      error_details do
        {
          "message" => "Execution failed",
          "code" => "EXECUTION_ERROR",
          "details" => "Connection timeout"
        }
      end
    end

    trait :cancelled do
      status { "cancelled" }
      started_at { 5.minutes.ago }
      completed_at { 2.minutes.ago }
      duration_ms { 180000 }
    end

    trait :webhook_triggered do
      trigger_type { "webhook" }
      trigger_source { "github" }
      trigger_metadata do
        {
          "event" => "push",
          "repository" => "test/repo"
        }
      end
    end

    trait :scheduled do
      trigger_type { "scheduled" }
      trigger_source { "cron" }
      trigger_metadata do
        {
          "schedule" => "0 */6 * * *"
        }
      end
    end

    trait :workflow_triggered do
      trigger_type { "workflow" }
      trigger_source { "workflow_engine" }
    end

    trait :retriable do
      status { "failed" }
      attempt_number { 1 }
      max_attempts { 3 }
      next_retry_at { 1.minute.from_now }
    end

    trait :max_retries_reached do
      status { "failed" }
      attempt_number { 3 }
      max_attempts { 3 }
    end

    trait :with_parent do
      association :parent_execution, factory: :devops_integration_execution
      attempt_number { 2 }
    end

    trait :with_input do
      input_data do
        {
          "method" => "POST",
          "path" => "/api/test",
          "body" => { "key" => "value" }
        }
      end
    end

    trait :fast_execution do
      status { "completed" }
      started_at { 30.seconds.ago }
      completed_at { 10.seconds.ago }
      duration_ms { 20000 }
    end

    trait :slow_execution do
      status { "completed" }
      started_at { 10.minutes.ago }
      completed_at { 1.minute.ago }
      duration_ms { 540000 }
    end
  end
end
