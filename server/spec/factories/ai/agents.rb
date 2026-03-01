# frozen_string_literal: true

FactoryBot.define do
  factory :ai_agent, class: "Ai::Agent" do
    account
    association :provider, factory: :ai_provider
    creator { association :user, account: account }
    sequence(:name) { |n| "#{Faker::App.name} #{n}" }
    description { Faker::Lorem.paragraph }
    agent_type { 'assistant' }
    mcp_tool_manifest do
      {
        'name' => 'assistant_tool',
        'description' => 'AI assistant for text generation and conversation',
        'type' => 'assistant',
        'version' => '1.0.0'
      }
    end
    status { 'active' }

    # Transient attributes that don't map to database columns
    transient do
      configuration do
        {
          instructions: 'You are a helpful assistant.',
          model: 'gpt-3.5-turbo',
          temperature: 0.7,
          max_tokens: 1000,
          system_prompt: 'You are a helpful assistant.'
        }
      end
    end
    version { '1.0.0' }  # Add semantic version for MCP compatibility
    metadata do
      {
        created_by: 'system',
        version: '1.0',
        capabilities: [ 'text_generation', 'conversation' ]
      }
    end

    trait :inactive do
      status { 'inactive' }
    end

    trait :with_executions do
      after(:create) do |agent|
        create_list(:ai_agent_execution, 3, agent: agent, account: agent.account)
      end
    end

    trait :code_assistant do
      agent_type { 'code_assistant' }
      transient do
        configuration do
          {
            model: 'claude-3-sonnet',
            temperature: 0.2,
            max_tokens: 4000,
            system_prompt: 'You are an expert programmer.'
          }
        end
      end
    end

    trait :data_analyst do
      agent_type { 'data_analyst' }
      transient do
        configuration do
          {
            model: 'gpt-4',
            temperature: 0.1,
            max_tokens: 2000,
            instructions: 'You are a data analysis expert who helps with data processing and insights.',
            system_prompt: 'You are a data analysis expert.'
          }
        end
      end
    end

    trait :mcp_client do
      agent_type { 'mcp_client' }
      sequence(:name) { |n| "Claude Code ##{n}" }
      description { 'Auto-created identity for Claude Code MCP session' }
    end

    trait :archived do
      status { 'archived' }
    end

    trait :monitor do
      agent_type { 'monitor' }
    end

    trait :content_generator do
      agent_type { 'content_generator' }
    end

    trait :workflow_operations do
      agent_type { 'workflow_operations' }
    end
  end
end
