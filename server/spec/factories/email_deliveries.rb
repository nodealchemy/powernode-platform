# frozen_string_literal: true

FactoryBot.define do
  factory :email_delivery do
    association :user
    sequence(:recipient_email) { |n| "recipient#{n}@example.com" }
    subject { "Test Email Subject" }
    email_type { "password_reset" }
    status { "pending" }
    retry_count { 0 }

    trait :sent do
      status { "sent" }
      sent_at { Time.current }
    end

    trait :failed do
      status { "failed" }
      error_message { "SMTP connection refused" }
    end

    trait :password_reset do
      email_type { "password_reset" }
      subject { "Reset Your Password" }
    end

    trait :welcome do
      email_type { "welcome" }
      subject { "Welcome to Powernode" }
    end

    trait :notification do
      email_type { "notification" }
      subject { "System Notification" }
    end

    trait :verification do
      email_type { "verification" }
      subject { "Verify Your Email" }
    end
  end
end
