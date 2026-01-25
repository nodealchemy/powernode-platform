# frozen_string_literal: true

FactoryBot.define do
  factory :ai_performance_benchmark, class: "Ai::PerformanceBenchmark" do
    association :account
    association :sandbox, factory: :ai_sandbox
    association :created_by, factory: :user

    benchmark_id { SecureRandom.uuid }
    sequence(:name) { |n| "Performance Benchmark #{n}" }
    description { "Testing performance metrics" }
    status { "active" }
    baseline_metrics { { "latency_ms" => 100, "throughput" => 1000 } }
    thresholds { { "latency_ms" => { "max" => 200 }, "throughput" => { "min" => 500 } } }
    sample_size { 100 }
    run_count { 0 }
    latest_results { {} }
    latest_score { nil }
    trend { "stable" }

    trait :active do
      status { "active" }
    end

    trait :paused do
      status { "paused" }
    end

    trait :archived do
      status { "archived" }
    end

    trait :with_results do
      run_count { 5 }
      latest_results { { "latency_ms" => 95, "throughput" => 1050 } }
      latest_score { 105.3 }
      trend { "improving" }
      last_run_at { 1.hour.ago }
    end

    trait :with_workflow do
      association :target_workflow, factory: :ai_workflow
    end

    trait :with_agent do
      association :target_agent, factory: :ai_agent
    end
  end
end
