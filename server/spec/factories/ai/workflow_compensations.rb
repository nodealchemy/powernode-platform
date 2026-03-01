# frozen_string_literal: true

FactoryBot.define do
  factory :ai_workflow_compensation, class: "Ai::WorkflowCompensation" do
    association :workflow_run, factory: :ai_workflow_run
    association :workflow_node_execution, factory: :ai_workflow_node_execution
    compensation_id { SecureRandom.uuid }
    compensation_type { "rollback" }
    trigger_reason { "node_failure" }
    status { "pending" }
    original_action { { "action" => "create_resource" } }
    compensation_action { { "action" => "delete_resource" } }
    compensation_result { {} }
    metadata { {} }
    retry_count { 0 }
    max_retries { 3 }

    trait :completed do
      status { "completed" }
      executed_at { 5.minutes.ago }
      completed_at { Time.current }
    end

    trait :failed do
      status { "failed" }
      executed_at { 5.minutes.ago }
      failed_at { Time.current }
    end

    trait :retry_compensation do
      compensation_type { "retry" }
    end
  end
end
