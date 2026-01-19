# frozen_string_literal: true

module Maintenance
  # Job for triggering scheduled database backups
  #
  # This job is scheduled via sidekiq-scheduler to run at configured times.
  # It triggers a backup via the backend API, which then queues the actual
  # backup work via DatabaseBackupJob.
  #
  class ScheduledBackupJob < BaseJob
    sidekiq_options queue: 'maintenance',
                    retry: 3,
                    dead: true

    def execute(backup_type: 'full')
      log_info "Starting scheduled backup", backup_type: backup_type

      # Validate backup type
      unless %w[full incremental schema_only].include?(backup_type)
        log_error "Invalid backup type", nil, backup_type: backup_type
        return { success: false, error: "Invalid backup type: #{backup_type}" }
      end

      # Create backup via backend API
      response = create_backup_via_api(backup_type)

      if response[:success]
        log_info "Scheduled backup initiated",
                 backup_id: response[:backup_id],
                 backup_type: backup_type

        {
          success: true,
          backup_id: response[:backup_id],
          backup_type: backup_type,
          message: "Backup job queued successfully"
        }
      else
        log_error "Failed to initiate scheduled backup", nil,
                  backup_type: backup_type,
                  error: response[:error]

        # Don't raise - let retry handle transient failures
        {
          success: false,
          error: response[:error]
        }
      end
    end

    private

    def create_backup_via_api(backup_type)
      response = api_client.post(
        '/api/v1/internal/maintenance/backups',
        {
          backup_type: backup_type,
          description: "Automated scheduled #{backup_type} backup - #{Time.current.strftime('%Y-%m-%d %H:%M UTC')}",
          scheduled: true
        }
      )

      if response['success']
        {
          success: true,
          backup_id: response.dig('data', 'id') || response.dig('backup', 'id')
        }
      else
        {
          success: false,
          error: response['error'] || response['message'] || 'Unknown error'
        }
      end
    rescue Faraday::Error => e
      log_error "API request failed", e
      { success: false, error: "API request failed: #{e.message}" }
    rescue => e
      log_error "Unexpected error creating backup", e
      { success: false, error: e.message }
    end
  end
end
