FactoryBot.define do
  factory :user do
    association :account
    sequence(:email) { |n| "user#{n}@example.com" }
    first_name { Faker::Name.first_name }
    last_name { Faker::Name.last_name }
    password { 'UncommonStr0ngP@ssw0rd99!' }
    status { 'active' }
    email_verified_at { 1.day.ago }

    # Default role assignment happens in after_create callback
    after(:create) do |user, evaluator|
      # User gets 'member' role by default via model callback
    end

    trait :owner do
      after(:create) do |user|
        user.roles = []
        user.add_role('owner')
      end
    end

    trait :admin do
      after(:create) do |user|
        user.roles = []
        user.add_role('admin')
      end
    end

    trait :super_admin do
      after(:create) do |user|
        user.roles = []
        user.add_role('super_admin')
      end
    end

    trait :manager do
      after(:create) do |user|
        user.roles = []
        user.add_role('manager')
      end
    end

    trait :member do
      after(:create) do |user|
        user.roles = []
        user.add_role('member')
      end
    end

    trait :billing_admin do
      after(:create) do |user|
        user.roles = []
        user.add_role('billing_admin')
      end
    end

    trait :inactive do
      status { 'inactive' }
    end

    trait :suspended do
      status { 'suspended' }
    end

    trait :unverified do
      email_verified_at { nil }
    end
  end
end
