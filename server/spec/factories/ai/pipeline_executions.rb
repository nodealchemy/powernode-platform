# frozen_string_literal: true

FactoryBot.define do
  factory :ai_pipeline_execution, class: "Ai::PipelineExecution" do
    association :account

    execution_id { SecureRandom.uuid }
    pipeline_type { "pr_review" }
    status { "pending" }
    trigger_source { "github" }
    trigger_event { "pull_request.opened" }
    repository_id { SecureRandom.uuid }
    branch { "feature/new-feature" }
    commit_sha { SecureRandom.hex(20) }
    input_data { { "files_changed" => 5, "additions" => 120, "deletions" => 30 } }
    output_data { {} }
    ai_analysis { {} }
    metrics { {} }

    trait :pending do
      status { "pending" }
    end

    trait :running do
      status { "running" }
      started_at { 2.minutes.ago }
    end

    trait :completed do
      status { "completed" }
      started_at { 5.minutes.ago }
      completed_at { 1.minute.ago }
      duration_ms { 240_000 }
      output_data do
        {
          "review_completed" => true,
          "issues_found" => 3,
          "suggestions" => 5
        }
      end
      ai_analysis do
        {
          "code_quality_score" => 85,
          "security_score" => 92,
          "test_coverage_impact" => -2.5
        }
      end
      metrics do
        {
          "tokens_used" => 1500,
          "cost_usd" => 0.025,
          "files_analyzed" => 8
        }
      end
    end

    trait :failed do
      status { "failed" }
      started_at { 3.minutes.ago }
      completed_at { 1.minute.ago }
      duration_ms { 120_000 }
      output_data do
        {
          "error" => {
            "message" => "AI provider timeout",
            "code" => "PROVIDER_TIMEOUT"
          }
        }
      end
    end

    trait :cancelled do
      status { "cancelled" }
      started_at { 2.minutes.ago }
      completed_at { Time.current }
    end

    trait :timeout do
      status { "timeout" }
      started_at { 10.minutes.ago }
      completed_at { Time.current }
      duration_ms { 600_000 }
    end

    trait :pr_review do
      pipeline_type { "pr_review" }
      pull_request_number { "123" }
      trigger_event { "pull_request.opened" }
    end

    trait :commit_analysis do
      pipeline_type { "commit_analysis" }
      trigger_event { "push" }
      pull_request_number { nil }
    end

    trait :deployment do
      pipeline_type { "deployment" }
      trigger_event { "deployment.created" }
      input_data do
        {
          "environment" => "production",
          "version" => "1.2.3",
          "changes" => 15
        }
      end
    end

    trait :release do
      pipeline_type { "release" }
      trigger_event { "release.created" }
      input_data do
        {
          "tag" => "v1.2.3",
          "commits_since_last_release" => 42
        }
      end
    end

    trait :scheduled do
      pipeline_type { "scheduled" }
      trigger_source { "cron" }
      trigger_event { "scheduled.daily" }
    end

    trait :manual do
      pipeline_type { "manual" }
      trigger_source { "user" }
      trigger_event { "manual.trigger" }
      association :triggered_by, factory: :user
    end

    trait :with_devops_installation do
      association :devops_installation, factory: :ai_devops_template_installation
    end

    trait :with_workflow_run do
      association :workflow_run, factory: :ai_workflow_run
    end

    trait :with_deployment_risks do
      after(:create) do |execution|
        create_list(:ai_deployment_risk, 2,
                    pipeline_execution: execution,
                    account: execution.account)
      end
    end

    trait :with_code_reviews do
      after(:create) do |execution|
        create(:ai_code_review,
               pipeline_execution: execution,
               account: execution.account)
      end
    end
  end
end
