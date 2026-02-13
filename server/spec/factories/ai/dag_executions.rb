# frozen_string_literal: true

FactoryBot.define do
  factory :ai_dag_execution, class: "Ai::DagExecution" do
    account
    sequence(:name) { |n| "DAG Execution #{n}" }
    status { "pending" }
    dag_definition { {} }
    execution_plan { [] }
    node_states { {} }
    shared_context { {} }
    checkpoint_data { {} }
    final_outputs { {} }
    total_nodes { 5 }
    completed_nodes { 0 }
    failed_nodes { 0 }
    running_nodes { 0 }
    resumable { true }

    trait :running do
      status { "running" }
      started_at { 5.minutes.ago }
      running_nodes { 2 }
    end

    trait :completed do
      status { "completed" }
      started_at { 10.minutes.ago }
      completed_at { Time.current }
      duration_ms { 600_000 }
      completed_nodes { 5 }
    end

    trait :failed do
      status { "failed" }
      started_at { 10.minutes.ago }
      completed_at { Time.current }
      failed_nodes { 1 }
      error_message { "Node execution failed" }
    end
  end
end
