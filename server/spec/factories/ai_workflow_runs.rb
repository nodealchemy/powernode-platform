# frozen_string_literal: true

FactoryBot.define do
  factory :ai_workflow_run do
    ai_workflow
    account { ai_workflow.account }
    run_id { SecureRandom.uuid }
    status { 'initializing' }
    trigger_type { 'manual' }
    input_variables do
      {
        user_input: 'Test input data',
        session_id: SecureRandom.uuid,
        timestamp: Time.current.iso8601
      }
    end
    output_variables { {} }
    runtime_context do
      {
        user_id: SecureRandom.uuid,
        source: 'test_suite',
        environment: 'test'
      }
    end
    metadata do
      {
        test_run: true,
        created_via: 'factory_bot'
      }
    end

    # Automatically set timestamps and required fields based on status
    # Using after(:build) to set values before validation
    after(:build) do |run|
      case run.status
      when 'running'
        run.started_at ||= 5.minutes.ago
      when 'completed'
        run.started_at ||= 10.minutes.ago
        run.completed_at ||= 2.minutes.ago
      when 'failed'
        run.started_at ||= 15.minutes.ago
        run.completed_at ||= 10.minutes.ago
        # Always set error_details for failed runs if not explicitly provided
        run.error_details = {
          error_type: 'execution_error',
          error_message: 'Test error',
          failed_node_id: SecureRandom.uuid
        } if run.error_details.blank? || run.error_details == {}
      when 'cancelled'
        run.started_at ||= 8.minutes.ago
        run.completed_at ||= 3.minutes.ago
        run.cancelled_at ||= 3.minutes.ago
        # Always set error_details for cancelled runs if not explicitly provided
        run.error_details = {
          cancellation_reason: 'test_cancellation',
          cancelled_by: SecureRandom.uuid
        } if run.error_details.blank? || run.error_details == {}
      end
    end

    trait :running do
      status { 'running' }
      started_at { 5.minutes.ago }
      runtime_context do
        {
          user_id: SecureRandom.uuid,
          current_node_id: SecureRandom.uuid,
          nodes_completed: 1,
          nodes_total: 3
        }
      end
    end

    trait :completed do
      status { 'completed' }
      started_at { 10.minutes.ago }
      completed_at { 2.minutes.ago }
      duration_ms { 480_000 }
      total_cost { 0.025 }
      output_variables do
        {
          result: 'Workflow completed successfully',
          final_output: 'Generated content here',
          metrics: {
            nodes_executed: 5,
            success_rate: 100.0,
            total_tokens: 1500
          }
        }
      end
      runtime_context do
        {
          user_id: SecureRandom.uuid,
          nodes_completed: 5,
          nodes_total: 5,
          final_node_id: SecureRandom.uuid
        }
      end
    end

    trait :failed do
      status { 'failed' }
      started_at { 15.minutes.ago }
      completed_at { 10.minutes.ago }
      duration_ms { 300_000 }
      total_cost { 0.012 }
      error_details do
        {
          error_type: 'node_execution_error',
          error_message: 'AI provider timeout',
          failed_node_id: SecureRandom.uuid,
          stack_trace: 'Error occurred at node execution',
          retry_count: 3
        }
      end
    end

    trait :cancelled do
      status { 'cancelled' }
      started_at { 8.minutes.ago }
      completed_at { 3.minutes.ago }
      cancelled_at { 3.minutes.ago }
      duration_ms { 300_000 }
      total_cost { 0.008 }
      error_details do
        {
          cancellation_reason: 'user_requested',
          cancelled_by: SecureRandom.uuid,
          cancelled_at_node: SecureRandom.uuid
        }
      end
    end

    trait :waiting_approval do
      status { 'waiting_approval' }
      started_at { 20.minutes.ago }
      duration_ms { 600_000 }
      total_cost { 0.015 }
      metadata do
        {
          approval_requested_at: 10.minutes.ago.iso8601,
          approval_message: 'Human approval required for this workflow step',
          approval_node_id: SecureRandom.uuid,
          user_id: SecureRandom.uuid
        }
      end
    end

    trait :scheduled do
      trigger_type { 'schedule' }
      trigger_context do
        {
          schedule_id: SecureRandom.uuid,
          scheduled_time: Time.current.iso8601,
          cron_expression: '0 9 * * *'
        }
      end
    end

    trait :webhook_triggered do
      trigger_type { 'webhook' }
      input_variables do
        {
          webhook_data: {
            event: 'user_signup',
            user_id: 12345,
            email: 'test@example.com'
          },
          headers: {
            'X-Webhook-Source': 'github',
            'X-Signature': 'sha256=test_signature'
          }
        }
      end
      trigger_context do
        {
          webhook_id: SecureRandom.uuid,
          source_ip: '192.168.1.1',
          user_agent: 'GitHub-Hookshot/abc123'
        }
      end
    end

    trait :event_triggered do
      trigger_type { 'event' }
      trigger_context do
        {
          event_type: 'workflow.completed',
          source_workflow_id: SecureRandom.uuid,
          event_data: {
            result: 'success',
            output: 'Previous workflow completed'
          }
        }
      end
    end

    trait :api_triggered do
      trigger_type { 'api' }
      trigger_context do
        {
          api_endpoint: '/api/v1/workflows/execute',
          request_id: SecureRandom.uuid,
          client_id: 'test_client'
        }
      end
    end

    trait :with_node_executions do
      after(:create) do |run|
        workflow_nodes = run.ai_workflow.nodes.limit(3)
        workflow_nodes.each_with_index do |node, index|
          status = case index
                   when 0 then 'completed'
                   when 1 then 'running'
                   else 'pending'
                   end
          
          create(:ai_workflow_node_execution,
                 ai_workflow_run: run,
                 ai_workflow_node: node,
                 status: status,
                 account: run.account)
        end
      end
    end

    trait :high_cost do
      total_cost { 5.75 }
      output_variables do
        {
          cost_breakdown: {
            ai_agent_costs: 4.25,
            api_call_costs: 1.50,
            total_tokens: 50_000,
            execution_time: 1800
          }
        }
      end
    end

    trait :fast_execution do
      duration_ms { 30_000 }
      output_variables do
        {
          performance_metrics: {
            nodes_per_second: 2.5,
            average_node_time: 6000,
            cache_hit_rate: 85.0
          }
        }
      end
    end

    trait :slow_execution do
      duration_ms { 1_800_000 }
      output_variables do
        {
          performance_metrics: {
            nodes_per_second: 0.1,
            average_node_time: 360_000,
            bottleneck_nodes: ['ai_agent_node_1', 'api_call_node_3']
          }
        }
      end
    end

    trait :blog_generation_run do
      input_variables do
        {
          blog_topic: 'The Future of AI in Web Development',
          target_audience: 'developers',
          word_count: 1500,
          tone: 'professional',
          include_examples: true
        }
      end
      output_variables do
        {
          generated_content: '# The Future of AI in Web Development\n\nAI is transforming...',
          word_count: 1567,
          readability_score: 85.2,
          seo_score: 92.1,
          topics_covered: ['machine learning', 'automation', 'developer tools']
        }
      end
      metadata do
        {
          content_type: 'blog_post',
          quality_score: 4.2,
          generation_model: 'gpt-4'
        }
      end
    end

    trait :data_processing_run do
      input_variables do
        {
          data_source: 'customer_orders.csv',
          processing_rules: {
            filter_date_range: '2024-01-01 to 2024-12-31',
            group_by: 'customer_id',
            calculate: ['total_amount', 'order_count']
          }
        }
      end
      output_variables do
        {
          processed_records: 15_420,
          total_revenue: 456_789.50,
          unique_customers: 3_245,
          summary_report: 'data/processed_summary_2024.json'
        }
      end
    end

    trait :with_retry_history do
      metadata do
        {
          retry_history: [
            {
              attempt: 1,
              failed_at: 2.hours.ago.iso8601,
              error: 'API timeout',
              node_id: SecureRandom.uuid
            },
            {
              attempt: 2,
              failed_at: 1.hour.ago.iso8601,
              error: 'Rate limit exceeded',
              node_id: SecureRandom.uuid
            }
          ],
          current_attempt: 3
        }
      end
    end

    trait :with_execution_logs do
      after(:create) do |run|
        create_list(:ai_workflow_execution_log, 5, ai_workflow_run: run)
      end
    end
  end
end