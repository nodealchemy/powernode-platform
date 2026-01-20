# frozen_string_literal: true

FactoryBot.define do
  factory :analytics_alert_event do
    association :analytics_alert
    account { nil }
    event_type { "triggered" }
    triggered_value { 60000 }
    threshold_value { 50000 }
    message { "MRR exceeded threshold" }
    severity { "medium" }
    acknowledged { false }
    acknowledged_at { nil }
    acknowledged_by { nil }
    resolved { false }
    resolved_at { nil }
    resolution_notes { nil }

    trait :acknowledged do
      acknowledged { true }
      acknowledged_at { 1.hour.ago }
      acknowledged_by { "admin@example.com" }
    end

    trait :resolved do
      event_type { "resolved" }
      resolved { true }
      resolved_at { 30.minutes.ago }
      resolution_notes { "Issue fixed" }
      severity { "info" }
    end

    trait :critical do
      severity { "critical" }
    end

    trait :high do
      severity { "high" }
    end

    trait :escalated do
      event_type { "escalated" }
    end

    trait :old do
      created_at { 2.days.ago }
    end

    trait :recent do
      created_at { 1.hour.ago }
    end
  end
end
