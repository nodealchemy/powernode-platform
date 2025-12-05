# frozen_string_literal: true

FactoryBot.define do
  factory :account_delegation do
    association :account
    association :delegated_user, factory: :user
    association :delegated_by, factory: :user
    role { nil }  # Optional - tests can specify when needed

    status { 'active' }
    expires_at { 30.days.from_now }
    notes { Faker::Lorem.sentence }

    trait :active do
      status { 'active' }
      expires_at { 30.days.from_now }
    end

    trait :inactive do
      status { 'inactive' }
    end

    trait :revoked do
      status { 'revoked' }
      revoked_at { 1.day.ago }
      association :revoked_by, factory: :user
    end

    trait :expired do
      status { 'active' }
      expires_at { 1.day.ago }
    end

    trait :no_expiration do
      expires_at { nil }
    end

    trait :with_permissions do
      transient do
        permission_count { 3 }
      end

      after(:create) do |delegation, evaluator|
        create_list(:delegation_permission, evaluator.permission_count, account_delegation: delegation)
      end
    end

    trait :without_role do
      role { nil }
    end
  end
end
