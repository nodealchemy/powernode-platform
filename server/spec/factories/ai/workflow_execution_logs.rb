# frozen_string_literal: true

# NOTE: This factory references Ai::WorkflowRunLog (the correct model class).
# The factory name :ai_workflow_execution_log is kept as an alias for backward
# compatibility with specs that reference it.
FactoryBot.define do
  factory :ai_workflow_execution_log, class: "Ai::WorkflowRunLog" do
    association :workflow_run, factory: :ai_workflow_run
    log_level { 'info' }
    event_type { 'workflow_started' }
    message { 'Workflow execution log message' }
    logged_at { Time.current }
    context_data { {} }
    metadata { {} }

    trait :debug do
      log_level { 'debug' }
      event_type { 'variable_updated' }
      message { 'Debug information for workflow execution' }
    end

    trait :info do
      log_level { 'info' }
      event_type { 'node_completed' }
      message { 'Workflow step completed successfully' }
    end

    trait :warn do
      log_level { 'warn' }
      event_type { 'timeout_detected' }
      message { 'Workflow execution warning' }
    end

    trait :error do
      log_level { 'error' }
      event_type { 'node_failed' }
      message { 'Node execution failed' }
    end

    trait :fatal do
      log_level { 'fatal' }
      event_type { 'workflow_failed' }
      message { 'Critical workflow execution failure' }
    end

    trait :node_start do
      event_type { 'node_started' }
      message { 'Node execution started' }
    end

    trait :node_complete do
      event_type { 'node_completed' }
      message { 'Node execution completed' }
    end

    trait :workflow_start do
      event_type { 'workflow_started' }
      message { 'Workflow execution started' }
    end

    trait :workflow_complete do
      event_type { 'workflow_completed' }
      message { 'Workflow execution completed successfully' }
    end

    trait :api_call_log do
      event_type { 'api_called' }
      message { 'API call executed' }
    end

    trait :webhook_sent do
      event_type { 'webhook_sent' }
      message { 'Webhook notification sent' }
    end

    trait :condition_evaluated do
      event_type { 'condition_evaluated' }
      message { 'Condition evaluation completed' }
    end

    trait :human_approval_requested do
      event_type { 'approval_requested' }
      message { 'Human approval requested' }
    end

    trait :data_transform do
      event_type { 'data_transformed' }
      message { 'Data transformation executed' }
    end

    trait :retry_attempt do
      log_level { 'warn' }
      event_type { 'retry_attempted' }
      message { 'Retrying failed node execution' }
    end

    trait :cost_tracking do
      event_type { 'cost_added' }
      message { 'Cost tracking update' }
    end
  end
end
