# frozen_string_literal: true

FactoryBot.define do
  factory :ai_test_run, class: "Ai::TestRun" do
    association :account
    association :sandbox, factory: :ai_sandbox
    association :triggered_by, factory: :user

    run_id { SecureRandom.uuid }
    run_type { "manual" }
    status { "pending" }
    scenario_ids { [] }
    total_scenarios { 0 }
    passed_scenarios { 0 }
    failed_scenarios { 0 }
    skipped_scenarios { 0 }
    total_assertions { 0 }
    passed_assertions { 0 }
    failed_assertions { 0 }
    summary { {} }
    environment { {} }

    trait :pending do
      status { "pending" }
    end

    trait :running do
      status { "running" }
      started_at { Time.current }
    end

    trait :completed do
      status { "completed" }
      started_at { 5.minutes.ago }
      completed_at { Time.current }
      duration_ms { 300_000 }
      total_scenarios { 10 }
      passed_scenarios { 8 }
      failed_scenarios { 1 }
      skipped_scenarios { 1 }
    end

    trait :failed do
      status { "failed" }
      started_at { 5.minutes.ago }
      completed_at { Time.current }
      duration_ms { 120_000 }
      total_scenarios { 5 }
      passed_scenarios { 2 }
      failed_scenarios { 3 }
    end

    trait :scheduled do
      run_type { "scheduled" }
    end

    trait :ci_triggered do
      run_type { "ci_triggered" }
    end
  end
end
