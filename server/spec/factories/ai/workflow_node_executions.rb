# frozen_string_literal: true

FactoryBot.define do
  factory :ai_workflow_node_execution, class: "Ai::WorkflowNodeExecution" do
    transient do
      skip_node_creation { false }
    end

    association :workflow_run, factory: :ai_workflow_run

    execution_id { SecureRandom.uuid }
    status { 'pending' }
    retry_count { 0 }
    max_retries { 3 }
    cost { 0.0 }
    output_data { {} }

    after(:build) do |execution, evaluator|
      # Check if node was provided via ai_workflow_node_id or if we need to create one
      node = nil

      # First check if ai_workflow_node_id was set
      if execution.ai_workflow_node_id.present?
        node = Ai::WorkflowNode.find_by(id: execution.ai_workflow_node_id)
      end

      # If no node found and we shouldn't skip creation, create a default node
      if node.nil? && !evaluator.skip_node_creation
        wf = execution.workflow_run&.workflow
        if wf.present?
          node = create(:ai_workflow_node, workflow: wf)
        else
          node = create(:ai_workflow_node)
        end
        execution.ai_workflow_node_id = node.id
      end

      if node.present?
        execution.node_id ||= node.node_id
        execution.node_type ||= node.node_type
      else
        # Provide defaults if node is not set
        execution.node_id ||= SecureRandom.uuid
        execution.node_type ||= 'ai_agent'
      end

      if execution.input_data.blank? && execution.workflow_run.present?
        execution.input_data = {
          previous_output: 'Input from previous node',
          workflow_variables: execution.workflow_run.input_variables || {},
          execution_context: {
            run_id: execution.workflow_run&.run_id,
            node_position: 1
          }
        }
      end

      if execution.metadata.blank?
        execution.metadata = {
          node_type: execution.node_type,
          execution_order: 1
        }
      end
    end

    trait :running do
      status { 'running' }
      started_at { 2.minutes.ago }
    end

    trait :completed do
      status { 'completed' }
      started_at { 5.minutes.ago }
      completed_at { 2.minutes.ago }
      duration_ms { 180_000 }
      cost { 0.008 }
      output_data do
        {
          result: 'Node executed successfully',
          processed_data: 'Transformed input data',
          metrics: {
            tokens_used: 250,
            processing_time: 180_000,
            success: true
          }
        }
      end
    end

    trait :failed do
      status { 'failed' }
      started_at { 8.minutes.ago }
      completed_at { 5.minutes.ago }
      duration_ms { 180_000 }
      cost { 0.003 }
      error_details do
        {
          error_type: 'execution_timeout',
          error_message: 'Node execution exceeded timeout limit',
          error_code: 'TIMEOUT_ERROR',
          retry_count: 2,
          timestamp: Time.current.iso8601
        }
      end
    end

    trait :skipped do
      status { 'skipped' }
      started_at { 3.minutes.ago }
      completed_at { 3.minutes.ago }
      duration_ms { 100 }
      metadata do
        {
          skip_reason: 'conditional_not_met',
          condition_result: false,
          condition_expression: 'input.status == "ready"'
        }
      end
    end

    trait :ai_agent_execution do
      node { create(:ai_workflow_node, :ai_agent, workflow: workflow_run.workflow) }
      input_data do
        {
          prompt: 'Generate a summary of this data',
          context: 'User data analysis request',
          model_config: {
            temperature: 0.7,
            max_tokens: 1000
          }
        }
      end
      output_data do
        {
          ai_response: 'Here is a comprehensive summary of the provided data...',
          tokens_used: 847,
          model_used: 'gpt-4',
          response_time: 2.3,
          confidence_score: 0.92
        }
      end
      cost { 0.0124 }
    end

    trait :api_call_execution do
      node { create(:ai_workflow_node, :api_call, workflow: workflow_run.workflow) }
      input_data do
        {
          url: 'https://api.example.com/data',
          method: 'GET',
          headers: { 'Authorization': 'Bearer token123' },
          timeout: 30
        }
      end
      output_data do
        {
          response_body: { data: 'API response data', status: 'success' },
          status_code: 200,
          response_headers: {
            'content-type': 'application/json',
            'x-rate-limit-remaining': '999'
          },
          response_time: 450
        }
      end
      cost { 0.001 }
    end

    trait :webhook_execution do
      node { create(:ai_workflow_node, :webhook, workflow: workflow_run.workflow) }
      input_data do
        {
          url: 'https://webhook.example.com/notify',
          payload: { event: 'workflow_step_completed', data: 'step results' },
          headers: { 'Content-Type': 'application/json' },
          signature_secret: 'webhook_secret'
        }
      end
      output_data do
        {
          webhook_response: { received: true, id: 'webhook_123' },
          status_code: 200,
          delivery_time: 1.2,
          signature_verified: true
        }
      end
      cost { 0.0005 }
    end

    trait :condition_execution do
      node { create(:ai_workflow_node, :condition, workflow: workflow_run.workflow) }
      input_data do
        {
          condition_expression: 'input.score > 0.8',
          input_values: { score: 0.95, confidence: 0.87 },
          data_type: 'number'
        }
      end
      output_data do
        {
          condition_result: true,
          evaluation_details: {
            expression: 'input.score > 0.8',
            actual_value: 0.95,
            threshold: 0.8,
            comparison: 'greater_than'
          },
          next_path: 'success_branch'
        }
      end
      cost { 0.0001 }
    end

    trait :transform_execution do
      node { create(:ai_workflow_node, :transform, workflow: workflow_run.workflow) }
      input_data do
        {
          script: 'output.upper_text = input.text.toUpperCase(); output.word_count = input.text.split(" ").length;',
          input_values: { text: 'hello world example' }
        }
      end
      output_data do
        {
          transformed_data: {
            upper_text: 'HELLO WORLD EXAMPLE',
            word_count: 3,
            original_text: 'hello world example'
          },
          script_execution_time: 15,
          transformation_success: true
        }
      end
      cost { 0.0002 }
    end

    trait :delay_execution do
      node { create(:ai_workflow_node, :delay, workflow: workflow_run.workflow) }
      input_data do
        {
          delay_duration: 30,
          delay_unit: 'seconds',
          start_time: 30.seconds.ago.iso8601
        }
      end
      output_data do
        {
          delay_completed: true,
          actual_delay: 30.2,
          scheduled_resume: Time.current.iso8601
        }
      end
      duration_ms { 30_200 }
      cost { 0.0 }
    end

    trait :human_approval_execution do
      node { create(:ai_workflow_node, :human_approval, workflow: workflow_run.workflow) }
      status { 'waiting_approval' }
      input_data do
        {
          approval_request: 'Please review the generated content',
          content_to_review: 'Generated blog post content...',
          required_approvers: 1,
          timeout: 3600
        }
      end
      output_data do
        {
          approval_status: 'pending',
          approval_url: "https://app.example.com/approvals/#{SecureRandom.uuid}",
          notification_sent: true,
          expires_at: 1.hour.from_now.iso8601
        }
      end
    end

    trait :loop_execution do
      node { create(:ai_workflow_node, :loop, workflow: workflow_run.workflow) }
      input_data do
        {
          array_data: [ 1, 2, 3, 4, 5 ],
          current_iteration: 3,
          max_iterations: 10,
          item_variable: 'current_item'
        }
      end
      output_data do
        {
          processed_items: [ 1, 2, 3 ],
          current_item: 3,
          remaining_items: [ 4, 5 ],
          loop_status: 'continuing',
          iteration_results: [
            { item: 1, processed: true, result: 'success' },
            { item: 2, processed: true, result: 'success' },
            { item: 3, processed: true, result: 'success' }
          ]
        }
      end
    end

    trait :sub_workflow_execution do
      node { create(:ai_workflow_node, :sub_workflow, workflow: workflow_run.workflow) }
      input_data do
        {
          sub_workflow_id: create(:ai_workflow).id,
          input_mapping: { 'parent.data': 'child.input' },
          sub_workflow_input: { data: 'test data for sub workflow' }
        }
      end
      output_data do
        {
          sub_workflow_run_id: SecureRandom.uuid,
          sub_workflow_status: 'completed',
          sub_workflow_result: { processed_data: 'result from sub workflow' },
          execution_time: 120_000
        }
      end
      cost { 0.045 }
    end

    trait :with_retries do
      metadata do
        {
          retry_history: [
            {
              attempt: 1,
              started_at: 10.minutes.ago.iso8601,
              error: 'Temporary API failure',
              duration: 5000
            },
            {
              attempt: 2,
              started_at: 8.minutes.ago.iso8601,
              error: 'Rate limit exceeded',
              duration: 3000
            }
          ],
          current_attempt: 3,
          max_retries: 3
        }
      end
    end

    trait :high_cost do
      cost { 0.125 }
      output_data do
        {
          cost_breakdown: {
            base_cost: 0.075,
            usage_multiplier: 1.5,
            premium_features: 0.025,
            total_tokens: 5000
          }
        }
      end
    end

    trait :performance_metrics do
      output_data do
        {
          performance: {
            cpu_time: 150,
            memory_usage: 45_600_000,
            network_calls: 3,
            cache_hits: 2,
            cache_misses: 1
          }
        }
      end
    end

    # Realistic blog generation node execution
    trait :blog_content_generation do
      node { create(:ai_workflow_node, :blog_writer, workflow: workflow_run.workflow) }
      input_data do
        {
          topic: 'Advanced Rails Testing Strategies',
          target_length: 1200,
          audience: 'intermediate developers',
          include_code_examples: true
        }
      end
      output_data do
        {
          generated_content: '# Advanced Rails Testing Strategies\n\nTesting is crucial...',
          word_count: 1247,
          code_examples_included: 3,
          readability_score: 78.5,
          estimated_reading_time: '5 minutes'
        }
      end
      cost { 0.0456 }
      duration_ms { 12_400 }
    end

    trait :content_quality_check do
      node { create(:ai_workflow_node, :content_reviewer, workflow: workflow_run.workflow) }
      input_data do
        {
          content_to_review: 'Blog post content to be reviewed...',
          quality_criteria: [ 'grammar', 'coherence', 'technical_accuracy' ],
          target_score: 85
        }
      end
      output_data do
        {
          quality_score: 89.2,
          grammar_score: 92.1,
          coherence_score: 87.8,
          technical_accuracy: 88.5,
          suggestions: [
            'Consider adding more specific examples',
            'Clarify the second paragraph'
          ],
          approved: true
        }
      end
      cost { 0.0234 }
    end
  end
end
