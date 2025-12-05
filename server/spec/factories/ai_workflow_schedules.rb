# frozen_string_literal: true

FactoryBot.define do
  factory :ai_workflow_schedule do
    ai_workflow
    account { ai_workflow.account }
    name { "#{ai_workflow.name} Schedule" }
    cron_expression { '0 9 * * *' } # Daily at 9 AM
    timezone { 'UTC' }
    is_active { true }
    input_variables do
      {
        scheduled_execution: true,
        trigger_source: 'cron_schedule',
        execution_context: {
          scheduled_at: Time.current.iso8601
        }
      }
    end
    configuration do
      {
        max_missed_runs: 3,
        allow_concurrent_runs: false,
        timeout_seconds: 3600,
        retry_failed_runs: true,
        notification_settings: {
          on_success: false,
          on_failure: true,
          channels: ['email']
        }
      }
    end

    trait :inactive do
      is_active { false }
    end

    trait :hourly do
      cron_expression { '0 * * * *' }
      name { "Hourly #{ai_workflow.name}" }
      configuration do
        {
          max_missed_runs: 5,
          allow_concurrent_runs: false,
          timeout_seconds: 1800
        }
      end
    end

    trait :daily do
      cron_expression { '0 2 * * *' } # Daily at 2 AM
      name { "Daily #{ai_workflow.name}" }
      timezone { 'America/New_York' }
    end

    trait :weekly do
      cron_expression { '0 9 * * 1' } # Monday at 9 AM
      name { "Weekly #{ai_workflow.name}" }
      configuration do
        {
          max_missed_runs: 2,
          allow_concurrent_runs: false,
          timeout_seconds: 7200,
          notification_settings: {
            on_success: true,
            on_failure: true,
            channels: ['email', 'slack']
          }
        }
      end
    end

    trait :monthly do
      cron_expression { '0 9 1 * *' } # First day of month at 9 AM
      name { "Monthly #{ai_workflow.name}" }
      configuration do
        {
          max_missed_runs: 1,
          allow_concurrent_runs: false,
          timeout_seconds: 10800,
          end_date: 1.year.from_now.iso8601
        }
      end
    end

    trait :weekdays_only do
      cron_expression { '0 9 * * 1-5' } # Weekdays at 9 AM
      name { "Weekday #{ai_workflow.name}" }
      timezone { 'America/Los_Angeles' }
    end

    trait :custom_interval do
      cron_expression { '*/15 * * * *' } # Every 15 minutes
      name { "Custom Interval #{ai_workflow.name}" }
      configuration do
        {
          max_missed_runs: 10,
          allow_concurrent_runs: true,
          max_concurrent_runs: 3,
          timeout_seconds: 900
        }
      end
    end

    trait :with_end_date do
      configuration do
        {
          start_date: Time.current.iso8601,
          end_date: 6.months.from_now.iso8601,
          max_executions: 100
        }
      end
    end

    trait :high_frequency do
      cron_expression { '* * * * *' } # Every minute
      name { "High Frequency #{ai_workflow.name}" }
      configuration do
        {
          max_missed_runs: 60,
          allow_concurrent_runs: true,
          max_concurrent_runs: 10,
          timeout_seconds: 30,
          circuit_breaker: {
            failure_threshold: 5,
            recovery_timeout: 300
          }
        }
      end
    end

    trait :business_hours do
      cron_expression { '0 9-17 * * 1-5' } # Business hours, weekdays
      name { "Business Hours #{ai_workflow.name}" }
      timezone { 'America/New_York' }
      configuration do
        {
          holiday_calendar: 'US',
          skip_holidays: true,
          notification_settings: {
            business_hours_only: true
          }
        }
      end
    end

    trait :report_generation do
      name { "Daily Report Generation" }
      cron_expression { '0 23 * * *' } # Daily at 11 PM
      input_variables do
        {
          report_type: 'daily_summary',
          date_range: 'yesterday',
          output_format: 'pdf',
          recipients: ['reports@example.com']
        }
      end
      configuration do
        {
          timeout_seconds: 1800,
          retry_failed_runs: true,
          max_retries: 3,
          notification_settings: {
            on_success: true,
            on_failure: true,
            include_logs: true
          }
        }
      end
    end

    trait :data_sync do
      name { "Hourly Data Synchronization" }
      cron_expression { '0 * * * *' } # Every hour
      input_variables do
        {
          sync_type: 'incremental',
          data_sources: ['database_a', 'api_endpoint_b'],
          conflict_resolution: 'timestamp_wins'
        }
      end
      configuration do
        {
          timeout_seconds: 900,
          allow_concurrent_runs: false,
          circuit_breaker: {
            enabled: true,
            failure_threshold: 3,
            recovery_timeout: 1800
          }
        }
      end
    end

    trait :maintenance_task do
      name { "Weekly Maintenance" }
      cron_expression { '0 2 * * 0' } # Sunday at 2 AM
      input_variables do
        {
          maintenance_type: 'cleanup',
          target_resources: ['temp_files', 'old_logs', 'expired_cache'],
          dry_run: false
        }
      end
      configuration do
        {
          timeout_seconds: 3600,
          max_missed_runs: 1,
          notification_settings: {
            on_success: true,
            on_failure: true,
            channels: ['email', 'slack'],
            include_summary: true
          }
        }
      end
    end

    trait :with_execution_history do
      after(:create) do |schedule|
        # Create some past executions
        5.times do |i|
          create(:ai_workflow_run,
                 :completed,
                 ai_workflow: schedule.ai_workflow,
                 trigger_type: 'schedule',
                 trigger_context: {
                   schedule_id: schedule.id,
                   scheduled_time: i.days.ago.iso8601
                 },
                 created_at: i.days.ago)
        end

        # Create a recent failed execution
        create(:ai_workflow_run,
               :failed,
               ai_workflow: schedule.ai_workflow,
               trigger_type: 'schedule',
               trigger_context: {
                 schedule_id: schedule.id,
                 scheduled_time: 1.hour.ago.iso8601
               },
               created_at: 1.hour.ago)
      end
    end

    trait :paused do
      is_active { false }
      paused_at { 2.hours.ago }
      pause_reason { 'too_many_failures' }
      metadata do
        {
          pause_details: {
            paused_by: 'system',
            failure_count: 5,
            last_failure: 2.hours.ago.iso8601
          }
        }
      end
    end

    trait :with_complex_config do
      configuration do
        {
          max_missed_runs: 5,
          allow_concurrent_runs: true,
          max_concurrent_runs: 3,
          timeout_seconds: 1800,
          retry_failed_runs: true,
          max_retries: 3,
          retry_delay: 300,
          exponential_backoff: true,
          circuit_breaker: {
            enabled: true,
            failure_threshold: 5,
            success_threshold: 3,
            timeout: 300,
            recovery_timeout: 1800
          },
          notification_settings: {
            on_success: false,
            on_failure: true,
            on_missed_run: true,
            channels: ['email', 'webhook'],
            webhook_url: 'https://alerts.example.com/webhook',
            email_template: 'schedule_failure',
            include_logs: true,
            include_metrics: true
          },
          resource_limits: {
            max_memory_mb: 512,
            max_cpu_percent: 80,
            max_execution_time: 1800
          },
          environment_variables: {
            'SCHEDULE_EXECUTION': 'true',
            'LOG_LEVEL': 'info'
          }
        }
      end
    end

    # Factory for testing timezone handling
    trait :multiple_timezones do
      after(:build) do |schedule|
        schedule.timezone = ['UTC', 'America/New_York', 'Europe/London', 'Asia/Tokyo'].sample
      end
    end

    # Factory for testing cron expression validation
    trait :invalid_cron do
      cron_expression { '60 25 32 13 *' } # Invalid: minute=60, hour=25, day=32, month=13
    end

    trait :complex_cron do
      cron_expression { '0 9,13,17 * * 1-5' } # Multiple times on weekdays
      name { "Multi-time Schedule" }
    end
  end
end