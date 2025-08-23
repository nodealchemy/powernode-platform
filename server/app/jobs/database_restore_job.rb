# frozen_string_literal: true

class DatabaseRestoreJob < ApplicationJob
  queue_as :maintenance

  retry_on StandardError, wait: :exponentially_longer, attempts: 1

  def perform(restore_id)
    DatabaseBackupService.perform_restore(restore_id)
  rescue => e
    Rails.logger.error "Database restore job failed for restore #{restore_id}: #{e.message}"
    
    # Update restore status to failed
    restore = DatabaseRestore.find_by(id: restore_id)
    if restore
      restore.update!(
        status: 'failed',
        error_message: e.message,
        completed_at: Time.current
      )
    end
    
    raise e
  end
end