# frozen_string_literal: true

FactoryBot.define do
  factory :git_webhook_event, class: 'Devops::GitWebhookEvent' do
    association :git_provider
    association :account
    association :repository, factory: :git_repository

    event_type { 'push' }
    action { nil }
    sequence(:delivery_id) { |n| "delivery_#{n}" }
    status { 'pending' }
    payload do
      {
        ref: 'refs/heads/main',
        repository: { full_name: 'testuser/test-repo' },
        sender: { login: 'testuser' },
        head_commit: { id: SecureRandom.hex(20), message: 'Test commit' }
      }
    end
    headers do
      {
        'X-GitHub-Event' => 'push',
        'X-GitHub-Delivery' => delivery_id,
        'Content-Type' => 'application/json'
      }
    end
    sender_username { 'testuser' }
    ref { 'refs/heads/main' }
    sha { SecureRandom.hex(20) }
    error_message { nil }
    retry_count { 0 }
    processed_at { nil }
    processing_result { {} }

    trait :push do
      event_type { 'push' }
      action { nil }
    end

    trait :pull_request do
      event_type { 'pull_request' }
      action { 'opened' }
      payload do
        {
          action: 'opened',
          pull_request: {
            number: 1,
            title: 'Test PR',
            user: { login: 'testuser' }
          },
          repository: { full_name: 'testuser/test-repo' }
        }
      end
    end

    trait :workflow_run do
      event_type { 'workflow_run' }
      action { 'completed' }
      payload do
        {
          action: 'completed',
          workflow_run: {
            id: 12345,
            name: 'CI',
            status: 'completed',
            conclusion: 'success'
          },
          repository: { full_name: 'testuser/test-repo' }
        }
      end
    end

    trait :pending do
      status { 'pending' }
      processed_at { nil }
    end

    trait :processing do
      status { 'processing' }
      processed_at { nil }
    end

    trait :processed do
      status { 'processed' }
      processed_at { Time.current }
      processing_result { { success: true } }
    end

    trait :failed do
      status { 'failed' }
      processed_at { Time.current }
      error_message { 'Processing failed: connection timeout' }
      retry_count { 1 }
    end

    trait :retrying do
      status { 'failed' }
      retry_count { 1 }
      error_message { 'Temporary failure, retrying' }
    end

    trait :max_retries do
      status { 'failed' }
      retry_count { 3 }
      error_message { 'Max retries reached' }
    end
  end
end
