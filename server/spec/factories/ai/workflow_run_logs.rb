# frozen_string_literal: true

FactoryBot.define do
  factory :ai_workflow_run_log, class: "Ai::WorkflowRunLog" do
    association :workflow_run, factory: :ai_workflow_run
    log_level { 'info' }
    event_type { 'workflow_started' }
    message { 'Workflow execution log message' }
    logged_at { Time.current }
    context_data { {} }
    metadata { {} }

    trait :debug do
      log_level { 'debug' }
    end

    trait :info do
      log_level { 'info' }
    end

    trait :warn do
      log_level { 'warn' }
    end

    trait :error do
      log_level { 'error' }
      event_type { 'node_failed' }
    end

    trait :fatal do
      log_level { 'fatal' }
      event_type { 'workflow_failed' }
    end
  end
end
