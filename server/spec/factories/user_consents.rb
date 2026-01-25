# frozen_string_literal: true

FactoryBot.define do
  factory :user_consent do
    association :user
    association :account
    consent_type { "marketing" }
    collection_method { "explicit" }
    granted { true }
    granted_at { Time.current }
    version { "1.0" }
    consent_text { "I agree to receive marketing communications." }
    ip_address { Faker::Internet.ip_v4_address }
    user_agent { "Mozilla/5.0 (Test Browser)" }
    metadata { {} }

    trait :marketing do
      consent_type { "marketing" }
      consent_text { "I agree to receive marketing communications." }
    end

    trait :analytics do
      consent_type { "analytics" }
      consent_text { "I agree to analytics data collection." }
    end

    trait :cookies do
      consent_type { "cookies" }
      consent_text { "I accept cookies for this website." }
    end

    trait :data_sharing do
      consent_type { "data_sharing" }
      consent_text { "I agree to share my data with third parties." }
    end

    trait :newsletter do
      consent_type { "newsletter" }
      consent_text { "I agree to receive newsletter updates." }
    end

    trait :withdrawn do
      granted { false }
      withdrawn_at { Time.current }
    end

    trait :expired do
      expires_at { 1.day.ago }
    end

    trait :implicit do
      collection_method { "implicit" }
    end

    trait :opt_out do
      collection_method { "opt_out" }
    end
  end
end
