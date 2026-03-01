# frozen_string_literal: true

FactoryBot.define do
  factory :reseller do
    association :account
    association :primary_user, factory: :user

    company_name { "Test Reseller #{SecureRandom.hex(4)}" }
    contact_email { Faker::Internet.email }
    tier { 'bronze' }
    status { 'active' }
    # Don't set referral_code - model auto-generates it
    # Don't set commission_percentage - model sets by tier

    trait :pending do
      status { 'pending' }
    end

    trait :approved do
      status { 'approved' }
      approved_at { Time.current }
      association :approved_by, factory: :user
    end

    trait :suspended do
      status { 'suspended' }
    end

    trait :silver do
      tier { 'silver' }
    end

    trait :gold do
      tier { 'gold' }
    end

    trait :platinum do
      tier { 'platinum' }
    end
  end
end
