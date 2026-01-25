# frozen_string_literal: true

FactoryBot.define do
  factory :ai_compliance_audit_entry, class: "Ai::ComplianceAuditEntry" do
    account
    association :user, factory: :user
    entry_id { SecureRandom.uuid }
    action_type { "policy_update" }
    resource_type { "Ai::CompliancePolicy" }
    resource_id { SecureRandom.uuid }
    outcome { "success" }
    description { Faker::Lorem.sentence }
    occurred_at { Time.current }
    before_state { {} }
    after_state { {} }
    context { {} }
    ip_address { Faker::Internet.ip_v4_address }
    user_agent { "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" }

    trait :success do
      outcome { "success" }
    end

    trait :failure do
      outcome { "failure" }
      description { "Operation failed: #{Faker::Lorem.sentence}" }
    end

    trait :blocked do
      outcome { "blocked" }
      description { "Operation blocked by policy" }
    end

    trait :warning do
      outcome { "warning" }
      description { "Operation completed with warnings" }
    end

    trait :with_state_change do
      before_state do
        {
          status: "draft",
          enforcement_level: "log"
        }
      end
      after_state do
        {
          status: "active",
          enforcement_level: "warn"
        }
      end
    end

    trait :policy_created do
      action_type { "policy_create" }
      before_state { {} }
      after_state do
        {
          name: "New Policy",
          status: "draft",
          policy_type: "data_access"
        }
      end
    end

    trait :agent_execution do
      action_type { "agent_execution" }
      resource_type { "Ai::Agent" }
    end

    trait :workflow_run do
      action_type { "workflow_run" }
      resource_type { "Ai::Workflow" }
    end

    trait :data_access do
      action_type { "data_access" }
      resource_type { "Ai::DataClassification" }
    end
  end
end
