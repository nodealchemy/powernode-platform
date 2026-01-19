# frozen_string_literal: true

module Maintenance
  # Job for cleaning up expired database backups
  #
  # This job removes backup files and records that exceed the retention period.
  # It should be scheduled to run daily to maintain storage hygiene.
  #
  class BackupCleanupJob < BaseJob
    sidekiq_options queue: 'maintenance',
                    retry: 2,
                    dead: true

    # Default retention period in days
    RETENTION_DAYS = ENV.fetch('BACKUP_RETENTION_DAYS', 30).to_i

    # Maximum number of backups to delete per run (prevents long-running jobs)
    MAX_DELETIONS_PER_RUN = 100

    def execute
      log_info "Starting backup cleanup", retention_days: RETENTION_DAYS

      # Get list of expired backups from backend
      expired_backups = fetch_expired_backups

      if expired_backups.empty?
        log_info "No expired backups to clean up"
        return { success: true, deleted_count: 0 }
      end

      log_info "Found expired backups", count: expired_backups.size

      deleted_count = 0
      failed_count = 0

      expired_backups.take(MAX_DELETIONS_PER_RUN).each do |backup|
        result = delete_backup(backup['id'])

        if result[:success]
          deleted_count += 1
          log_info "Deleted backup", backup_id: backup['id']
        else
          failed_count += 1
          log_error "Failed to delete backup", nil,
                    backup_id: backup['id'],
                    error: result[:error]
        end
      end

      remaining = expired_backups.size - MAX_DELETIONS_PER_RUN
      if remaining > 0
        log_info "More backups need cleanup",
                 remaining: remaining,
                 message: "Will be processed in next scheduled run"
      end

      {
        success: failed_count == 0,
        deleted_count: deleted_count,
        failed_count: failed_count,
        remaining_count: [remaining, 0].max
      }
    end

    private

    def fetch_expired_backups
      cutoff_date = (Time.current - RETENTION_DAYS.days).iso8601

      response = api_client.get(
        '/api/v1/internal/maintenance/backups',
        { created_before: cutoff_date, status: 'completed' }
      )

      response['data'] || []
    rescue => e
      log_error "Failed to fetch expired backups", e
      []
    end

    def delete_backup(backup_id)
      response = api_client.delete("/api/v1/internal/maintenance/backups/#{backup_id}")

      if response['success']
        { success: true }
      else
        { success: false, error: response['error'] || 'Unknown error' }
      end
    rescue => e
      { success: false, error: e.message }
    end
  end
end
