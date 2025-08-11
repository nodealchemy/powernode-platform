FactoryBot.define do
  factory :user do
    association :account
    sequence(:email) { |n| "user#{n}@example.com" }
    first_name { Faker::Name.first_name }
    last_name { Faker::Name.last_name }
    password { 'UncommonStr0ngP@ssw0rd#99' }
    status { 'active' }
    email_verified_at { 1.day.ago }
    
    transient do
      skip_roles { false }
    end

    after(:create) do |user, evaluator|
      # Assign default Member role if no roles assigned yet and not skipping roles
      if user.roles.empty? && !evaluator.try(:skip_roles)
        member_role = Role.find_by(name: 'Member') || create(:role, :member)
        user.roles << member_role
      end
    end

    trait :owner do
      after(:create) do |user|
        user.roles.clear
        owner_role = Role.find_by(name: 'Owner') || create(:role, :owner)
        user.roles << owner_role
      end
    end

    trait :admin do
      after(:create) do |user|
        user.roles.clear
        admin_role = Role.find_by(name: 'Admin') || create(:role, :admin)
        user.roles << admin_role
      end
    end

    trait :member do
      after(:create) do |user|
        user.roles.clear
        member_role = Role.find_by(name: 'Member') || create(:role, :member)
        user.roles << member_role
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

    trait :skip_owner_callback do
      # This trait can be used when creating multiple users for the same account
      skip_roles { true }
    end
  end
end
