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
        # Permissions are code-defined; grant real catalog permissions BY NAME
        # through the role_permissions join (no Permission AR model exists).
        %w[users.read users.create].each do |permission_name|
          role.role_permissions.find_or_create_by!(permission_name: permission_name)
        end
      end
    end
  end
end
