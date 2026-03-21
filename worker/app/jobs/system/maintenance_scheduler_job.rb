# frozen_string_literal: true

module System
  # MaintenanceSchedulerJob - Schedules maintenance for all accounts
  #
  # This job runs periodically to queue maintenance operations for all accounts.
  # It replicates the behavior of the legacy powernode-agent poller.
  #
  # @example Run the scheduler
  #   System::MaintenanceSchedulerJob.perform_async
  #
  class MaintenanceSchedulerJob < BaseJob
    sidekiq_options queue: 'system',
                    retry: 1,
                    dead: false

    # Execute maintenance scheduling
    def execute
      log_info('Starting maintenance scheduler run')
      start_time = Time.current
      accounts_queued = 0
      errors = []

      begin
        # Get all accounts that need maintenance
        accounts = fetch_maintenance_accounts

        accounts.each do |account|
          begin
            System::MaintenanceJob.perform_async(account['id'])
            accounts_queued += 1
          rescue StandardError => e
            log_warn('Failed to queue maintenance for account',
                     account_id: account['id'],
                     error: e.message)
            errors << { account_id: account['id'], error: e.message }
          end
        end

        duration = Time.current - start_time
        log_info('Maintenance scheduler completed',
                 accounts_queued: accounts_queued,
                 errors_count: errors.size,
                 duration: duration)

        track_performance_metric('system_maintenance_scheduler_duration', duration)
        increment_counter('system_maintenance_scheduler_runs')

        { accounts_queued: accounts_queued, errors: errors, duration: duration }

      rescue StandardError => e
        log_error('Maintenance scheduler failed', e)
        track_error_metric('maintenance_scheduler_failed')
        raise
      end
    end

    private

    def fetch_maintenance_accounts
      with_api_retry do
        response = api_client.get('/api/v1/internal/system/accounts', for_maintenance: true)
        response['accounts'] || []
      end
    rescue BackendApiClient::ApiError => e
      log_error('Failed to fetch accounts for maintenance', e)
      []
    end
  end
end
