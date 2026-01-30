# frozen_string_literal: true

FactoryBot.define do
  factory :notification do
    association :account
    association :user
    notification_type { "system_alert" }
    title { "Test Notification" }
    message { "This is a test notification message." }
    severity { "info" }
    category { "general" }

    trait :unread do
      read_at { nil }
    end

    trait :read do
      read_at { Time.current }
    end

    trait :dismissed do
      dismissed_at { Time.current }
    end

    trait :expired do
      expires_at { 1.day.ago }
    end

    trait :warning do
      severity { "warning" }
    end

    trait :error do
      severity { "error" }
    end

    trait :success do
      severity { "success" }
    end

    trait :billing do
      notification_type { "billing_reminder" }
      category { "billing" }
    end

    trait :security do
      notification_type { "security_alert" }
      category { "security" }
      severity { "warning" }
    end

    trait :with_action do
      action_url { "https://app.example.com/settings" }
      action_label { "View Settings" }
    end
  end
end
