# frozen_string_literal: true

FactoryBot.define do
  factory :analytics_alert do
    account { nil }
    sequence(:name) { |n| "Alert #{n}" }
    alert_type { "threshold" }
    metric_name { "mrr" }
    condition { "greater_than" }
    threshold_value { 50000 }
    status { "enabled" }
    cooldown_minutes { 60 }
    cooldown_until { nil }
    trigger_count { 0 }
    current_value { nil }
    last_checked_at { nil }
    last_triggered_at { nil }
    auto_resolve { false }
    notification_channels { [ "email:admin@example.com" ] }
    metadata { {} }

    trait :with_account do
      account
    end

    trait :disabled do
      status { "disabled" }
    end

    trait :triggered do
      status { "triggered" }
      last_triggered_at { 30.minutes.ago }
      trigger_count { 1 }
    end

    trait :resolved do
      status { "resolved" }
    end

    trait :less_than do
      condition { "less_than" }
      metric_name { "customer_count" }
      threshold_value { 100 }
    end

    trait :change_percent do
      condition { "change_percent" }
      metric_name { "churn_rate" }
      threshold_value { 10 }
    end

    trait :anomaly do
      alert_type { "anomaly" }
      condition { "anomaly_detected" }
    end

    trait :recently_triggered do
      status { "triggered" }
      last_triggered_at { 30.minutes.ago }
      trigger_count { 5 }
    end

    trait :in_cooldown do
      status { "triggered" }
      cooldown_until { 30.minutes.from_now }
      last_triggered_at { 30.minutes.ago }
    end

    trait :with_slack do
      notification_channels { [ "email:admin@example.com", "slack:#alerts" ] }
    end

    trait :with_webhook do
      notification_channels { [ "email:admin@example.com", "webhook:https://example.com/webhook" ] }
    end
  end
end
