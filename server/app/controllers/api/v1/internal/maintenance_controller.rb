# frozen_string_literal: true

class Api::V1::Internal::MaintenanceController < Api::V1::Internal::InternalBaseController
  # Internal API endpoints for maintenance operations
  # These endpoints are called by background workers only

  # GET /api/v1/internal/maintenance/backups/:id
  def show_backup
    backup = Database::Backup.find_by!(id: params[:id])

    render_success({
      id: backup.id,
      file_path: backup.file_path,
      backup_type: backup.backup_type,
      status: backup.status,
      description: backup.description,
      file_size_bytes: backup.file_size_bytes,
      metadata: backup.metadata,
      created_by_id: backup.created_by_id,
      started_at: backup.started_at,
      completed_at: backup.completed_at,
      created_at: backup.created_at
    })
  rescue ActiveRecord::RecordNotFound
    render_error("Backup not found", status: :not_found)
  end

  # PATCH /api/v1/internal/maintenance/backups/:id
  def update_backup
    backup = Database::Backup.find_by!(id: params[:id])

    case params[:status]
    when "running"
      backup.update!(
        status: "running",
        started_at: Time.current
      )
    when "completed"
      backup.update!(
        status: "completed",
        completed_at: Time.current,
        file_path: params[:file_path],
        file_size_bytes: params[:file_size_bytes],
        duration_seconds: params[:duration_seconds]
      )
    when "failed"
      backup.update!(
        status: "failed",
        completed_at: Time.current,
        error_message: params[:error_message],
        duration_seconds: params[:duration_seconds]
      )
    else
      backup.update!(backup_update_params)
    end

    render_success({
      id: backup.id,
      status: backup.status,
      message: "Backup status updated successfully"
    })
  rescue ActiveRecord::RecordNotFound
    render_error("Backup not found", status: :not_found)
  rescue ActiveRecord::RecordInvalid => e
    render_error("Failed to update backup: #{e.message}", status: :unprocessable_content)
  end

  # GET /api/v1/internal/maintenance/restores/:id
  def show_restore
    restore = Database::Restore.find_by!(id: params[:id])

    render_success({
      id: restore.id,
      database_backup_id: restore.database_backup_id,
      status: restore.status,
      description: restore.description,
      backup_file_path: restore.database_backup&.file_path,
      metadata: restore.metadata,
      initiated_by_id: restore.initiated_by_id,
      started_at: restore.started_at,
      completed_at: restore.completed_at,
      created_at: restore.created_at
    })
  rescue ActiveRecord::RecordNotFound
    render_error("Restore not found", status: :not_found)
  end

  # PATCH /api/v1/internal/maintenance/restores/:id
  def update_restore
    restore = Database::Restore.find_by!(id: params[:id])

    case params[:status]
    when "running"
      restore.update!(
        status: "running",
        started_at: Time.current
      )
    when "completed"
      restore.update!(
        status: "completed",
        completed_at: Time.current,
        duration_seconds: params[:duration_seconds]
      )
    when "failed"
      restore.update!(
        status: "failed",
        completed_at: Time.current,
        error_message: params[:error_message],
        duration_seconds: params[:duration_seconds]
      )
    else
      restore.update!(restore_update_params)
    end

    render_success({
      id: restore.id,
      status: restore.status,
      message: "Restore status updated successfully"
    })
  rescue ActiveRecord::RecordNotFound
    render_error("Restore not found", status: :not_found)
  rescue ActiveRecord::RecordInvalid => e
    render_error("Failed to update restore: #{e.message}", status: :unprocessable_content)
  end

  # GET /api/v1/internal/maintenance/scheduled_tasks
  # Returns tasks that are due for execution
  def list_due_tasks
    due_before = params[:due_before] ? Time.parse(params[:due_before]) : Time.current

    tasks = ScheduledTask.where(is_active: true)
                         .where("next_run_at <= ?", due_before)
                         .order(:next_run_at)
                         .limit(params[:limit] || 50)

    render_success({
      tasks: tasks.map { |task|
        {
          id: task.id,
          name: task.name,
          task_type: task.task_type,
          cron_expression: task.cron_expression,
          parameters: task.parameters,
          next_run_at: task.next_run_at,
          last_run_at: task.last_run_at
        }
      },
      count: tasks.count
    })
  end

  # POST /api/v1/internal/maintenance/scheduled_tasks/:id/executions
  def create_task_execution
    task = ScheduledTask.find_by!(id: params[:id])

    execution = task.task_executions.create!(
      status: "running",
      started_at: Time.current
    )

    # Update task's last_run_at and next_run_at
    task.update!(
      last_run_at: Time.current,
      next_run_at: calculate_next_run(task.cron_expression)
    )

    render_success({
      execution_id: execution.id,
      task_id: task.id,
      status: execution.status,
      started_at: execution.started_at
    })
  rescue ActiveRecord::RecordNotFound
    render_error("Task not found", status: :not_found)
  rescue ActiveRecord::RecordInvalid => e
    render_error("Failed to create execution: #{e.message}", status: :unprocessable_content)
  end

  # PATCH /api/v1/internal/maintenance/task_executions/:id
  def update_task_execution
    execution = TaskExecution.find_by!(id: params[:id])

    case params[:status]
    when "running"
      execution.update!(status: "running")
    when "completed"
      execution.update!(
        status: "completed",
        completed_at: Time.current,
        duration_ms: params[:duration_ms],
        log_output: params[:log_output],
        result: params[:result]
      )
    when "failed"
      execution.update!(
        status: "failed",
        completed_at: Time.current,
        duration_ms: params[:duration_ms],
        error_message: params[:error_message]
      )
    else
      execution.update!(execution_update_params)
    end

    render_success({
      execution_id: execution.id,
      task_id: execution.scheduled_task_id,
      status: execution.status,
      message: "Execution status updated successfully"
    })
  rescue ActiveRecord::RecordNotFound
    render_error("Execution not found", status: :not_found)
  rescue ActiveRecord::RecordInvalid => e
    render_error("Failed to update execution: #{e.message}", status: :unprocessable_content)
  end

  # POST /api/v1/internal/maintenance/backups/:id/cleanup
  def cleanup_old_backups
    days_to_keep = params[:days_to_keep]&.to_i || 30

    cutoff_date = days_to_keep.days.ago
    old_backups = Database::Backup.where("created_at < ?", cutoff_date)
                                .where(status: "completed")

    deleted_count = 0
    failed_count = 0

    old_backups.find_each do |backup|
      # Delete the actual backup file
      if backup.file_path.present? && File.exist?(backup.file_path)
        File.delete(backup.file_path) rescue nil
      end

      # Delete the database record
      if backup.destroy
        deleted_count += 1
      else
        failed_count += 1
      end
    rescue StandardError => e
      Rails.logger.error "Failed to delete backup #{backup.id}: #{e.message}"
      failed_count += 1
    end

    render_success({
      deleted_count: deleted_count,
      failed_count: failed_count,
      cutoff_date: cutoff_date.iso8601,
      message: "Backup cleanup completed"
    })
  end

  private

  def backup_update_params
    params.permit(
      :status, :file_path, :file_size_bytes, :duration_seconds,
      :error_message, :started_at, :completed_at
    )
  end

  def restore_update_params
    params.permit(
      :status, :duration_seconds,
      :error_message, :started_at, :completed_at
    )
  end

  def execution_update_params
    params.permit(
      :status, :duration_ms, :log_output, :result,
      :error_message, :completed_at
    )
  end

  def calculate_next_run(cron_expression)
    # Use the fugit gem to parse cron expressions
    cron = Fugit::Cron.parse(cron_expression)
    cron&.next_time&.to_t || 1.day.from_now
  rescue StandardError => e
    Rails.logger.error "Failed to parse cron expression: #{e.message}"
    1.day.from_now
  end
end
