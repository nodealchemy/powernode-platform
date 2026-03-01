# frozen_string_literal: true

FactoryBot.define do
  factory :ai_runner_dispatch, class: "Ai::RunnerDispatch" do
    account
    status { "pending" }
    input_params { {} }
    output_result { {} }
    runner_labels { [] }

    trait :dispatched do
      status { "dispatched" }
      dispatched_at { Time.current }
    end

    trait :completed do
      status { "completed" }
      dispatched_at { 10.minutes.ago }
      completed_at { Time.current }
      duration_ms { 600_000 }
    end

    trait :failed do
      status { "failed" }
      dispatched_at { 5.minutes.ago }
      completed_at { Time.current }
    end
  end
end
