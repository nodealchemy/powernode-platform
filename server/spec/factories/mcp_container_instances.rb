# frozen_string_literal: true

FactoryBot.define do
  factory :mcp_container_instance, class: 'Mcp::ContainerInstance' do
    account
    association :template, factory: :mcp_container_template
    status { 'pending' }
    sequence(:workflow_run_id) { |n| n * 1000 }
    input_parameters do
      {
        'task' => 'analyze_code',
        'repository' => 'example/repo'
      }
    end
    output_data { {} }
    execution_logs { '' }
    resource_usage { {} }
    started_at { nil }
    completed_at { nil }

    trait :pending do
      status { 'pending' }
      started_at { nil }
    end

    trait :provisioning do
      status { 'provisioning' }
      started_at { Time.current }
    end

    trait :running do
      status { 'running' }
      started_at { 5.minutes.ago }
      runner_name { 'runner-001' }
    end

    trait :completed do
      status { 'completed' }
      started_at { 10.minutes.ago }
      completed_at { Time.current }
      output_data do
        {
          'result' => 'success',
          'artifacts' => [ 'output.json' ]
        }
      end
      resource_usage do
        {
          'peak_memory_mb' => 256,
          'cpu_seconds' => 120,
          'network_bytes' => 1024
        }
      end
    end

    trait :failed do
      status { 'failed' }
      started_at { 10.minutes.ago }
      completed_at { Time.current }
      execution_logs { "Error: Task execution failed\nStack trace: ..." }
    end

    trait :cancelled do
      status { 'cancelled' }
      started_at { 5.minutes.ago }
      completed_at { Time.current }
    end

    trait :timeout do
      status { 'timeout' }
      started_at { 2.hours.ago }
      completed_at { Time.current }
    end

    trait :with_vault_token do
      vault_token_id { SecureRandom.uuid }
    end

    trait :with_a2a_task do
      association :a2a_task, factory: :ai_a2a_task
    end

    trait :with_logs do
      execution_logs do
        <<~LOGS
          [2024-01-15 10:00:00] Starting container execution
          [2024-01-15 10:00:01] Loading configuration
          [2024-01-15 10:00:02] Executing task: analyze_code
          [2024-01-15 10:05:00] Task completed successfully
        LOGS
      end
    end

    trait :security_violation do
      security_violations do
        [
          {
            'type' => 'network_access',
            'details' => 'Attempted to connect to blocked domain',
            'timestamp' => Time.current.iso8601
          }
        ]
      end
    end
  end
end
