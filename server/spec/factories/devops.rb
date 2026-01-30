# frozen_string_literal: true

FactoryBot.define do
  # Alias for backwards compatibility with ci_cd naming
  factory :ci_cd_pipeline, class: 'Devops::Pipeline' do
    association :account
    name { "CI/CD Pipeline #{SecureRandom.hex(4)}" }
    slug { name.parameterize }
    pipeline_type { 'deploy' }
    description { 'CI/CD pipeline for specs' }
    triggers { { 'manual' => true } }
    steps { [] }
    environment { {} }
    secret_refs { [] }
    runner_labels { ['ubuntu-latest'] }
    timeout_minutes { 60 }
    allow_concurrent { false }
    features { {} }
    is_active { true }
    is_system { false }
    version { 1 }
  end

  factory :devops_pipeline, class: 'Devops::Pipeline' do
    association :account
    name { "Test Pipeline #{SecureRandom.hex(4)}" }
    slug { name.parameterize }
    pipeline_type { 'deploy' }
    description { 'Test pipeline for specs' }
    triggers { { 'manual' => true } }
    steps { [] }
    environment { {} }
    secret_refs { [] }
    runner_labels { ['ubuntu-latest'] }
    timeout_minutes { 60 }
    allow_concurrent { false }
    features { {} }
    is_active { true }
    is_system { false }
    version { 1 }

    trait :with_approval_features do
      features { { 'approval_required' => true } }
    end
  end

  factory :devops_pipeline_step, class: 'Devops::PipelineStep' do
    association :pipeline, factory: :devops_pipeline
    sequence(:name) { |n| "Step #{n}" }
    step_type { 'custom' }
    sequence(:position) { |n| n }
    configuration { { 'description' => 'Test step' } }
    inputs { {} }
    outputs { [] }
    condition { nil }
    continue_on_error { false }
    is_active { true }
    requires_approval { false }
    approval_settings { {} }

    trait :with_approval do
      requires_approval { true }
      approval_settings do
        {
          'timeout_hours' => 24,
          'require_comment' => false,
          'notification_recipients' => [
            { 'type' => 'email', 'value' => 'approver@example.com' }
          ]
        }
      end
    end

    trait :requires_comment do
      requires_approval { true }
      approval_settings do
        {
          'timeout_hours' => 24,
          'require_comment' => true,
          'notification_recipients' => []
        }
      end
    end
  end

  factory :devops_pipeline_run, class: 'Devops::PipelineRun' do
    association :pipeline, factory: :devops_pipeline
    sequence(:run_number) { |n| n.to_s }
    status { 'pending' }
    trigger_type { 'manual' }
    trigger_context { { 'triggered_by' => 'Test' } }
    outputs { {} }
    artifacts { [] }

    trait :running do
      status { 'running' }
      started_at { Time.current }
    end

    trait :completed do
      status { 'success' }
      started_at { 1.hour.ago }
      completed_at { Time.current }
      duration_seconds { 3600 }
    end

    trait :failed do
      status { 'failure' }
      started_at { 1.hour.ago }
      completed_at { Time.current }
      error_message { 'Pipeline failed' }
    end
  end

  factory :devops_step_execution, class: 'Devops::StepExecution' do
    association :pipeline_run, factory: :devops_pipeline_run
    association :pipeline_step, factory: :devops_pipeline_step
    status { 'pending' }
    outputs { {} }

    trait :running do
      status { 'running' }
      started_at { Time.current }
    end

    trait :waiting_approval do
      status { 'waiting_approval' }
      started_at { Time.current }
    end

    trait :completed do
      status { 'completed' }
      started_at { 1.minute.ago }
      completed_at { Time.current }
      duration_seconds { 60 }
    end

    trait :failed do
      status { 'failure' }
      started_at { 1.minute.ago }
      completed_at { Time.current }
      error_message { 'Step failed' }
    end
  end

  factory :devops_step_approval_token, class: 'Devops::StepApprovalToken' do
    association :step_execution, factory: [:devops_step_execution, :waiting_approval]
    recipient_email { Faker::Internet.email }
    token_digest { Digest::SHA256.hexdigest(SecureRandom.urlsafe_base64(32)) }
    status { 'pending' }
    expires_at { 24.hours.from_now }

    trait :approved do
      status { 'approved' }
      responded_at { Time.current }
      response_comment { 'Approved' }
    end

    trait :rejected do
      status { 'rejected' }
      responded_at { Time.current }
      response_comment { 'Rejected' }
    end

    trait :expired do
      status { 'expired' }
      expires_at { 1.hour.ago }
    end

    trait :with_user do
      association :recipient_user, factory: :user
    end

    trait :with_responder do
      association :responded_by, factory: :user
    end
  end

  # Aliases for backward compatibility with specs using ci_cd_ prefix
  factory :ci_cd_pipeline_run, parent: :devops_pipeline_run
  factory :ci_cd_pipeline_step, parent: :devops_pipeline_step
  factory :ci_cd_step_execution, parent: :devops_step_execution
end
