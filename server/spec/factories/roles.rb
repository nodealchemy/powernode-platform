FactoryBot.define do
  factory :role do
    sequence(:name) { |n| "test_role_#{n}".downcase.gsub(/[^a-z_]/, '_') }
    display_name { "Test Role" }
    description { Faker::Lorem.sentence }
    role_type { 'user' }
    is_system { false }

    trait :system do
      is_system { true }
    end

    trait :owner do
      sequence(:name) { |n| "test_owner_#{n}" }
      display_name { 'Test Account Owner' }
      description { 'Test account owner with full account management capabilities' }
      role_type { 'user' }
      is_system { false }
    end

    trait :admin do
      sequence(:name) { |n| "test_admin_#{n}" }
      display_name { 'Test Administrator' }
      description { 'Test system administrator with full administrative access' }
      role_type { 'admin' }
      is_system { false }
    end

    trait :member do
      sequence(:name) { |n| "test_member_#{n}" }
      display_name { 'Test Member' }
      description { 'Test basic account member with standard access' }
      role_type { 'user' }
      is_system { false }
    end

    trait :with_permissions do
      after(:create) do |role|
        permission = create(:permission)
        role.permissions << permission
      end
    end
  end
end
