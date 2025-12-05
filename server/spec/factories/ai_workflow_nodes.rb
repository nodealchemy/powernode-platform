# frozen_string_literal: true

FactoryBot.define do
  factory :ai_workflow_node do
    ai_workflow
    node_id { SecureRandom.uuid }
    name { Faker::App.name + " Node" }
    node_type { 'ai_agent' }
    position do
      {
        x: rand(100..800),
        y: rand(100..600)
      }
    end
    configuration do
      case node_type
      when 'ai_agent'
        {
          provider_id: SecureRandom.uuid,
          model: 'gpt-3.5-turbo',
          temperature: 0.7,
          max_tokens: 1000,
          system_prompt: 'You are a helpful assistant.'
        }
      when 'api_call'
        {
          method: 'POST',
          url: 'https://api.example.com/endpoint',
          headers: { 'Content-Type': 'application/json' },
          timeout: 30
        }
      when 'webhook'
        {
          url: 'https://webhook.example.com/notify',
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          signature_secret: 'webhook_secret_key'
        }
      when 'condition'
        {
          expression: 'input.status == "success"',
          true_path: 'continue',
          false_path: 'error_handler'
        }
      when 'loop'
        {
          array_path: 'input.items',
          max_iterations: 100,
          break_condition: 'current.processed == true'
        }
      when 'transform'
        {
          script: 'output.result = input.data.toUpperCase();',
          language: 'javascript'
        }
      when 'delay'
        {
          duration: 5,
          unit: 'seconds'
        }
      when 'human_approval'
        {
          timeout: 3600,
          notification_channels: ['email', 'slack'],
          required_approvers: 1
        }
      when 'sub_workflow'
        {
          workflow_id: SecureRandom.uuid,
          input_mapping: { 'parent.data': 'child.input' }
        }
      when 'merge'
        {
          strategy: 'merge_objects',
          conflict_resolution: 'last_wins'
        }
      when 'split'
        {
          strategy: 'array_split',
          batch_size: 10
        }
      else
        {}
      end
    end
    metadata do
      {
        description: "#{node_type} node for workflow processing",
        version: '1.0',
        category: node_type.split('_').first
      }
    end

    # After build callback to ensure ai_agent nodes have agent_id before validation
    after(:build) do |node, evaluator|
      if node.node_type == 'ai_agent'
        # Only create agent if one doesn't exist and if node configuration needs it
        if node.configuration['agent_id'].blank? || !node.ai_workflow.account.ai_agents.exists?(id: node.configuration['agent_id'])
          # Create minimal agent for this workflow's account - let factory generate unique name
          agent = create(:ai_agent, account: node.ai_workflow.account)
          node.configuration = node.configuration.merge('agent_id' => agent.id)
        end
      end
    end

    trait :start_node do
      node_type { 'start' }
      name { 'Start' }
      is_start_node { true }
      configuration { { node_type: 'start' } }
      position { { x: 100, y: 300 } }
    end

    trait :end_node do
      node_type { 'end' }
      name { 'End' }
      is_end_node { true }
      configuration { { node_type: 'end' } }
      position { { x: 800, y: 300 } }
    end

    trait :trigger do
      node_type { 'trigger' }
      name { 'Workflow Trigger' }
      configuration do
        {
          trigger_type: 'manual',
          enabled: true
        }
      end
      position { { x: 50, y: 300 } }
    end

    trait :action do
      node_type { 'data_processor' }  # action is not a valid node_type, use data_processor instead
      name { 'Data Processor Node' }
      configuration do
        {
          operation: 'transform',
          timeout: 30
        }
      end
      position { { x: 400, y: 300 } }
    end

    trait :ai_agent do
      node_type { 'ai_agent' }
      name { 'AI Assistant' }
      # Configuration will be set by after(:build) callback with real agent
    end

    trait :api_call do
      node_type { 'api_call' }
      name { 'API Request' }
      configuration do
        {
          method: 'GET',
          url: 'https://jsonplaceholder.typicode.com/posts/1',
          headers: {
            'Accept': 'application/json',
            'User-Agent': 'AI-Workflow-Bot/1.0'
          },
          timeout: 30,
          retry_count: 3,
          retry_delay: 1
        }
      end
    end

    trait :webhook do
      node_type { 'webhook' }
      name { 'Send Webhook' }
      configuration do
        {
          url: 'https://webhook.site/test-endpoint',
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-Workflow-Source': 'powernode'
          },
          payload_template: '{"event": "workflow_completed", "data": "{{input}}"}',
          signature_secret: 'test_webhook_secret',
          timeout: 15
        }
      end
    end

    trait :condition do
      node_type { 'condition' }
      name { 'Decision Point' }
      configuration do
        {
          conditions: [
            {
              field: 'input.score',
              operator: '>',
              value: 0.8,
              data_type: 'number'
            }
          ],
          logic_operator: 'AND',
          default_path: 'false',
          expression: 'input.score > 0.8',
          true_path: 'high_quality',
          false_path: 'needs_review'
        }
      end
    end

    trait :loop do
      node_type { 'loop' }
      name { 'Process Items' }
      configuration do
        {
          iteration_source: 'input.items',
          max_iterations: 50,
          break_condition: 'current.error != null',
          item_variable: 'current_item',
          index_variable: 'item_index'
        }
      end
    end

    trait :transform do
      node_type { 'transform' }
      name { 'Data Transform' }
      configuration do
        {
          script: "const result = {}; result.processed_text = input.text.toUpperCase(); result.word_count = input.text.split(' ').length; result.timestamp = new Date().toISOString(); output = result;",
          language: 'javascript',
          timeout: 10
        }
      end
    end

    trait :delay do
      node_type { 'delay' }
      name { 'Wait Period' }
      configuration do
        {
          duration: 30,
          unit: 'seconds',
          variable_delay: false
        }
      end
    end

    trait :human_approval do
      node_type { 'human_approval' }
      name { 'Review Required' }
      configuration do
        {
          timeout: 7200,
          notification_channels: ['email', 'webhook'],
          required_approvers: 2,
          approval_message: 'Please review the workflow output',
          auto_approve_after: 24 * 3600
        }
      end
    end

    trait :sub_workflow do
      node_type { 'sub_workflow' }
      name { 'Sub Process' }
      configuration do
        {
          workflow_id: SecureRandom.uuid,
          input_mapping: {
            'parent.data': 'child.input_data',
            'parent.context': 'child.context'
          },
          output_mapping: {
            'child.result': 'parent.sub_result'
          },
          timeout: 3600
        }
      end
    end

    trait :merge do
      node_type { 'merge' }
      name { 'Merge Results' }
      configuration do
        {
          strategy: 'deep_merge',
          conflict_resolution: 'prefer_first',
          merge_arrays: true,
          flatten_result: false
        }
      end
    end

    trait :split do
      node_type { 'split' }
      name { 'Split Data' }
      configuration do
        {
          strategy: 'chunk_array',
          batch_size: 5,
          preserve_order: true,
          parallel_execution: true
        }
      end
    end

    trait :error_handler do
      node_type { 'error_handler' }
      name { 'Error Handler' }
      configuration do
        {
          error_types: ['timeout', 'api_error', 'validation_error'],
          actions: {
            'timeout': 'retry',
            'api_error': 'fallback',
            'validation_error': 'terminate'
          },
          max_retries: 3,
          fallback_workflow_id: nil
        }
      end
    end

    trait :ollama_agent do
      node_type { 'ai_agent' }
      name { 'Ollama Assistant' }
      configuration do
        {
          provider_id: SecureRandom.uuid,
          model: 'llama3.1:8b',
          temperature: 0.1,
          max_tokens: 4000,
          system_prompt: 'You are a coding assistant specialized in Ruby and Rails.',
          stream: false
        }
      end
    end

    trait :blog_writer do
      node_type { 'ai_agent' }
      name { 'Blog Writer' }
      configuration do
        {
          provider_id: SecureRandom.uuid,
          model: 'gpt-4',
          temperature: 0.8,
          max_tokens: 3000,
          system_prompt: 'You are a professional blog writer. Create engaging, well-structured blog posts based on the given topic and outline.',
          response_format: 'markdown'
        }
      end
    end

    trait :content_reviewer do
      node_type { 'ai_agent' }
      name { 'Content Reviewer' }
      configuration do
        {
          provider_id: SecureRandom.uuid,
          model: 'claude-3-sonnet',
          temperature: 0.3,
          max_tokens: 2000,
          system_prompt: 'You are a content editor. Review the provided content for quality, grammar, and coherence. Provide improvement suggestions.'
        }
      end
    end

    trait :with_error_config do
      configuration do
        base_config = attributes_for(:ai_workflow_node, node_type: node_type)[:configuration]
        base_config.merge(
          error_handling: {
            on_error: 'continue',
            max_retries: 2,
            retry_delay: 5,
            fallback_action: 'skip'
          }
        )
      end
    end
  end
end