# frozen_string_literal: true

FactoryBot.define do
  factory :ai_execution_event, class: "Ai::ExecutionEvent" do
    account
    source_type { "Ai::Agent" }
    source_id { SecureRandom.uuid }
    event_type { "execution_started" }
    status { "success" }
    metadata { {} }
    cost_usd { nil }
    duration_ms { nil }
    error_class { nil }
    error_message { nil }

    trait :started do
      event_type { "execution_started" }
      status { "success" }
    end

    trait :completed do
      event_type { "execution_completed" }
      status { "success" }
      duration_ms { rand(500..5000) }
      cost_usd { rand(0.001..0.05).round(6) }
      metadata do
        {
          "tokens_used" => rand(100..2000),
          "model" => "gpt-4",
          "provider" => "openai"
        }
      end
    end

    trait :failed do
      event_type { "execution_failed" }
      status { "failure" }
      duration_ms { rand(100..3000) }
      error_class { "ProviderTimeoutError" }
      error_message { "Request to provider timed out after 30 seconds" }
      metadata do
        {
          "retry_count" => 2,
          "last_attempt_at" => 1.minute.ago.iso8601
        }
      end
    end

    trait :retried do
      event_type { "execution_retried" }
      status { "success" }
      metadata do
        {
          "retry_number" => 1,
          "original_error" => "ProviderTimeoutError",
          "delay_ms" => 2000
        }
      end
    end

    trait :cancelled do
      event_type { "execution_cancelled" }
      status { "cancelled" }
      metadata do
        {
          "cancelled_by" => SecureRandom.uuid,
          "reason" => "User requested cancellation"
        }
      end
    end

    trait :from_agent do
      source_type { "Ai::Agent" }
    end

    trait :from_workflow do
      source_type { "Ai::Workflow" }
    end

    trait :from_team_execution do
      source_type { "Ai::TeamExecution" }
    end

    trait :with_cost do
      cost_usd { rand(0.001..0.10).round(6) }
      duration_ms { rand(200..8000) }
    end

    trait :with_error do
      error_class { "Ai::ProviderError" }
      error_message { "API returned 500: Internal server error" }
    end

    trait :high_cost do
      cost_usd { rand(0.50..2.00).round(6) }
      duration_ms { rand(5000..30000) }
      metadata do
        {
          "tokens_used" => rand(5000..50000),
          "model" => "gpt-4-turbo",
          "provider" => "openai",
          "warning" => "high_cost_execution"
        }
      end
    end

    trait :token_limit_exceeded do
      event_type { "token_limit_exceeded" }
      status { "failure" }
      error_class { "TokenLimitExceededError" }
      error_message { "Input exceeded maximum token limit of 100000" }
      metadata do
        {
          "requested_tokens" => 120000,
          "max_tokens" => 100000
        }
      end
    end
  end
end
