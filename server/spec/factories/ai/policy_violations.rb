# frozen_string_literal: true

FactoryBot.define do
  factory :ai_policy_violation, class: "Ai::PolicyViolation" do
    account
    association :policy, factory: :ai_compliance_policy
    violation_id { SecureRandom.uuid }
    severity { "medium" }
    status { "open" }
    description { Faker::Lorem.paragraph }
    source_type { "Ai::Agent" }
    source_id { SecureRandom.uuid }
    detected_at { Time.current }
    context { { action: "agent_execution", user_id: SecureRandom.uuid } }
    violation_data { {} }
    remediation_steps { [] }

    trait :open do
      status { "open" }
    end

    trait :acknowledged do
      status { "acknowledged" }
      acknowledged_at { Time.current }
      association :detected_by, factory: :user
    end

    trait :investigating do
      status { "investigating" }
      association :detected_by, factory: :user
    end

    trait :resolved do
      status { "resolved" }
      resolved_at { Time.current }
      association :resolved_by, factory: :user
      resolution_notes { "Issue resolved by updating policy configuration" }
      resolution_action { "policy_updated" }
    end

    trait :dismissed do
      status { "dismissed" }
      resolved_at { Time.current }
      association :resolved_by, factory: :user
      resolution_notes { "False positive - no action required" }
      resolution_action { "dismissed" }
    end

    trait :escalated do
      status { "escalated" }
      escalated_at { Time.current }
    end

    trait :low do
      severity { "low" }
    end

    trait :medium do
      severity { "medium" }
    end

    trait :high do
      severity { "high" }
    end

    trait :critical do
      severity { "critical" }
    end

    trait :from_agent do
      source_type { "Ai::Agent" }
    end

    trait :from_workflow do
      source_type { "Ai::Workflow" }
    end

    trait :from_conversation do
      source_type { "Ai::Conversation" }
    end

    trait :with_remediation_steps do
      remediation_steps do
        [
          { step: 1, action: "Review the policy configuration", completed: false },
          { step: 2, action: "Update enforcement level", completed: false },
          { step: 3, action: "Notify affected users", completed: false }
        ]
      end
    end

    trait :data_access_violation do
      description { "Unauthorized data access attempt detected" }
      violation_data do
        {
          attempted_action: "read",
          resource: "sensitive_data",
          classification: "pii"
        }
      end
    end

    trait :cost_limit_violation do
      description { "Cost limit exceeded for AI operations" }
      violation_data do
        {
          limit: 100.00,
          actual: 150.00,
          currency: "USD"
        }
      end
    end
  end
end
