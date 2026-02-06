# frozen_string_literal: true

FactoryBot.define do
  factory :ai_remediation_log, class: "Ai::RemediationLog" do
    account
    trigger_source { "health_monitor" }
    trigger_event { "provider_latency_spike" }
    action_type { "provider_failover" }
    action_config { {} }
    before_state { {} }
    after_state { {} }
    result { "success" }
    result_message { nil }
    executed_at { Time.current }

    trait :successful do
      result { "success" }
      result_message { "Remediation action completed successfully" }
    end

    trait :failed do
      result { "failure" }
      result_message { "Remediation action failed: target service unavailable" }
    end

    trait :skipped do
      result { "skipped" }
      result_message { "Action skipped: already remediated by prior action" }
    end

    trait :rate_limited do
      result { "rate_limited" }
      result_message { "Action rate limited: too many remediations in the last hour" }
    end

    trait :provider_failover do
      action_type { "provider_failover" }
      trigger_source { "health_monitor" }
      trigger_event { "provider_error_rate_high" }
      action_config do
        {
          "from_provider" => "openai",
          "to_provider" => "anthropic",
          "failover_reason" => "error_rate_exceeded_threshold"
        }
      end
      before_state do
        {
          "active_provider" => "openai",
          "error_rate" => 0.15,
          "avg_latency_ms" => 4500
        }
      end
      after_state do
        {
          "active_provider" => "anthropic",
          "error_rate" => 0.01,
          "avg_latency_ms" => 800
        }
      end
    end

    trait :workflow_retry do
      action_type { "workflow_retry" }
      trigger_source { "workflow_monitor" }
      trigger_event { "workflow_execution_failed" }
      action_config do
        {
          "workflow_id" => SecureRandom.uuid,
          "max_retries" => 3,
          "retry_delay_ms" => 5000
        }
      end
      before_state do
        {
          "execution_status" => "failed",
          "retry_count" => 0,
          "error" => "Timeout"
        }
      end
      after_state do
        {
          "execution_status" => "completed",
          "retry_count" => 1
        }
      end
    end

    trait :alert_escalation do
      action_type { "alert_escalation" }
      trigger_source { "alert_manager" }
      trigger_event { "critical_alert_unresolved" }
      action_config do
        {
          "escalation_level" => 2,
          "notify_channels" => %w[slack email pagerduty],
          "alert_id" => SecureRandom.uuid
        }
      end
      before_state do
        {
          "alert_status" => "open",
          "escalation_level" => 1,
          "time_open_minutes" => 30
        }
      end
      after_state do
        {
          "alert_status" => "escalated",
          "escalation_level" => 2,
          "notifications_sent" => 3
        }
      end
    end

    trait :recent do
      executed_at { rand(1..60).minutes.ago }
    end

    trait :old do
      executed_at { rand(2..30).days.ago }
    end
  end
end
