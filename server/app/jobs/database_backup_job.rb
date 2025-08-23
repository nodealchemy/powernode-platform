# frozen_string_literal: true

class DatabaseBackupJob < ApplicationJob
  queue_as :maintenance

  retry_on StandardError, wait: :exponentially_longer, attempts: 2

  def perform(backup_id)
    DatabaseBackupService.perform_backup(backup_id)
  rescue => e
    Rails.logger.error "Database backup job failed for backup #{backup_id}: #{e.message}"
    
    # Update backup status to failed
    backup = DatabaseBackup.find_by(id: backup_id)
    if backup
      backup.update!(
        status: 'failed',
        error_message: e.message,
        completed_at: Time.current
      )
    end
    
    raise e
  end
end