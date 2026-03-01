# frozen_string_literal: true

FactoryBot.define do
  factory :ai_agent_privilege_policy, class: "Ai::AgentPrivilegePolicy" do
    account
    sequence(:policy_name) { |n| "policy_#{n}" }
    policy_type { "custom" }
    allowed_actions { [] }
    denied_actions { [] }
    allowed_tools { [] }
    denied_tools { [] }
    allowed_resources { [] }
    denied_resources { [] }
    communication_rules { {} }
    escalation_rules { {} }
    priority { 0 }
    active { true }

    trait :system do
      policy_type { "system" }
    end

    trait :trust_tier do
      policy_type { "trust_tier" }
      trust_tier { "supervised" }
    end

    trait :for_supervised do
      policy_type { "trust_tier" }
      trust_tier { "supervised" }
      denied_actions { %w[delete_data modify_system spawn_agent] }
      denied_tools { %w[execute_code] }
    end

    trait :restrictive do
      denied_actions { %w[delete_data external_api_call spawn_agent modify_system] }
      denied_tools { %w[execute_code shell_command] }
    end

    trait :inactive do
      active { false }
    end

    trait :high_priority do
      priority { 100 }
    end
  end
end
