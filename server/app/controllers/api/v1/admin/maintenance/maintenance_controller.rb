# frozen_string_literal: true

class Api::V1::Admin::Maintenance::MaintenanceController < ApplicationController
  include Authentication

  before_action :require_admin_maintenance_permission

  # Maintenance Mode endpoints
  def show_mode
    render_success({

        enabled: maintenance_mode_enabled?,
        message: safe_config(:maintenance_message) || "System is under maintenance",
        enabled_at: safe_config(:maintenance_enabled_at),
        estimated_completion: safe_config(:maintenance_estimated_completion),
        bypass_ips: safe_config(:maintenance_bypass_ips) || []
      }
    )
  end

  def update_mode
    enabled = params[:enabled]
    message = params[:message] || "System is under maintenance"
    estimated_completion = params[:estimated_completion]
    bypass_ips = params[:bypass_ips] || []

    if enabled
      enable_maintenance_mode(message, estimated_completion, bypass_ips)
      Rails.logger.info "Maintenance mode ENABLED by #{current_user.email}"
    else
      disable_maintenance_mode
      Rails.logger.info "Maintenance mode DISABLED by #{current_user.email}"
    end

    render_success({

        enabled: enabled,
        message: message,
        estimated_completion: estimated_completion
      },
      message: enabled ? "Maintenance mode enabled" : "Maintenance mode disabled"
    )
  end

  # Data Cleanup endpoints
  def cleanup_stats
    stats = DataCleanupService.get_cleanup_stats

    render_success(stats)
  end

  def cleanup_audit_logs
    days_old = params[:days_old] || 90
    result = DataCleanupService.cleanup_audit_logs(days_old.to_i)

    render_success(
      data: result,
      message: "Audit logs cleanup completed"
    )
  end

  def cleanup_sessions
    result = DataCleanupService.cleanup_expired_sessions

    render_success(
      data: result,
      message: "Expired sessions cleanup completed"
    )
  end

  def cleanup_temp_files
    result = DataCleanupService.cleanup_temp_files

    render_success(
      data: result,
      message: "Temporary files cleanup completed"
    )
  end

  def clear_cache
    result = DataCleanupService.clear_application_cache

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

  # Status endpoint
  def status
    render_success({

        maintenance_mode: maintenance_mode_enabled?,
        database_status: check_database_status,
        redis_status: check_redis_status,
        sidekiq_status: check_sidekiq_status,
        last_backup: get_last_backup_info,
        system_uptime: get_system_uptime
      }
    )
  end

  # Health endpoint
  def health
    health_check = {
      database: check_database_health,
      redis: check_redis_health,
      sidekiq: check_sidekiq_health,
      disk_space: check_disk_space,
      memory_usage: check_memory_usage,
      cpu_usage: check_cpu_usage
    }

    overall_status = health_check.values.all? { |v| v[:status] == "healthy" } ? "healthy" : "degraded"

    render_success({

        overall_status: overall_status,
        checks: health_check,
        timestamp: Time.current
      }
    )
  end

  # Metrics endpoint
  def metrics
    render_success({

        database: {
          total_records: get_total_records_count,
          connections: ActiveRecord::Base.connection_pool.stat
        },
        cache: {
          size: begin
            Rails.cache.stats
          rescue StandardError
            nil
          end
        },
        background_jobs: {
          processed: get_processed_jobs_count,
          failed: get_failed_jobs_count,
          pending: get_pending_jobs_count
        },
        storage: {
          uploads_size: calculate_uploads_size,
          logs_size: calculate_logs_size,
          cache_size: calculate_cache_size
        }
      }
    )
  end

  # Backups endpoint
  def backups
    backups = Database::Backup.order(created_at: :desc).limit(20)

    render_success(
      data: backups.map { |backup|
        {
          id: backup.id,
          name: backup.name,
          size: backup.size,
          status: backup.status,
          created_at: backup.created_at,
          completed_at: backup.completed_at,
          location: backup.location
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

  def require_permission
    require_any_permission("admin.maintenance.mode", "admin.maintenance.backup", "admin.maintenance.restore", "admin.maintenance.cleanup", "admin.maintenance.tasks", "system.admin")
  end

  def require_health_permission
    require_any_permission("admin.maintenance.mode", "admin.maintenance.backup", "system.admin")
  end

  def maintenance_mode_enabled?
    Rails.application.config.respond_to?(:maintenance_mode) &&
    Rails.application.config.maintenance_mode == true
  end

  def enable_maintenance_mode(message, estimated_completion, bypass_ips)
    Rails.application.config.maintenance_mode = true
    Rails.application.config.maintenance_message = message
    Rails.application.config.maintenance_enabled_at = Time.current
    Rails.application.config.maintenance_estimated_completion = estimated_completion
    Rails.application.config.maintenance_bypass_ips = bypass_ips

    # Write maintenance file for web server
    write_maintenance_file(message, estimated_completion)

    # Log maintenance mode activation
    AuditLog.create!(
      user: current_user,
      account: current_account,
      action: "maintenance_mode_enabled",
      resource_type: "System",
      resource_id: "system",
      source: "admin_panel",
      ip_address: request.remote_ip,
      metadata: {
        message: message,
        estimated_completion: estimated_completion,
        bypass_ips: bypass_ips
      }
    )
  end

  def disable_maintenance_mode
    Rails.application.config.maintenance_mode = false
    Rails.application.config.maintenance_message = nil
    Rails.application.config.maintenance_enabled_at = nil
    Rails.application.config.maintenance_estimated_completion = nil
    Rails.application.config.maintenance_bypass_ips = nil

    # Remove maintenance file
    remove_maintenance_file

    # Log maintenance mode deactivation
    AuditLog.create!(
      user: current_user,
      account: current_account,
      action: "maintenance_mode_disabled",
      resource_type: "System",
      resource_id: "system",
      source: "admin_panel",
      ip_address: request.remote_ip,
      metadata: {}
    )
  end

  def write_maintenance_file(message, estimated_completion)
    maintenance_file = Rails.root.join("public", "maintenance.html")
    content = generate_maintenance_page_content(message, estimated_completion)
    File.write(maintenance_file, content)
  end

  def remove_maintenance_file
    maintenance_file = Rails.root.join("public", "maintenance.html")
    File.delete(maintenance_file) if File.exist?(maintenance_file)
  end

  def generate_maintenance_page_content(message, estimated_completion)
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <title>Powernode - Under Maintenance</title>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          body { font-family: Arial, sans-serif; margin: 0; padding: 40px; background: #f5f5f5; color: #333; }
          .container { max-width: 600px; margin: 0 auto; background: white; padding: 40px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); text-align: center; }
          h1 { color: #e74c3c; margin-bottom: 20px; }
          .icon { font-size: 48px; margin-bottom: 20px; }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="icon">🔧</div>
          <h1>System Under Maintenance</h1>
          <p>#{message}</p>
          #{estimated_completion ? "<p><strong>Estimated completion:</strong> #{estimated_completion}</p>" : ""}
          <p>We apologize for any inconvenience. Please check back shortly.</p>
        </div>
      </body>
      </html>
    HTML
  end

  # Helper methods for status checks
  def check_database_status
    ActiveRecord::Base.connection.active? ? "connected" : "disconnected"
  rescue StandardError => e
    Rails.logger.error "Database status check failed: #{e.message}"
    "error"
  end

  def check_redis_status
    Redis.current.ping == "PONG" ? "connected" : "disconnected"
  rescue StandardError => e
    Rails.logger.error "Redis status check failed: #{e.message}"
    "unavailable"
  end

  def check_sidekiq_status
    Sidekiq::Stats.new.processes_size > 0 ? "running" : "stopped"
  rescue StandardError => e
    Rails.logger.error "Sidekiq status check failed: #{e.message}"
    "unavailable"
  end

  def get_last_backup_info
    backup = Database::Backup.order(created_at: :desc).first
    backup ? { created_at: backup.created_at, size: backup.size } : nil
  rescue StandardError => e
    Rails.logger.error "Failed to get last backup info: #{e.message}"
    nil
  end

  def get_system_uptime
    uptime_seconds = Time.current - Rails.application.config.booted_at rescue 0
    {
      seconds: uptime_seconds,
      formatted: format_duration(uptime_seconds)
    }
  end

  def check_database_health
    start = Time.current
    ActiveRecord::Base.connection.execute("SELECT 1")
    response_time = ((Time.current - start) * 1000).round(2)

    { status: "healthy", response_time_ms: response_time }
  rescue StandardError => e
    { status: "unhealthy", error: e.message }
  end

  def check_redis_health
    start = Time.current
    Redis.current.ping
    response_time = ((Time.current - start) * 1000).round(2)

    { status: "healthy", response_time_ms: response_time }
  rescue StandardError => e
    { status: "unhealthy", error: e.message }
  end

  def check_sidekiq_health
    stats = Sidekiq::Stats.new
    {
      status: "healthy",
      processed: stats.processed,
      failed: stats.failed,
      queues: stats.queues
    }
  rescue StandardError => e
    { status: "unhealthy", error: e.message }
  end

  def check_disk_space
    stat = Sys::Filesystem.stat("/")
    used_percentage = ((1 - (stat.bytes_free.to_f / stat.bytes_total)) * 100).round(2)

    {
      status: used_percentage < 80 ? "healthy" : "warning",
      used_percentage: used_percentage,
      free_gb: (stat.bytes_free / 1.gigabyte).round(2)
    }
  rescue StandardError => e
    Rails.logger.error "Disk space check failed: #{e.message}"
    { status: "unknown" }
  end

  def check_memory_usage
    memory_info = `free -m`.split("\n")[1].split
    total = memory_info[1].to_f
    used = memory_info[2].to_f
    used_percentage = ((used / total) * 100).round(2)

    {
      status: used_percentage < 80 ? "healthy" : "warning",
      used_percentage: used_percentage,
      used_mb: used.round,
      total_mb: total.round
    }
  rescue StandardError => e
    Rails.logger.error "Memory usage check failed: #{e.message}"
    { status: "unknown" }
  end

  def check_cpu_usage
    load_average = `uptime`.match(/load average: ([\d.]+), ([\d.]+), ([\d.]+)/)
    if load_average
      one_min = load_average[1].to_f
      {
        status: one_min < 2.0 ? "healthy" : "warning",
        load_1min: one_min,
        load_5min: load_average[2].to_f,
        load_15min: load_average[3].to_f
      }
    else
      { status: "unknown" }
    end
  rescue StandardError => e
    Rails.logger.error "CPU usage check failed: #{e.message}"
    { status: "unknown" }
  end

  def get_total_records_count
    {
      users: User.count,
      accounts: Account.count,
      subscriptions: (defined?(Billing::Subscription) ? Billing::Subscription.count : 0),
      payments: (defined?(Billing::Payment) ? Billing::Payment.count : 0)
    }
  rescue StandardError => e
    Rails.logger.error "Failed to get total records count: #{e.message}"
    {}
  end

  def get_processed_jobs_count
    Sidekiq::Stats.new.processed rescue 0
  end

  def get_failed_jobs_count
    Sidekiq::Stats.new.failed rescue 0
  end

  def get_pending_jobs_count
    Sidekiq::Stats.new.enqueued rescue 0
  end

  def calculate_uploads_size
    Dir.glob(Rails.root.join("storage", "**", "*")).sum { |f| File.size(f) if File.file?(f) }.to_i / 1.megabyte rescue 0
  end

  def calculate_logs_size
    Dir.glob(Rails.root.join("log", "**", "*.log")).sum { |f| File.size(f) }.to_i / 1.megabyte rescue 0
  end

  def calculate_cache_size
    Dir.glob(Rails.root.join("tmp", "cache", "**", "*")).sum { |f| File.size(f) if File.file?(f) }.to_i / 1.megabyte rescue 0
  end

  def format_duration(seconds)
    days = (seconds / 86400).to_i
    hours = ((seconds % 86400) / 3600).to_i
    minutes = ((seconds % 3600) / 60).to_i

    parts = []
    parts << "#{days}d" if days > 0
    parts << "#{hours}h" if hours > 0
    parts << "#{minutes}m" if minutes > 0 || parts.empty?

    parts.join(" ")
  end

  def safe_config(key)
    Rails.application.config.respond_to?(key) ? Rails.application.config.send(key) : nil
  end
end
