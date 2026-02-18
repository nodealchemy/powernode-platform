# frozen_string_literal: true

FactoryBot.define do
  factory :ai_delegation_policy, class: "Ai::DelegationPolicy" do
    account
    association :agent, factory: :ai_agent
    max_depth { 3 }
    allowed_delegate_types { [] }
    delegatable_actions { [] }
    budget_delegation_pct { 0.5 }
    inheritance_policy { "conservative" }

    trait :restrictive do
      max_depth { 1 }
      allowed_delegate_types { ["assistant"] }
      delegatable_actions { ["read_data"] }
      budget_delegation_pct { 0.2 }
    end

    trait :permissive do
      max_depth { 5 }
      budget_delegation_pct { 0.8 }
      inheritance_policy { "permissive" }
    end
  end
end
