# frozen_string_literal: true

FactoryBot.define do
  factory :ai_agent_execution, class: "Ai::AgentExecution" do
    account
    association :agent, factory: :ai_agent
    user { agent&.creator }
    association :provider, factory: :ai_provider
    execution_id { SecureRandom.uuid }
    input_parameters do
      {
        prompt: Faker::Lorem.paragraph,
        parameters: { temperature: 0.7, max_tokens: 1000 }
      }
    end
    status { 'pending' }
    started_at { nil }
    completed_at { nil }
    output_data { {} }

    trait :running do
      status { 'running' }
      started_at { 5.minutes.ago }
    end

    trait :completed do
      status { 'completed' }
      started_at { 10.minutes.ago }
      completed_at { 2.minutes.ago }
      duration_ms { 480000 }
      output_data do
        {
          output: Faker::Lorem.paragraph,
          metrics: {
            tokens_used: 450,
            response_time_ms: 2500,
            cost_estimate: 0.009
          },
          artifacts: []
        }
      end
    end

    trait :failed do
      status { 'failed' }
      started_at { 15.minutes.ago }
      completed_at { 10.minutes.ago }
      error_message { 'Provider timeout occurred during execution' }
      output_data do
        {
          error: 'Provider timeout',
          error_details: {
            provider: 'openai',
            http_code: 504,
            message: 'Gateway timeout'
          }
        }
      end
    end

    trait :cancelled do
      status { 'cancelled' }
      started_at { 20.minutes.ago }
      completed_at { 15.minutes.ago }
      output_data do
        {
          cancelled: true,
          cancelled_by: SecureRandom.uuid,
          reason: 'User requested cancellation'
        }
      end
    end

    trait :with_artifacts do
      status { 'completed' }
      started_at { 10.minutes.ago }
      completed_at { 2.minutes.ago }
      output_data do
        {
          output: Faker::Lorem.paragraph,
          metrics: {
            tokens_used: 750,
            response_time_ms: 4200,
            cost_estimate: 0.015
          },
          artifacts: [
            {
              name: 'generated_code.py',
              type: 'code',
              size: 2048,
              url: 'https://example.com/artifacts/code.py',
              metadata: { language: 'python' }
            },
            {
              name: 'analysis_report.md',
              type: 'document',
              size: 4096,
              url: 'https://example.com/artifacts/report.md',
              metadata: { format: 'markdown' }
            }
          ]
        }
      end
    end

    trait :high_priority do
      execution_context do
        {
          priority: 'high',
          retry_count: 0,
          created_by: 'user',
          urgent: true
        }
      end
    end

    # Alias traits for test compatibility - use valid statuses
    trait :queued do
      # queued is not a valid status, use pending instead
      status { 'pending' }
      started_at { nil }
      completed_at { nil }
    end

    trait :processing do
      # processing is not a valid status, use running instead
      status { 'running' }
      started_at { 3.minutes.ago }
      completed_at { nil }
    end

    trait :pending do
      status { 'pending' }
      started_at { nil }
      completed_at { nil }
    end
  end
end
