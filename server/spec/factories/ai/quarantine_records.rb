# frozen_string_literal: true

FactoryBot.define do
  factory :ai_quarantine_record, class: "Ai::QuarantineRecord" do
    account
    agent_id { SecureRandom.uuid }
    severity { "medium" }
    status { "active" }
    trigger_reason { "Anomalous behavior detected" }
    trigger_source { "anomaly_detection" }
    restrictions_applied { { monitoring_level: "high" } }
    forensic_snapshot { { agent_status: "active", captured_at: Time.current.iso8601 } }
    previous_capabilities { { skill_slugs: [], status: "active" } }
    cooldown_minutes { 60 }
    scheduled_restore_at { 60.minutes.from_now }

    trait :low do
      severity { "low" }
      cooldown_minutes { 30 }
      scheduled_restore_at { 30.minutes.from_now }
    end

    trait :high do
      severity { "high" }
      cooldown_minutes { 240 }
      scheduled_restore_at { 240.minutes.from_now }
    end

    trait :critical do
      severity { "critical" }
      cooldown_minutes { 1440 }
      scheduled_restore_at { nil }
    end

    trait :escalated do
      status { "escalated" }
    end

    trait :restored do
      status { "restored" }
      restored_at { Time.current }
      approved_by_id { SecureRandom.uuid }
      restoration_notes { "Restored by admin" }
    end

    trait :restorable do
      status { "active" }
      scheduled_restore_at { 1.minute.ago }
    end

    trait :expired_status do
      status { "expired" }
    end
  end
end
