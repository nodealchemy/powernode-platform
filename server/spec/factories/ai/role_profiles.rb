# frozen_string_literal: true

FactoryBot.define do
  factory :ai_role_profile, class: "Ai::RoleProfile" do
    account
    sequence(:name) { |n| "Role Profile #{n}" }
    sequence(:slug) { |n| "role-profile-#{n}" }
    role_type { "worker" }
    description { Faker::Lorem.sentence }
    is_system { false }
    communication_style { {} }
    delegation_rules { {} }
    escalation_rules { {} }
    expected_output_schema { {} }
    quality_checks { [] }
    review_criteria { [] }
    metadata { {} }

    trait :system_profile do
      is_system { true }
      account { nil }
    end

    trait :manager do
      role_type { "manager" }
    end

    trait :reviewer do
      role_type { "reviewer" }
    end
  end
end
