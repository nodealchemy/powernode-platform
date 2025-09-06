FactoryBot.define do
  factory :api_key do
    sequence(:name) { |n| "API Key #{n}" }
    key_digest { SecureRandom.hex(32) }
    prefix { "pk_test_#{SecureRandom.hex(8)}" }
    is_active { true }
    permissions { [] }
    rate_limits { {} }
    association :account
    association :created_by, factory: :user

    trait :active do
      is_active { true }
    end

    trait :revoked do
      is_active { false }
    end

    trait :expired do
      expires_at { 1.day.ago }
      is_active { true }
    end
  end
end