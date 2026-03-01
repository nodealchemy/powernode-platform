# frozen_string_literal: true

FactoryBot.define do
  factory :ai_approval_chain, class: "Ai::ApprovalChain" do
    account
    association :created_by, factory: :user
    sequence(:name) { |n| "Approval Chain #{n}" }
    description { Faker::Lorem.paragraph }
    trigger_type { "workflow_deploy" }
    status { "active" }
    is_sequential { true }
    timeout_hours { 24 }
    timeout_action { "reject" }
    trigger_conditions { {} }
    usage_count { 0 }
    steps do
      [
        {
          "name" => "Manager Approval",
          "approvers" => [ "*" ],
          "required_approvals" => 1
        }
      ]
    end

    trait :active do
      status { "active" }
    end

    trait :disabled do
      status { "disabled" }
    end

    trait :workflow_deploy do
      trigger_type { "workflow_deploy" }
    end

    trait :agent_deploy do
      trigger_type { "agent_deploy" }
    end

    trait :high_cost do
      trigger_type { "high_cost" }
      trigger_conditions do
        { "cost_threshold_usd" => 100 }
      end
    end

    trait :sensitive_data do
      trigger_type { "sensitive_data" }
    end

    trait :model_change do
      trigger_type { "model_change" }
    end

    trait :policy_override do
      trigger_type { "policy_override" }
    end

    trait :manual do
      trigger_type { "manual" }
    end

    trait :parallel do
      is_sequential { false }
    end

    trait :multi_step do
      steps do
        [
          {
            "name" => "Team Lead Approval",
            "approvers" => [ "*" ],
            "required_approvals" => 1
          },
          {
            "name" => "Manager Approval",
            "approvers" => [ "*" ],
            "required_approvals" => 1
          },
          {
            "name" => "Director Approval",
            "approvers" => [ "*" ],
            "required_approvals" => 1
          }
        ]
      end
    end

    trait :auto_approve_on_timeout do
      timeout_action { "approve" }
    end

    trait :escalate_on_timeout do
      timeout_action { "escalate" }
    end

    trait :no_timeout do
      timeout_hours { nil }
      timeout_action { nil }
    end

    trait :with_requests do
      after(:create) do |chain|
        create_list(:ai_approval_request, 3, approval_chain: chain, account: chain.account)
      end
    end
  end
end
