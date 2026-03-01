# frozen_string_literal: true

FactoryBot.define do
  factory :ai_approval_request, class: "Ai::ApprovalRequest" do
    account
    association :approval_chain, factory: :ai_approval_chain
    association :requested_by, factory: :user
    request_id { SecureRandom.uuid }
    status { "pending" }
    source_type { "Ai::Workflow" }
    source_id { SecureRandom.uuid }
    description { Faker::Lorem.paragraph }
    request_data { { reason: "Deployment approval required" } }
    current_step { 0 }
    step_statuses do
      [
        {
          "step_number" => 0,
          "step_name" => "Manager Approval",
          "approvers" => [ "*" ],
          "status" => "pending",
          "required_approvals" => 1,
          "current_approvals" => 0
        }
      ]
    end
    expires_at { 24.hours.from_now }

    trait :pending do
      status { "pending" }
    end

    trait :approved do
      status { "approved" }
      completed_at { Time.current }
      step_statuses do
        [
          {
            "step_number" => 0,
            "step_name" => "Manager Approval",
            "approvers" => [ "*" ],
            "status" => "approved",
            "required_approvals" => 1,
            "current_approvals" => 1
          }
        ]
      end
    end

    trait :rejected do
      status { "rejected" }
      completed_at { Time.current }
      step_statuses do
        [
          {
            "step_number" => 0,
            "step_name" => "Manager Approval",
            "approvers" => [ "*" ],
            "status" => "rejected",
            "required_approvals" => 1,
            "current_approvals" => 0
          }
        ]
      end
    end

    trait :expired do
      status { "expired" }
      expires_at { 1.hour.ago }
    end

    trait :cancelled do
      status { "cancelled" }
      completed_at { Time.current }
    end

    trait :for_workflow do
      source_type { "Ai::Workflow" }
    end

    trait :for_agent do
      source_type { "Ai::Agent" }
    end

    trait :multi_step do
      current_step { 0 }
      step_statuses do
        [
          {
            "step_number" => 0,
            "step_name" => "Team Lead Approval",
            "approvers" => [ "*" ],
            "status" => "pending",
            "required_approvals" => 1,
            "current_approvals" => 0
          },
          {
            "step_number" => 1,
            "step_name" => "Manager Approval",
            "approvers" => [ "*" ],
            "status" => "pending",
            "required_approvals" => 1,
            "current_approvals" => 0
          }
        ]
      end
    end

    trait :no_expiry do
      expires_at { nil }
    end
  end
end
