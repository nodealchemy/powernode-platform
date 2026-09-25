# frozen_string_literal: true

class Api::V1::Admin::Maintenance::MaintenanceController < ApplicationController
  include Authentication

  before_action :require_admin_maintenance_permission
  # Narrower than the controller-wide gate above: a backup/cleanup/restore/
  # tasks-only holder can reach cleanup_stats etc, but must NOT be able to
  # enable maintenance mode (and then have no permission left to disable it —
  # admin.maintenance.mode is the one EXEMPT_PERMISSIONS entry that exists
  # specifically so its holder can't lock itself out, see Admin::MaintenanceMode).
  before_action :require_maintenance_mode_permission, only: %i[show_mode update_mode update_fields]

  # Maintenance Mode endpoints
  def show_mode
    render_success(Admin::MaintenanceMode.status)
  end

  def update_mode
    return render_error("enabled is required", status: :bad_request) unless params.key?(:enabled)

    enabled = ActiveModel::Type::Boolean.new.cast(params[:enabled])
    status = nil

    # State + audit row in one transaction: a failed audit write must not
    # leave maintenance mode silently toggled with no record of who did it
    # or why, and a failed state write must not log an audit row for a
    # change that never actually took effect.
    ActiveRecord::Base.transaction do
      if enabled
        status = Admin::MaintenanceMode.enable!(
          message: params[:message],
          estimated_completion: params[:estimated_completion],
          bypass_ips: params[:bypass_ips] || []
        )
        Rails.logger.info "Maintenance mode ENABLED by #{current_user.email}"
        audit_maintenance_change("maintenance_mode_enabled", status)
      else
        status = Admin::MaintenanceMode.disable!
        Rails.logger.info "Maintenance mode DISABLED by #{current_user.email}"
        audit_maintenance_change("maintenance_mode_disabled", status)
      end
    end

    render_success(status, message: status[:enabled] ? "Maintenance mode enabled" : "Maintenance mode disabled")
  rescue Admin::MaintenanceMode::InvalidBypassIp => e
    render_error(e.message, status: :unprocessable_content)
  end

  # PATCH /admin/maintenance/mode — updates message/estimated_completion/
  # bypass_ips WITHOUT toggling `enabled`. Separate action (and separate
  # verb) from update_mode's POST specifically so the Mode tab's Save button
  # can persist an edit made while maintenance is OFF (staging a message
  # before turning it on) or ON (editing without resetting enabled_at) —
  # see Admin::MaintenanceMode.update_fields! for the two regressions this
  # split fixes.
  def update_fields
    status = nil
    # Only forward keys ACTUALLY PRESENT in the request — Admin::MaintenanceMode
    # .update_fields! defaults every keyword to UNSET, so a key this hash
    # never mentions is left completely untouched. Without this, a
    # message-only PATCH (e.g. bypass_ips simply not sent) would previously
    # wipe bypass_ips back to [] and the ETA back to nil.
    updates = {}
    updates[:message] = params[:message] if params.key?(:message)
    updates[:estimated_completion] = params[:estimated_completion] if params.key?(:estimated_completion)
    updates[:bypass_ips] = params[:bypass_ips] if params.key?(:bypass_ips)

    ActiveRecord::Base.transaction do
      status = Admin::MaintenanceMode.update_fields!(**updates)
      Rails.logger.info "Maintenance mode settings updated by #{current_user.email}"
      audit_maintenance_change("maintenance_mode_updated", status)
    end

    render_success(status, message: "Maintenance settings updated")
  rescue Admin::MaintenanceMode::InvalidBypassIp => e
    render_error(e.message, status: :unprocessable_content)
  end

  # Data Cleanup endpoints
  def cleanup_stats
    stats = DataManagement::CleanupService.get_cleanup_stats

    render_success(stats)
  end

  def cleanup_audit_logs
    days_old = params[:days_old] || 90
    result = DataManagement::CleanupService.cleanup_audit_logs(days_old.to_i)

    render_success(
      data: result,
      message: "Audit logs cleanup completed"
    )
  end

  def cleanup_sessions
    result = DataManagement::CleanupService.cleanup_expired_sessions

    render_success(
      data: result,
      message: "Expired sessions cleanup completed"
    )
  end

  def cleanup_temp_files
    result = DataManagement::CleanupService.cleanup_temp_files

    render_success(
      data: result,
      message: "Temporary files cleanup completed"
    )
  end

  def clear_cache
    result = DataManagement::CleanupService.clear_application_cache

    render_success(
      data: result,
      message: "Application cache cleared"
    )
  end

  # Scheduled Tasks endpoints
  def list_tasks
    tasks = ScheduledTaskService.list_tasks

    render_success(tasks)
  end

  def create_task
    task_params = params.require(:task).permit(:name, :description, :cron_schedule, :enabled, :command, :type)
    result = ScheduledTaskService.create_task(task_params, current_user)

    if result[:success]
      render_success(
        data: result[:task],
        message: "Scheduled task created"
      )
    else
      render_error(
        result[:error],
        :unprocessable_content,
        details: result[:details]
      )
    end
  end

  def update_task
    task_id = params[:id]
    task_params = params.require(:task).permit(:name, :description, :cron_schedule, :enabled, :command, :type)
    result = ScheduledTaskService.update_task(task_id, task_params, current_user)

    if result[:success]
      render_success(
        data: result[:task],
        message: "Scheduled task updated"
      )
    else
      render_error(
        result[:error],
        :unprocessable_content,
        details: result[:details]
      )
    end
  end

  def delete_task
    task_id = params[:id]
    result = ScheduledTaskService.delete_task(task_id)

    if result[:success]
      render_success(message: "Scheduled task deleted")
    else
      render_error(result[:error], status: :unprocessable_content)
    end
  end

  def execute_task
    task_id = params[:id]
    result = ScheduledTaskService.execute_task(task_id, current_user)

    if result[:success]
      render_success(
        data: result[:execution],
        message: "Task execution initiated"
      )
    else
      render_error(result[:error], status: :unprocessable_content)
    end
  end

  # Health endpoint
  def health
    # The one set of core checks (Platform::Health::CoreChecks), under the
    # key names this endpoint has always used.
    checks = ::Platform::Health::CoreChecks.all
    health_check = {
      database: checks[:database],
      redis: checks[:redis],
      sidekiq: checks[:sidekiq],
      disk_space: checks[:disk],
      memory_usage: checks[:memory],
      cpu_usage: checks[:cpu]
    }

    overall_status = health_check.values.all? { |v| v[:status] == "healthy" } ? "healthy" : "degraded"

    render_success({

        overall_status: overall_status,
        checks: health_check,
        timestamp: Time.current
      }
    )
  end

  # Backups endpoint
  # IMP-8b25fb48368e: `.name` / `.size` / `.location` are neither columns nor
  # model methods on Database::Backup (schema: backup_type, description,
  # file_path, file_size_bytes, status, started_at, completed_at, ...) — this
  # raised NoMethodError -> 503 on every non-empty result, latent only because
  # the table was always empty before the worker's create_backup path was
  # reachable. Mapped to the real columns rather than fabricated; no rename to
  # the frontend's `filename`/`type` naming, since that's a wider, separate
  # contract question (see report).
  def backups
    backups = Database::Backup.order(created_at: :desc).limit(20)

    render_success(
      data: backups.map { |backup|
        {
          id: backup.id,
          name: backup.description,
          size: backup.file_size_bytes,
          status: backup.status,
          created_at: backup.created_at,
          completed_at: backup.completed_at,
          location: backup.file_path
        }
      }
    )
  rescue StandardError => e
    Rails.logger.error "Database backups unavailable: #{e.message}"
    render_error("Unable to retrieve database backups", status: :service_unavailable)
  end

  # Schedules endpoint
  def schedules
    schedules = ScheduledTask.where(task_type: "maintenance").order(:name)

    render_success(
      data: schedules.map { |schedule|
        {
          id: schedule.id,
          name: schedule.name,
          cron: schedule.cron_expression,
          enabled: schedule.enabled?,
          last_run: schedule.last_run_at,
          next_run: schedule.next_run_at
        }
      }
    )
  rescue StandardError => e
    Rails.logger.error "Scheduled tasks unavailable: #{e.message}"
    render_error("Unable to retrieve scheduled tasks", status: :service_unavailable)
  end

  private

  def require_admin_maintenance_permission
    unless current_user&.has_any_permission?("admin.maintenance.mode", "admin.maintenance.backup", "admin.maintenance.restore", "admin.maintenance.cleanup", "admin.maintenance.tasks", "system.admin")
      render_error("Permission denied: requires admin maintenance permissions", status: :forbidden)
    end
  end

  def require_maintenance_mode_permission
    unless current_user&.has_any_permission?("admin.maintenance.mode", "system.admin")
      render_error("Permission denied: requires admin.maintenance.mode or system.admin", status: :forbidden)
    end
  end

  def require_permission
    require_any_permission("admin.maintenance.mode", "admin.maintenance.backup", "admin.maintenance.restore", "admin.maintenance.cleanup", "admin.maintenance.tasks", "system.admin")
  end

  def require_health_permission
    require_any_permission("admin.maintenance.mode", "admin.maintenance.backup", "system.admin")
  end

  # Audit-logs every maintenance-mode change (Admin::MaintenanceMode itself
  # is pure store logic with no request/current_user context). Action names
  # ("maintenance_mode_enabled"/"maintenance_mode_disabled") are unchanged
  # from the prior config-based implementation for audit-trail continuity.
  def audit_maintenance_change(action, status)
    AuditLog.create!(
      user: current_user,
      account: current_account,
      action: action,
      resource_type: "System",
      resource_id: "system",
      source: "admin_panel",
      ip_address: request.remote_ip,
      metadata: status.slice(:message, :estimated_completion, :bypass_ips)
    )
  end
end
