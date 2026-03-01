# frozen_string_literal: true

FactoryBot.define do
  factory :ai_team_execution, class: "Ai::TeamExecution" do
    account
    association :agent_team, factory: :ai_agent_team
    execution_id { SecureRandom.uuid }
    status { "pending" }
    objective { Faker::Lorem.sentence }
    metadata { {} }
    input_context { {} }
    output_result { {} }
    shared_memory { {} }
    performance_metrics { {} }
    tasks_total { 0 }
    tasks_completed { 0 }
    tasks_failed { 0 }
    total_tokens_used { 0 }
    total_cost_usd { 0.0 }
    messages_exchanged { 0 }
    resume_count { 0 }

    trait :running do
      status { "running" }
      started_at { 5.minutes.ago }
    end

    trait :completed do
      status { "completed" }
      started_at { 10.minutes.ago }
      completed_at { Time.current }
      duration_ms { 600_000 }
    end

    trait :failed do
      status { "failed" }
      started_at { 10.minutes.ago }
      completed_at { Time.current }
      termination_reason { "execution_error" }
    end
  end
end
