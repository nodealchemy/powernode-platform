# frozen_string_literal: true

class Api::V1::Internal::MaintenanceController < ApplicationController
  skip_before_action :authenticate_request
  before_action :authenticate_service_token

  # Internal API endpoints for maintenance operations
  # These endpoints are called by background workers only

  # GET /api/v1/internal/maintenance/backups/:id
  def show_backup
    backup = Database::Backup.find_by!(id: params[:id])

    render_success({
      id: backup.id,
      filename: backup.filename,
      file_path: backup.file_path,
      backup_type: backup.backup_type,
      status: backup.status,
      description: backup.description,
      file_size: backup.file_size,
      database_name: backup.database_name,
      metadata: backup.metadata,
      user_id: backup.user_id,
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
    when "in_progress"
      backup.update!(
        status: "in_progress",
        started_at: Time.current
      )
    when "completed"
      backup.update!(
        status: "completed",
        completed_at: Time.current,
        file_path: params[:file_path],
        file_size: params[:file_size],
        duration_seconds: params[:duration_seconds],
        checksum: params[:checksum]
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
      restore_type: restore.restore_type,
      target_database: restore.target_database,
      backup_file_path: restore.database_backup&.file_path,
      metadata: restore.metadata,
      user_id: restore.user_id,
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
    when "in_progress"
      restore.update!(
        status: "in_progress",
        started_at: Time.current
      )
    when "completed"
      restore.update!(
        status: "completed",
        completed_at: Time.current,
        duration_seconds: params[:duration_seconds],
        tables_restored: params[:tables_restored],
        rows_restored: params[:rows_restored]
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

    tasks = ScheduledTask.enabled
                         .where("next_run_at <= ?", due_before)
                         .order(:next_run_at)
                         .limit(params[:limit] || 50)

    render_success({
      tasks: tasks.map { |task|
        {
          id: task.id,
          name: task.name,
          task_type: task.task_type,
          command: task.command,
          cron_schedule: task.cron_schedule,
          configuration: task.configuration,
          next_run_at: task.next_run_at,
          last_run_at: task.last_run_at,
          user_id: task.user_id
        }
      },
      count: tasks.count
    })
  end

  # POST /api/v1/internal/maintenance/scheduled_tasks/:id/executions
  def create_task_execution
    task = ScheduledTask.find_by!(id: params[:id])

    execution = task.task_executions.create!(
      status: "pending",
      started_at: Time.current,
      triggered_by: params[:triggered_by] || "scheduler",
      job_id: params[:job_id]
    )

    # Update task's last_run_at and next_run_at
    task.update!(
      last_run_at: Time.current,
      next_run_at: calculate_next_run(task.cron_schedule)
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
        duration_seconds: params[:duration_seconds],
        output: params[:output],
        result: params[:result]
      )
    when "failed"
      execution.update!(
        status: "failed",
        completed_at: Time.current,
        duration_seconds: params[:duration_seconds],
        error_message: params[:error_message],
        error_details: params[:error_details]
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
    rescue => e
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

  def authenticate_service_token
    token = request.headers["Authorization"]&.split(" ")&.last

    unless token.present?
      render_error("Service token required", status: :unauthorized)
      return
    end

    begin
      payload = JWT.decode(token, Rails.application.config.jwt_secret_key, true, algorithm: "HS256").first

      unless payload["service"] == "worker" && payload["type"] == "service"
        render_error("Invalid service token", status: :unauthorized)
        nil
      end

    rescue JWT::DecodeError, JWT::ExpiredSignature
      render_error("Invalid service token", status: :unauthorized)
    end
  end

  def backup_update_params
    params.permit(
      :status, :file_path, :file_size, :duration_seconds,
      :error_message, :checksum, :started_at, :completed_at
    )
  end

  def restore_update_params
    params.permit(
      :status, :duration_seconds, :tables_restored, :rows_restored,
      :error_message, :started_at, :completed_at
    )
  end

  def execution_update_params
    params.permit(
      :status, :duration_seconds, :output, :result,
      :error_message, :error_details, :completed_at
    )
  end

  def calculate_next_run(cron_expression)
    # Use the fugit gem to parse cron expressions
    cron = Fugit::Cron.parse(cron_expression)
    cron&.next_time&.to_t || 1.day.from_now
  rescue => e
    Rails.logger.error "Failed to parse cron expression: #{e.message}"
    1.day.from_now
  end
end
