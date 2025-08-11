FactoryBot.define do
  factory :user do
    association :account
    sequence(:email) { |n| "user#{n}@example.com" }
    first_name { Faker::Name.first_name }
    last_name { Faker::Name.last_name }
    password { 'UncommonStr0ngP@ssw0rd#99' }
    status { 'active' }
    role { 'member' } # Default role for single role system
    email_verified_at { 1.day.ago }

    trait :owner do
      role { 'owner' }
    end

    trait :admin do
      role { 'admin' }
    end

    trait :member do
      role { 'member' }
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
