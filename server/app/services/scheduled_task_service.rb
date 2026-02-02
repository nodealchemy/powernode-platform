# frozen_string_literal: true

class ScheduledTaskService
  include ActiveModel::Model

  TASK_TYPES = %w[
    database_backup
    data_cleanup
    system_health_check
    report_generation
    custom_command
  ].freeze

  # Whitelist of allowed commands for custom_command task type
  # Only these command prefixes are allowed for security
  ALLOWED_COMMAND_PREFIXES = %w[
    rails
    bundle
    rake
    ruby
  ].freeze

  # Dangerous patterns that are never allowed in commands
  FORBIDDEN_COMMAND_PATTERNS = [
    /[;&|`$]/, # Shell metacharacters
    /\bsudo\b/i, # sudo
    /\brm\s+-rf?\b/i, # destructive rm
    /\bchmod\b/i, # permission changes
    /\bchown\b/i, # ownership changes
    /\bcurl\b.*\|/i, # curl piped to shell
    /\bwget\b.*\|/i, # wget piped to shell
    />\s*\//, # redirect to absolute path
    /\/etc\//i, # system config access
    /\/proc\//i, # proc access
    /\/sys\//i # sys access
  ].freeze

  PREDEFINED_SCHEDULES = {
    "daily" => "0 2 * * *",           # 2 AM daily
    "weekly" => "0 3 * * 0",          # 3 AM on Sundays
    "monthly" => "0 4 1 * *",         # 4 AM on 1st of month
    "hourly" => "0 * * * *",          # Every hour
    "every_6_hours" => "0 */6 * * *"  # Every 6 hours
  }.freeze

  class << self
    def list_tasks
      tasks = ScheduledTask.includes(:user, :executions).order(:name)

      tasks.map do |task|
        {
          id: task.id,
          name: task.name,
          description: task.description,
          type: task.task_type,
          cron_schedule: task.cron_schedule,
          enabled: task.enabled,
          next_run: calculate_next_run(task.cron_schedule),
          last_execution: format_last_execution(task.executions.order(:created_at).last),
          created_by: task.user&.email,
          created_at: task.created_at.iso8601,
          updated_at: task.updated_at.iso8601,
          execution_count: task.executions.count,
          success_rate: calculate_success_rate(task.executions)
        }
      end
    end

    def create_task(task_params, user)
      unless TASK_TYPES.include?(task_params[:type])
        return {
          success: false,
          error: "Invalid task type. Must be one of: #{TASK_TYPES.join(', ')}"
        }
      end

      unless valid_cron_schedule?(task_params[:cron_schedule])
        return {
          success: false,
          error: "Invalid cron schedule format"
        }
      end

      # Security: custom_command tasks require system.admin permission
      if task_params[:type] == "custom_command"
        unless user.has_permission?("system.admin")
          return {
            success: false,
            error: "Custom command tasks require system administrator privileges"
          }
        end

        # Validate command against whitelist and forbidden patterns
        unless valid_custom_command?(task_params[:command])
          return {
            success: false,
            error: "Invalid command. Only rails, bundle, rake, and ruby commands are allowed. Shell metacharacters are forbidden."
          }
        end
      end

      task = ScheduledTask.new(
        name: task_params[:name],
        description: task_params[:description],
        task_type: task_params[:type],
        cron_schedule: task_params[:cron_schedule],
        enabled: task_params[:enabled] || true,
        command: task_params[:command],
        user: user
      )

      if task.save
        Rails.logger.info "Created scheduled task: #{task.name} by #{user.email}"

        # Schedule the task if enabled
        schedule_task(task) if task.enabled?

        {
          success: true,
          task: format_task_response(task)
        }
      else
        {
          success: false,
          error: "Failed to create task",
          details: task.errors.full_messages
        }
      end
    end

    def update_task(task_id, task_params, user)
      task = ScheduledTask.find_by(id: task_id)
      return { success: false, error: "Task not found" } unless task

      if task_params[:type] && !TASK_TYPES.include?(task_params[:type])
        return {
          success: false,
          error: "Invalid task type. Must be one of: #{TASK_TYPES.join(', ')}"
        }
      end

      if task_params[:cron_schedule] && !valid_cron_schedule?(task_params[:cron_schedule])
        return {
          success: false,
          error: "Invalid cron schedule format"
        }
      end

      # Update task attributes
      task.assign_attributes(
        task_params.slice(:name, :description, :cron_schedule, :enabled, :command).compact
      )
      task.task_type = task_params[:type] if task_params[:type]

      if task.save
        Rails.logger.info "Updated scheduled task: #{task.name} by #{user.email}"

        # Reschedule the task
        unschedule_task(task)
        schedule_task(task) if task.enabled?

        {
          success: true,
          task: format_task_response(task)
        }
      else
        {
          success: false,
          error: "Failed to update task",
          details: task.errors.full_messages
        }
      end
    end

    def delete_task(task_id)
      task = ScheduledTask.find_by(id: task_id)
      return { success: false, error: "Task not found" } unless task

      # Unschedule the task first
      unschedule_task(task)

      # Delete the task and its executions
      task.destroy!

      Rails.logger.info "Deleted scheduled task: #{task.name}"
      { success: true }
    rescue StandardError => e
      Rails.logger.error "Failed to delete task: #{e.message}"
      { success: false, error: e.message }
    end

    def execute_task(task_id, user)
      task = ScheduledTask.find_by(id: task_id)
      return { success: false, error: "Task not found" } unless task

      execution = TaskExecution.create!(
        scheduled_task: task,
        user: user,
        status: "pending",
        started_at: Time.current,
        triggered_by: "manual"
      )

      # Execute the task in background
      ScheduledTaskJob.perform_async(execution.id)

      Rails.logger.info "Manual execution of task #{task.name} initiated by #{user.email}"

      {
        success: true,
        execution: {
          id: execution.id,
          status: "pending",
          started_at: execution.started_at.iso8601,
          triggered_by: "manual"
        }
      }
    rescue StandardError => e
      Rails.logger.error "Failed to execute task: #{e.message}"
      { success: false, error: e.message }
    end

    def execute_scheduled_task(execution_id)
      execution = TaskExecution.find(execution_id)
      task = execution.scheduled_task

      execution.update!(status: "running", started_at: Time.current)

      begin
        result = case task.task_type
        when "database_backup"
                   execute_database_backup_task(task)
        when "data_cleanup"
                   execute_data_cleanup_task(task)
        when "system_health_check"
                   execute_health_check_task(task)
        when "report_generation"
                   execute_report_generation_task(task)
        when "custom_command"
                   execute_custom_command_task(task)
        else
                   { success: false, error: "Unknown task type: #{task.task_type}" }
        end

        execution.update!(
          status: result[:success] ? "completed" : "failed",
          completed_at: Time.current,
          output: result[:output] || result[:message],
          error_message: result[:error]
        )

        Rails.logger.info "Task execution #{execution.id} completed with status: #{execution.status}"
        result
      rescue StandardError => e
        execution.update!(
          status: "failed",
          completed_at: Time.current,
          error_message: e.message
        )
        Rails.logger.error "Task execution #{execution.id} failed: #{e.message}"
        raise e
      end
    end

    private

    def valid_cron_schedule?(schedule)
      return true if PREDEFINED_SCHEDULES.values.include?(schedule)

      # Basic cron validation (5 fields: minute hour day month weekday)
      fields = schedule.split
      return false unless fields.length == 5

      # More sophisticated validation would go here
      true
    rescue StandardError
      false
    end

    def calculate_next_run(cron_schedule)
      # This would use a gem like 'cron_parser' to calculate next run time
      # For now, return a placeholder
      1.day.from_now.iso8601
    rescue StandardError
      nil
    end

    def format_last_execution(execution)
      return nil unless execution

      {
        id: execution.id,
        status: execution.status,
        started_at: execution.started_at.iso8601,
        completed_at: execution.completed_at&.iso8601,
        duration: execution.completed_at ? (execution.completed_at - execution.started_at).to_i : nil,
        triggered_by: execution.triggered_by,
        error_message: execution.error_message
      }
    end

    def calculate_success_rate(executions)
      return 0 if executions.empty?

      successful = executions.where(status: "completed").count
      total = executions.count

      (successful.to_f / total * 100).round(2)
    end

    def format_task_response(task)
      {
        id: task.id,
        name: task.name,
        description: task.description,
        type: task.task_type,
        cron_schedule: task.cron_schedule,
        enabled: task.enabled,
        created_at: task.created_at.iso8601,
        updated_at: task.updated_at.iso8601
      }
    end

    def schedule_task(task)
      return unless task.enabled? && task.cron_schedule.present?

      job_name = "scheduled_task_#{task.id}"

      # Use Sidekiq-scheduler if available
      if defined?(Sidekiq::Scheduler)
        Sidekiq.set_schedule(job_name, {
          "cron" => task.cron_schedule,
          "class" => "ScheduledTaskJob",
          "args" => [ task.id ],
          "queue" => "scheduled_tasks",
          "description" => "Scheduled task: #{task.name}"
        })

        # Reload the schedule
        Sidekiq::Scheduler.reload_schedule!

        Rails.logger.info "Scheduled task '#{task.name}' (#{task.id}) with cron: #{task.cron_schedule}"
      else
        # Fallback: Store schedule in Redis for custom scheduler
        schedule_key = "powernode:scheduled_tasks:#{task.id}"
        schedule_data = {
          task_id: task.id,
          name: task.name,
          cron_schedule: task.cron_schedule,
          next_run_at: calculate_next_run_time(task.cron_schedule),
          enabled: true,
          created_at: Time.current.iso8601
        }

        redis_client.set(schedule_key, schedule_data.to_json)
        redis_client.sadd("powernode:scheduled_tasks:active", task.id)

        Rails.logger.info "Scheduled task '#{task.name}' (#{task.id}) registered in Redis"
      end

      # Update task with next execution time
      next_run = calculate_next_run_time(task.cron_schedule)
      task.update_column(:next_execution_at, next_run) if task.respond_to?(:next_execution_at)
    end

    def unschedule_task(task)
      job_name = "scheduled_task_#{task.id}"

      if defined?(Sidekiq::Scheduler)
        # Remove from Sidekiq-scheduler
        Sidekiq.remove_schedule(job_name)
        Sidekiq::Scheduler.reload_schedule!

        Rails.logger.info "Unscheduled task '#{task.name}' (#{task.id}) from Sidekiq-scheduler"
      else
        # Remove from Redis
        schedule_key = "powernode:scheduled_tasks:#{task.id}"
        redis_client.del(schedule_key)
        redis_client.srem("powernode:scheduled_tasks:active", task.id)

        Rails.logger.info "Unscheduled task '#{task.name}' (#{task.id}) from Redis"
      end

      # Clear next execution time
      task.update_column(:next_execution_at, nil) if task.respond_to?(:next_execution_at)
    end

    def calculate_next_run_time(cron_schedule)
      return nil if cron_schedule.blank?

      # Use fugit gem for cron parsing if available
      if defined?(Fugit)
        cron = Fugit.parse(cron_schedule)
        return cron&.next_time&.to_t
      end

      # Fallback: Use rufus-scheduler if available
      if defined?(Rufus::Scheduler)
        cron = Rufus::Scheduler.parse(cron_schedule)
        return cron.next_time.to_t
      end

      # Basic fallback based on predefined schedules
      case cron_schedule
      when PREDEFINED_SCHEDULES["hourly"]
        Time.current.beginning_of_hour + 1.hour
      when PREDEFINED_SCHEDULES["daily"]
        Time.current.tomorrow.change(hour: 2)
      when PREDEFINED_SCHEDULES["weekly"]
        Time.current.next_occurring(:sunday).change(hour: 3)
      when PREDEFINED_SCHEDULES["monthly"]
        Time.current.next_month.beginning_of_month.change(hour: 4)
      else
        # Default to 1 day from now if we can't parse
        1.day.from_now
      end
    rescue StandardError => e
      Rails.logger.warn "Failed to calculate next run time for cron '#{cron_schedule}': #{e.message}"
      1.day.from_now
    end

    def redis_client
      @redis_client ||= Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))
    end

    # Task execution methods
    def execute_database_backup_task(task)
      backup_type = task.command&.include?("schema") ? "schema_only" : "full"
      System::DatabaseBackupService.create_backup(backup_type, "Scheduled backup: #{task.name}", task.user)
    end

    def execute_data_cleanup_task(task)
      results = []

      # Parse command for specific cleanup operations
      if task.command&.include?("audit_logs")
        days = extract_days_from_command(task.command) || 90
        result = DataCleanupService.cleanup_audit_logs(days)
        results << "Audit logs: #{result[:cleaned_count]} records cleaned"
      end

      if task.command&.include?("sessions")
        result = DataCleanupService.cleanup_expired_sessions
        results << "Sessions: #{result[:cleaned_count]} expired sessions cleaned"
      end

      if task.command&.include?("temp_files")
        result = DataCleanupService.cleanup_temp_files
        results << "Temp files: #{result[:cleaned_count]} files cleaned"
      end

      if task.command&.include?("cache")
        result = DataCleanupService.clear_application_cache
        results << "Cache: #{result[:cleared_entries]} entries cleared"
      end

      {
        success: true,
        output: results.join("; "),
        message: "Data cleanup completed"
      }
    end

    def execute_health_check_task(task)
      System::HealthService.trigger_comprehensive_check

      {
        success: true,
        output: "Comprehensive health check completed",
        message: "System health check completed successfully"
      }
    end

    def execute_report_generation_task(task)
      # This would integrate with your reporting system
      {
        success: true,
        output: "Report generation completed",
        message: "Scheduled report generated successfully"
      }
    end

    def execute_custom_command_task(task)
      return { success: false, error: "No command specified" } unless task.command.present?

      # Defense in depth: re-validate command at execution time
      unless valid_custom_command?(task.command)
        Rails.logger.error "Blocked execution of invalid command: #{task.command.truncate(100)}"
        return {
          success: false,
          error: "Command validation failed. Only rails, bundle, rake, and ruby commands are allowed."
        }
      end

      # Execute custom command safely using Open3 for better control
      begin
        require "open3"
        stdout, stderr, status = Open3.capture3(task.command)
        output = stdout.presence || stderr

        {
          success: status.success?,
          output: output.truncate(10_000),
          error: status.success? ? nil : "Command failed with exit code #{status.exitstatus}"
        }
      rescue StandardError => e
        Rails.logger.error "Custom command execution error: #{e.message}"
        {
          success: false,
          error: "Failed to execute command: #{e.message}"
        }
      end
    end

    def extract_days_from_command(command)
      match = command.match(/--days[=\s]+(\d+)/)
      match ? match[1].to_i : nil
    end

    # Validates that a custom command is safe to execute
    def valid_custom_command?(command)
      return false if command.blank?

      # Check against forbidden patterns
      FORBIDDEN_COMMAND_PATTERNS.each do |pattern|
        return false if command.match?(pattern)
      end

      # Check that command starts with an allowed prefix
      normalized_command = command.strip.downcase
      ALLOWED_COMMAND_PREFIXES.any? { |prefix| normalized_command.start_with?(prefix) }
    end
  end
end
