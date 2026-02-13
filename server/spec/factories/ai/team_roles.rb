# frozen_string_literal: true

FactoryBot.define do
  factory :ai_team_role, class: "Ai::TeamRole" do
    account
    association :agent_team, factory: :ai_agent_team
    sequence(:role_name) { |n| "Role #{n}" }
    role_type { "worker" }
    role_description { Faker::Lorem.sentence }
    capabilities { %w[code_generation testing] }
    constraints { [] }
    tools_allowed { [] }
    context_access { {} }
    metadata { {} }
    priority_order { 0 }
    max_concurrent_tasks { 1 }
    can_delegate { false }
    can_escalate { true }

    trait :manager do
      role_type { "manager" }
      can_delegate { true }
    end

    trait :reviewer do
      role_type { "reviewer" }
    end

    trait :specialist do
      role_type { "specialist" }
    end
  end
end
