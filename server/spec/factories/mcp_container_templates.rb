# frozen_string_literal: true

FactoryBot.define do
  factory :mcp_container_template, class: 'Mcp::ContainerTemplate' do
    account
    sequence(:name) { |n| "Container Template #{n}" }
    description { 'A test container template for AI agent execution' }
    image_name { 'powernode/ai-agent' }
    image_tag { 'latest' }
    visibility { 'private' }
    status { 'active' }
    execution_count { 0 }
    success_count { 0 }
    environment_variables do
      {
        'LOG_LEVEL' => 'info',
        'NODE_ENV' => 'production'
      }
    end
    resource_limits do
      {
        'memory_mb' => 512,
        'cpu_millicores' => 500,
        'storage_mb' => 1024,
        'timeout_seconds' => 3600
      }
    end
    security_options do
      {
        'read_only_root' => true,
        'no_new_privileges' => true,
        'drop_capabilities' => [ 'ALL' ]
      }
    end
    labels { { 'runner' => 'powernode-ai-agent' } }

    trait :private do
      visibility { 'private' }
    end

    trait :account_visible do
      visibility { 'account' }
    end

    trait :public do
      visibility { 'public' }
    end

    trait :active do
      status { 'active' }
    end

    trait :deprecated do
      status { 'deprecated' }
    end

    trait :archived do
      status { 'archived' }
    end

    trait :with_vault_secrets do
      vault_secret_paths do
        [
          'secret/data/powernode/ai-providers/openai',
          'secret/data/powernode/ai-providers/anthropic'
        ]
      end
    end

    trait :high_resource do
      resource_limits do
        {
          'memory_mb' => 2048,
          'cpu_millicores' => 2000,
          'storage_mb' => 4096,
          'timeout_seconds' => 7200
        }
      end
    end

    trait :gpu_enabled do
      labels { { 'runner' => 'powernode-gpu' } }
      resource_limits do
        {
          'memory_mb' => 8192,
          'cpu_millicores' => 4000,
          'storage_mb' => 10240,
          'timeout_seconds' => 14400,
          'gpu' => true
        }
      end
    end

    trait :with_executions do
      execution_count { 10 }
      success_count { 8 }
    end
  end
end
