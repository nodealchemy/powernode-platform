FactoryBot.define do
  factory :role do
    sequence(:name) { |n| "Role #{n}" }
    description { Faker::Lorem.sentence }
    system_role { false }

    trait :system_role do
      system_role { true }
    end

    trait :owner do
      name { 'Owner' }
      description { 'Account owner with full administrative access' }
      system_role { true }
    end

    trait :admin do
      name { 'Admin' }
      description { 'Administrator with extensive permissions' }
      system_role { true }
    end

    trait :member do
      name { 'Member' }
      description { 'Regular member with basic access' }
      system_role { true }
    end

    trait :with_permissions do
      after(:create) do |role|
        permission = create(:permission)
        role.permissions << permission
      end
    end
  end
end
