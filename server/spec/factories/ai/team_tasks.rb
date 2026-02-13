# frozen_string_literal: true

FactoryBot.define do
  factory :ai_team_task, class: "Ai::TeamTask" do
    association :team_execution, factory: :ai_team_execution
    description { Faker::Lorem.sentence }
    status { "pending" }
    task_type { "execution" }
    priority { 5 }
    input_data { {} }
    output_data { {} }
    metadata { {} }
    tools_used { [] }
    tokens_used { 0 }
    cost_usd { 0.0 }
    retry_count { 0 }
    max_retries { 3 }

    trait :assigned do
      status { "assigned" }
      assigned_at { Time.current }
      association :assigned_role, factory: :ai_team_role
    end

    trait :in_progress do
      status { "in_progress" }
      started_at { 5.minutes.ago }
    end

    trait :completed do
      status { "completed" }
      started_at { 10.minutes.ago }
      completed_at { Time.current }
      duration_ms { 300_000 }
    end

    trait :failed do
      status { "failed" }
      started_at { 10.minutes.ago }
      completed_at { Time.current }
      failure_reason { "execution_error" }
    end

    trait :review do
      task_type { "review" }
    end

    trait :validation do
      task_type { "validation" }
    end
  end
end
