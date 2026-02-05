# frozen_string_literal: true

FactoryBot.define do
  factory :devops_container_instance, class: 'Devops::ContainerInstance' do
    account
    association :template, factory: :devops_container_template
    status { 'pending' }
    sequence(:execution_id) { |n| "exec-#{SecureRandom.hex(8)}-#{n}" }
    image_name { 'powernode/ai-agent' }
    input_parameters do
      {
        'task' => 'analyze_code',
        'repository' => 'example/repo'
      }
    end
    output_data { {} }
    logs { '' }
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
      duration_ms { 600_000 }  # 10 minutes in milliseconds
      output_data do
        {
          'result' => 'success',
          'artifacts' => [ 'output.json' ]
        }
      end
      memory_used_mb { 256 }
      cpu_used_millicores { 500.0 }
      network_bytes_in { 512 }
      network_bytes_out { 512 }
    end

    trait :failed do
      status { 'failed' }
      started_at { 10.minutes.ago }
      completed_at { Time.current }
      logs { "Error: Task execution failed\nStack trace: ..." }
      error_message { "Task execution failed" }
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
      logs do
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
