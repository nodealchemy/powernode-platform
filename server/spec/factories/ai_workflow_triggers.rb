# frozen_string_literal: true

FactoryBot.define do
  factory :ai_workflow_trigger do
    ai_workflow
    trigger_type { 'event' }
    name { "#{trigger_type.humanize} Trigger" }
    is_active { true }
    status { 'active' }
    # webhook_url is required by database constraint for webhook triggers
    webhook_url { trigger_type == 'webhook' ? "https://api.example.com/webhooks/#{SecureRandom.hex(16)}" : nil }
    configuration do
      case trigger_type
      when 'event'
        {
          event_types: ['workflow_completed', 'user_created'],
          filter_conditions: {
            'workflow.status': 'success',
            'user.role': 'admin'
          },
          debounce_seconds: 5
        }
      when 'webhook'
        {
          webhook_path: '/webhooks/trigger',
          http_methods: ['POST'],
          signature_verification: true,
          signature_header: 'X-Signature',
          secret_key: 'webhook_secret_key'
        }
      when 'schedule'
        {
          cron_expression: '0 9 * * *',
          timezone: 'UTC',
          max_missed_runs: 3
        }
      when 'api'
        {
          api_endpoints: ['/api/v1/workflows/execute'],
          authentication_required: true,
          rate_limit: {
            requests_per_minute: 60,
            requests_per_hour: 1000
          }
        }
      else
        {}
      end
    end
    metadata do
      {
        created_by: 'system',
        trigger_category: trigger_type,
        description: "#{trigger_type} trigger for #{ai_workflow&.name}"
      }
    end

    trait :inactive do
      is_active { false }
    end

    trait :webhook_trigger do
      trigger_type { 'webhook' }
      name { 'Webhook Trigger' }
      webhook_url { "https://api.example.com/webhooks/#{SecureRandom.hex(16)}" }
      configuration do
        {
          webhook_path: "/webhooks/#{SecureRandom.hex(8)}",
          http_methods: ['POST', 'PUT'],
          content_type: 'application/json',
          signature_verification: true,
          signature_header: 'X-Hub-Signature-256',
          signature_algorithm: 'sha256',
          secret_key: SecureRandom.hex(32),
          timeout_seconds: 30,
          retry_on_failure: true,
          max_retries: 3,
          required_headers: {
            'User-Agent': 'required',
            'X-Source': 'github|slack|zapier'
          },
          payload_validation: {
            required_fields: ['event_type', 'data'],
            max_payload_size: 1048576 # 1MB
          }
        }
      end
    end

    trait :github_webhook do
      trigger_type { 'webhook' }
      name { 'GitHub Webhook' }
      webhook_url { "https://api.example.com/webhooks/github/#{SecureRandom.hex(16)}" }
      configuration do
        {
          webhook_path: '/webhooks/github',
          http_methods: ['POST'],
          signature_verification: true,
          signature_header: 'X-Hub-Signature-256',
          signature_algorithm: 'sha256',
          secret_key: 'github_webhook_secret',
          event_filters: {
            'X-GitHub-Event': ['push', 'pull_request', 'issues'],
            'action': ['opened', 'closed', 'synchronize']
          },
          payload_mapping: {
            'repository.full_name': 'repo_name',
            'sender.login': 'user',
            'action': 'event_action'
          },
          response_template: {
            'status': 'received',
            'workflow_triggered': true
          }
        }
      end
    end

    trait :slack_webhook do
      trigger_type { 'webhook' }
      name { 'Slack Webhook' }
      webhook_url { "https://api.example.com/webhooks/slack/#{SecureRandom.hex(16)}" }
      configuration do
        {
          webhook_path: '/webhooks/slack',
          http_methods: ['POST'],
          content_type: 'application/x-www-form-urlencoded',
          signature_verification: true,
          signature_header: 'X-Slack-Signature',
          timestamp_header: 'X-Slack-Request-Timestamp',
          secret_key: 'slack_signing_secret',
          event_filters: {
            'event.type': ['message', 'app_mention'],
            'event.subtype': [nil, 'bot_message']
          },
          slack_specific: {
            verify_timestamp: true,
            timestamp_tolerance: 300,
            challenge_response: true
          }
        }
      end
    end

    trait :event_trigger do
      trigger_type { 'event' }
      name { 'Platform Event Trigger' }
      configuration do
        {
          event_types: [
            'workflow.completed',
            'workflow.failed',
            'user.created',
            'payment.processed'
          ],
          event_sources: ['internal', 'api', 'webhook'],
          filter_conditions: {
            'workflow.account_id': '{{account.id}}',
            'event.severity': ['info', 'warning', 'error']
          },
          conditional_logic: {
            operator: 'AND',
            conditions: [
              {
                field: 'event.type',
                operator: 'equals',
                value: 'workflow.completed'
              },
              {
                field: 'workflow.success_rate',
                operator: 'greater_than',
                value: 0.8
              }
            ]
          },
          debounce_seconds: 10,
          max_events_per_minute: 100
        }
      end
    end

    trait :schedule_trigger do
      trigger_type { 'schedule' }
      name { 'Scheduled Trigger' }
      configuration do
        {
          cron_expression: '0 */6 * * *', # Every 6 hours
          timezone: 'America/New_York',
          max_missed_runs: 2,
          allow_concurrent_runs: false,
          schedule_metadata: {
            description: 'Runs every 6 hours during business days',
            next_run_estimate: 6.hours.from_now.iso8601
          },
          holiday_calendar: 'US',
          skip_holidays: false,
          execution_window: {
            start_hour: 9,
            end_hour: 17,
            business_days_only: false
          }
        }
      end
    end

    trait :api_trigger do
      trigger_type { 'api' }
      name { 'API Trigger' }
      configuration do
        {
          api_endpoints: [
            '/api/v1/workflows/execute',
            '/api/v1/triggers/fire'
          ],
          http_methods: ['POST', 'PUT'],
          authentication_required: true,
          authentication_types: ['api_key', 'bearer_token'],
          rate_limiting: {
            requests_per_minute: 120,
            requests_per_hour: 5000,
            burst_allowance: 20,
            rate_limit_key: 'client_id'
          },
          request_validation: {
            required_headers: ['Content-Type', 'Authorization'],
            max_payload_size: 2097152, # 2MB
            allowed_content_types: [
              'application/json',
              'application/x-www-form-urlencoded'
            ]
          },
          response_customization: {
            include_run_id: true,
            include_estimated_completion: true,
            custom_headers: {
              'X-Workflow-Trigger': 'api',
              'X-Rate-Limit-Remaining': '{{rate_limit.remaining}}'
            }
          }
        }
      end
    end

    trait :data_change_trigger do
      trigger_type { 'data_change' }
      name { 'Data Change Trigger' }
      configuration do
        {
          data_sources: [
            {
              type: 'database',
              connection: 'primary',
              tables: ['users', 'orders', 'products'],
              operations: ['INSERT', 'UPDATE', 'DELETE']
            },
            {
              type: 'api',
              endpoint: 'https://api.example.com/data',
              poll_interval: 300,
              change_detection: 'timestamp'
            }
          ],
          change_filters: {
            'table_name': ['users', 'orders'],
            'operation': ['INSERT', 'UPDATE'],
            'changed_fields': ['status', 'email', 'amount']
          },
          batch_processing: {
            enabled: true,
            batch_size: 100,
            batch_timeout: 30
          },
          deduplication: {
            enabled: true,
            key_fields: ['id', 'updated_at'],
            window_seconds: 60
          }
        }
      end
    end

    trait :file_system_trigger do
      trigger_type { 'file_system' }
      name { 'File System Trigger' }
      configuration do
        {
          watched_paths: [
            '/uploads/incoming',
            '/data/exports'
          ],
          file_patterns: [
            '*.csv',
            '*.json',
            '*.xml'
          ],
          watch_events: [
            'file_created',
            'file_modified',
            'file_deleted'
          ],
          file_filters: {
            min_size_bytes: 1024,
            max_size_bytes: 104857600, # 100MB
            max_age_hours: 24
          },
          processing_options: {
            move_processed_files: true,
            processed_path: '/processed',
            error_path: '/errors',
            backup_original: true
          }
        }
      end
    end

    trait :time_based_trigger do
      trigger_type { 'time_based' }
      name { 'Time-Based Trigger' }
      configuration do
        {
          trigger_times: [
            {
              time: '09:00',
              days_of_week: ['monday', 'wednesday', 'friday'],
              timezone: 'UTC'
            },
            {
              time: '14:30',
              days_of_week: ['tuesday', 'thursday'],
              timezone: 'America/New_York'
            }
          ],
          date_ranges: [
            {
              start_date: '2024-01-01',
              end_date: '2024-12-31',
              include_holidays: false
            }
          ],
          relative_triggers: [
            {
              relative_to: 'workflow_completion',
              offset: {
                hours: 24,
                minutes: 0
              },
              condition: 'previous_workflow_success'
            }
          ]
        }
      end
    end

    trait :conditional_trigger do
      trigger_type { 'conditional' }
      name { 'Conditional Logic Trigger' }
      configuration do
        {
          conditions: {
            operator: 'AND',
            rules: [
              {
                field: 'system.cpu_usage',
                operator: 'less_than',
                value: 80,
                data_source: 'monitoring_api'
              },
              {
                field: 'queue.depth',
                operator: 'greater_than',
                value: 100,
                data_source: 'queue_metrics'
              },
              {
                field: 'business_hours',
                operator: 'equals',
                value: true,
                data_source: 'time_check'
              }
            ]
          },
          evaluation_frequency: 60, # seconds
          hysteresis: {
            enabled: true,
            threshold_percentage: 10
          },
          data_sources: {
            monitoring_api: {
              url: 'https://monitoring.example.com/metrics',
              method: 'GET',
              timeout: 10
            },
            queue_metrics: {
              url: 'https://queue.example.com/stats',
              method: 'GET',
              headers: { 'Authorization': 'Bearer {{api_token}}' }
            }
          }
        }
      end
    end

    trait :complex_event_processing do
      trigger_type { 'complex_event' }
      name { 'Complex Event Processing' }
      configuration do
        {
          event_pattern: {
            pattern_type: 'sequence',
            events: [
              {
                event_type: 'user.login',
                time_window: 300,
                required: true
              },
              {
                event_type: 'page.view',
                filters: { 'page.type': 'product' },
                min_occurrences: 3,
                time_window: 600
              },
              {
                event_type: 'cart.add',
                time_window: 900,
                required: false
              }
            ],
            max_pattern_duration: 1800,
            correlation_key: 'user.id'
          },
          pattern_matching: {
            allow_partial_matches: false,
            require_order: true,
            sliding_window: true
          },
          aggregations: {
            count_events: true,
            sum_values: ['cart.value', 'product.price'],
            calculate_metrics: ['conversion_rate', 'session_duration']
          }
        }
      end
    end

    trait :with_execution_history do
      after(:create) do |trigger|
        # Create some trigger execution history
        5.times do |i|
          create(:ai_workflow_run,
                 ai_workflow: trigger.ai_workflow,
                 trigger_type: trigger.trigger_type,
                 trigger_context: {
                   trigger_id: trigger.id,
                   triggered_at: i.hours.ago.iso8601
                 },
                 created_at: i.hours.ago)
        end
      end
    end

    trait :high_frequency do
      configuration do
        base_config = attributes_for(:ai_workflow_trigger)[:configuration]
        base_config.merge(
          frequency: 'high',
          max_triggers_per_minute: 1000,
          batch_processing: true,
          performance_monitoring: {
            track_response_time: true,
            alert_on_slow_response: true,
            max_response_time_ms: 100
          }
        )
      end
    end

    trait :with_custom_payload_mapping do
      configuration do
        {
          payload_transformation: {
            input_mapping: {
              'webhook.body.user_id': 'workflow.input.user_id',
              'webhook.body.event.type': 'workflow.input.event_type',
              'webhook.headers.x-source': 'workflow.input.source'
            },
            transformation_script: "function transform(input) { return { user_id: input.user_id, event_type: input.event_type.toLowerCase(), source: input.source || 'unknown', timestamp: new Date().toISOString(), processed: true }; }",
            output_validation: {
              required_fields: ['user_id', 'event_type'],
              field_types: {
                'user_id': 'string',
                'timestamp': 'iso8601'
              }
            }
          }
        }
      end
    end
  end
end