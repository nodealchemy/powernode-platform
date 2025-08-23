# frozen_string_literal: true

class ScheduledTaskJob < ApplicationJob
  queue_as :scheduled_tasks

  retry_on StandardError, wait: :exponentially_longer, attempts: 2

  def perform(execution_id)
    ScheduledTaskService.execute_scheduled_task(execution_id)
  rescue => e
    Rails.logger.error "Scheduled task job failed for execution #{execution_id}: #{e.message}"
    
    # Update execution status to failed
    execution = TaskExecution.find_by(id: execution_id)
    if execution
      execution.update!(
        status: 'failed',
        error_message: e.message,
        completed_at: Time.current
      )
    end
    
    raise e
  end
end