# frozen_string_literal: true

FactoryBot.define do
  factory :ai_workflow_execution_log, class: "Ai::WorkflowExecutionLog" do
    association :workflow_run, factory: :ai_workflow_run
    account { workflow_run.account }
    log_level { 'info' }
    message { 'Workflow execution log message' }
    log_data do
      {
        step: 'node_execution',
        node_id: SecureRandom.uuid,
        execution_time: 1500,
        status: 'success'
      }
    end
    source_component { 'workflow_engine' }

    trait :debug do
      log_level { 'debug' }
      message { 'Debug information for workflow execution' }
      log_data do
        {
          debug_info: {
            memory_usage: 45_600_000,
            cpu_time: 150,
            variables_count: 12,
            active_connections: 3
          },
          execution_context: {
            current_node: 'ai_agent_node_1',
            next_nodes: [ 'transform_node_1' ],
            loop_iteration: nil
          }
        }
      end
    end

    trait :info do
      log_level { 'info' }
      message { 'Workflow step completed successfully' }
      log_data do
        {
          step: 'node_completion',
          node_name: 'AI Content Generator',
          duration_ms: 3400,
          tokens_used: 450,
          cost: 0.0067
        }
      end
    end

    trait :warn do
      log_level { 'warn' }
      message { 'Workflow execution warning' }
      log_data do
        {
          warning_type: 'high_cost',
          current_cost: 0.85,
          cost_threshold: 1.00,
          recommendation: 'Consider optimizing model parameters'
        }
      end
    end

    trait :error do
      log_level { 'error' }
      message { 'Node execution failed' }
      log_data do
        {
          error_type: 'api_timeout',
          error_code: 'TIMEOUT_ERROR',
          node_id: SecureRandom.uuid,
          node_type: 'api_call',
          attempt_number: 2,
          max_retries: 3,
          stack_trace: 'Error at line 45 in api_call_executor.rb'
        }
      end
    end

    trait :fatal do
      log_level { 'fatal' }
      message { 'Critical workflow execution failure' }
      log_data do
        {
          error_type: 'system_failure',
          error_message: 'Unable to connect to AI provider',
          system_state: 'degraded',
          recovery_action: 'workflow_terminated',
          incident_id: SecureRandom.uuid
        }
      end
    end

    trait :node_start do
      message { 'Node execution started' }
      log_data do
        {
          event_type: 'node_start',
          node_id: SecureRandom.uuid,
          node_type: 'ai_agent',
          node_name: 'Content Generator',
          input_size: 1500,
          configuration: {
            model: 'gpt-4',
            temperature: 0.7
          }
        }
      end
      source_component { 'node_executor' }
    end

    trait :node_complete do
      message { 'Node execution completed' }
      log_data do
        {
          event_type: 'node_complete',
          node_id: SecureRandom.uuid,
          node_type: 'ai_agent',
          execution_time_ms: 4200,
          output_size: 2800,
          success: true,
          metrics: {
            tokens_input: 380,
            tokens_output: 520,
            cost_estimate: 0.0089
          }
        }
      end
    end

    trait :workflow_start do
      message { 'Workflow execution started' }
      log_data do
        {
          event_type: 'workflow_start',
          workflow_id: workflow_run.workflow.id,
          workflow_name: workflow_run.workflow.name,
          trigger_type: workflow_run.trigger_type,
          input_variables: workflow_run.input_variables,
          total_nodes: 5,
          execution_mode: 'sequential'
        }
      end
      source_component { 'workflow_orchestrator' }
    end

    trait :workflow_complete do
      message { 'Workflow execution completed successfully' }
      log_data do
        {
          event_type: 'workflow_complete',
          total_execution_time_ms: 15_400,
          nodes_executed: 5,
          nodes_successful: 5,
          nodes_failed: 0,
          total_cost: 0.0456,
          output_summary: {
            content_generated: true,
            quality_score: 4.2,
            word_count: 1247
          }
        }
      end
    end

    trait :api_call_log do
      message { 'API call executed' }
      log_data do
        {
          event_type: 'api_call',
          method: 'POST',
          url: 'https://api.openai.com/v1/chat/completions',
          status_code: 200,
          response_time_ms: 2400,
          request_size: 450,
          response_size: 1200,
          headers: {
            'content-type': 'application/json',
            'x-ratelimit-remaining': '4999'
          }
        }
      end
      source_component { 'api_client' }
    end

    trait :webhook_sent do
      message { 'Webhook notification sent' }
      log_data do
        {
          event_type: 'webhook_sent',
          webhook_url: 'https://webhook.example.com/notify',
          method: 'POST',
          payload_size: 580,
          response_code: 200,
          response_time_ms: 450,
          signature_sent: true,
          delivery_attempt: 1
        }
      end
      source_component { 'webhook_sender' }
    end

    trait :condition_evaluated do
      message { 'Condition evaluation completed' }
      log_data do
        {
          event_type: 'condition_evaluated',
          condition_expression: 'output.score > 0.8',
          input_values: { score: 0.85, confidence: 0.92 },
          evaluation_result: true,
          next_path: 'success_branch',
          evaluation_time_ms: 15
        }
      end
      source_component { 'condition_evaluator' }
    end

    trait :loop_iteration do
      message { 'Loop iteration processed' }
      log_data do
        {
          event_type: 'loop_iteration',
          loop_node_id: SecureRandom.uuid,
          iteration_number: 3,
          total_iterations: 5,
          current_item: { id: 123, name: 'item_3' },
          processing_result: 'success',
          iteration_time_ms: 800
        }
      end
    end

    trait :human_approval_requested do
      message { 'Human approval requested' }
      log_data do
        {
          event_type: 'approval_requested',
          approval_id: SecureRandom.uuid,
          approval_type: 'content_review',
          requested_from: [ 'admin@example.com' ],
          timeout_minutes: 60,
          approval_url: 'https://app.example.com/approvals/abc123',
          notification_sent: true
        }
      end
      source_component { 'approval_system' }
    end

    trait :data_transform do
      message { 'Data transformation executed' }
      log_data do
        {
          event_type: 'data_transform',
          transform_script: 'output.upper_text = input.text.toUpperCase();',
          input_data_size: 250,
          output_data_size: 250,
          transformation_time_ms: 25,
          script_language: 'javascript',
          success: true
        }
      end
      source_component { 'transform_engine' }
    end

    trait :retry_attempt do
      log_level { 'warn' }
      message { 'Retrying failed node execution' }
      log_data do
        {
          event_type: 'retry_attempt',
          node_id: SecureRandom.uuid,
          original_error: 'API rate limit exceeded',
          retry_attempt: 2,
          max_retries: 3,
          retry_delay_seconds: 5,
          backoff_strategy: 'exponential'
        }
      end
    end

    trait :cache_hit do
      message { 'Cache hit for node execution' }
      log_data do
        {
          event_type: 'cache_hit',
          cache_key: 'ai_agent_content_gen_hash123',
          node_id: SecureRandom.uuid,
          cache_age_seconds: 450,
          cache_ttl_seconds: 3600,
          execution_time_saved_ms: 3200
        }
      end
      source_component { 'cache_manager' }
    end

    trait :resource_usage do
      message { 'Resource usage metrics' }
      log_data do
        {
          event_type: 'resource_usage',
          timestamp: Time.current.iso8601,
          metrics: {
            memory_usage_mb: 128.5,
            cpu_usage_percent: 25.8,
            active_connections: 4,
            queue_depth: 12,
            disk_io_operations: 45
          },
          thresholds: {
            memory_warning_mb: 256,
            cpu_warning_percent: 80
          }
        }
      end
      source_component { 'resource_monitor' }
    end

    trait :security_event do
      log_level { 'warn' }
      message { 'Security validation performed' }
      log_data do
        {
          event_type: 'security_check',
          check_type: 'input_validation',
          validation_result: 'passed',
          potential_issues: [],
          input_sanitized: true,
          security_score: 0.95,
          scan_duration_ms: 120
        }
      end
      source_component { 'security_scanner' }
    end

    trait :performance_alert do
      log_level { 'warn' }
      message { 'Performance threshold exceeded' }
      log_data do
        {
          event_type: 'performance_alert',
          metric_name: 'node_execution_time',
          current_value: 8500,
          threshold_value: 5000,
          threshold_unit: 'milliseconds',
          node_id: SecureRandom.uuid,
          performance_impact: 'medium',
          suggested_actions: [
            'optimize_model_parameters',
            'reduce_input_size',
            'enable_caching'
          ]
        }
      end
    end

    trait :batch_processing do
      message { 'Batch processing status' }
      log_data do
        {
          event_type: 'batch_processing',
          batch_id: SecureRandom.uuid,
          batch_size: 100,
          processed_count: 75,
          successful_count: 72,
          failed_count: 3,
          remaining_count: 25,
          processing_rate: 12.5, # items per second
          estimated_completion: 2.minutes.from_now.iso8601
        }
      end
    end

    trait :external_service_call do
      message { 'External service integration' }
      log_data do
        {
          event_type: 'external_service',
          service_name: 'slack_api',
          operation: 'send_message',
          endpoint: 'https://slack.com/api/chat.postMessage',
          request_id: SecureRandom.uuid,
          response_code: 200,
          response_time_ms: 680,
          rate_limit_remaining: 4995,
          success: true
        }
      end
      source_component { 'external_integrations' }
    end

    trait :workflow_paused do
      log_level { 'warn' }
      message { 'Workflow execution paused' }
      log_data do
        {
          event_type: 'workflow_paused',
          pause_reason: 'human_approval_required',
          paused_at_node: SecureRandom.uuid,
          pause_duration_estimate: 3600, # seconds
          resume_conditions: [ 'approval_granted' ],
          pause_token: SecureRandom.hex(32)
        }
      end
    end

    trait :workflow_resumed do
      message { 'Workflow execution resumed' }
      log_data do
        {
          event_type: 'workflow_resumed',
          pause_duration_seconds: 1800,
          resume_reason: 'approval_granted',
          resumed_at_node: SecureRandom.uuid,
          resume_token: SecureRandom.hex(32)
        }
      end
    end

    trait :cost_tracking do
      message { 'Cost tracking update' }
      log_data do
        {
          event_type: 'cost_update',
          operation_type: 'ai_agent_call',
          cost_increment: 0.0089,
          running_total: 0.0456,
          cost_breakdown: {
            input_tokens: 0.0038,
            output_tokens: 0.0051
          },
          provider: 'openai',
          model: 'gpt-4'
        }
      end
      source_component { 'cost_tracker' }
    end

    # Specific workflow types
    trait :blog_generation_log do
      message { 'Blog generation step completed' }
      log_data do
        {
          event_type: 'content_generation',
          content_type: 'blog_post',
          topic: 'AI in Software Development',
          word_count: 1247,
          quality_metrics: {
            readability_score: 78.5,
            seo_score: 85.2,
            uniqueness: 0.94
          },
          generation_time_ms: 8400,
          tokens_used: 1850
        }
      end
    end

    trait :data_processing_log do
      message { 'Data processing batch completed' }
      log_data do
        {
          event_type: 'data_processing',
          batch_id: SecureRandom.uuid,
          records_processed: 1000,
          records_successful: 987,
          records_failed: 13,
          processing_time_ms: 45_600,
          throughput_records_per_second: 21.9,
          data_quality_score: 0.987
        }
      end
    end

    trait :with_structured_metadata do
      log_data do
        {
          trace_id: SecureRandom.uuid,
          span_id: SecureRandom.hex(16),
          parent_span_id: SecureRandom.hex(16),
          operation_name: 'node_execution',
          tags: {
            component: 'workflow_engine',
            version: '1.2.3',
            environment: 'production'
          },
          duration_microseconds: 1_500_000,
          status: 'ok'
        }
      end
    end

    trait :performance_metrics do
      message { 'Performance metrics collected' }
      log_data do
        {
          metrics: {
            execution_time: 2400,
            memory_peak_mb: 67.8,
            cpu_time_ms: 1800,
            network_bytes_sent: 4096,
            network_bytes_received: 8192,
            cache_hits: 3,
            cache_misses: 1,
            database_queries: 0,
            external_api_calls: 2
          },
          baselines: {
            typical_execution_time: 1800,
            typical_memory_mb: 45.2
          },
          variance_analysis: {
            execution_time_variance: '+33%',
            memory_variance: '+50%'
          }
        }
      end
    end
  end
end
