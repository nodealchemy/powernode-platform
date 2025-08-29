FactoryBot.define do
  factory :api_key do
    sequence(:name) { |n| "API Key #{n}" }
    key_hash { SecureRandom.hex(32) }
    status { 'active' }
    association :account
    association :created_by, factory: :user

    trait :active do
      status { 'active' }
    end

    trait :revoked do
      status { 'revoked' }
    end

    trait :expired do
      status { 'expired' }
      expires_at { 1.day.ago }
    end
  end
end