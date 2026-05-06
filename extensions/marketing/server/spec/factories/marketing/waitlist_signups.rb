# frozen_string_literal: true

FactoryBot.define do
  factory :marketing_waitlist_signup, class: "Marketing::WaitlistSignup" do
    sequence(:email) { |n| "waitlist#{n}@example.com" }
    status { "pending" }
    source { "homepage" }

    trait :confirmed do
      status { "confirmed" }
      confirmed_at { Time.current }
    end

    trait :unsubscribed do
      status { "unsubscribed" }
      unsubscribed_at { Time.current }
    end

    trait :converted do
      # "converted" is tracked via converted_account_id FK, not status.
      # Caller passes an account explicitly via association(:converted_account).
      converted_at { Time.current }
    end

    trait :with_utm do
      metadata { { "utm_source" => "twitter", "utm_medium" => "social", "utm_campaign" => "launch-2026" } }
    end
  end
end
