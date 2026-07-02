# frozen_string_literal: true

class ScheduledTaskService
  include ActiveModel::Model

  TASK_TYPES = %w[
    data_cleanup
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
      tasks = ScheduledTask.includes(:task_executions).order(:name)

      tasks.map do |task|
        # Sort/count/filter the eager-loaded association in Ruby so the
        # includes above actually saves queries rather than re-querying per row.
        executions = task.task_executions.sort_by(&:created_at)
        {
          id: task.id,
          name: task.name,
          description: task.parameters&.dig("description"),
          type: task.task_type,
          cron_schedule: task.cron_expression,
          enabled: task.enabled?,
          command: task.parameters&.dig("command"),
          next_run: task.next_run_at&.iso8601,
          last_execution: format_last_execution(executions.last),
          # scheduled_tasks has no creator association/column
          created_by: nil,
          created_at: task.created_at.iso8601,
          updated_at: task.updated_at.iso8601,
          execution_count: executions.size,
          success_rate: calculate_success_rate(executions)
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

      # Map admin params onto the real schema: name / task_type / cron_expression /
      # is_active columns, with description and command living inside the
      # `parameters` jsonb (the shape the worker-facing controller and Sidekiq
      # executor already read — command at parameters["command"]).
      task = ScheduledTask.new(
        name: task_params[:name],
        task_type: task_params[:type],
        cron_expression: task_params[:cron_schedule],
        is_active: enabled_from(task_params),
        parameters: merge_task_parameters({}, task_params)
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

      # Security: editing a custom_command task (or promoting a task to one, or
      # changing the command it runs) is as privileged as creating one — mirror
      # the create_task gate so update can't be used to smuggle in an
      # unvalidated command or to escalate past the system.admin requirement.
      effective_type = task_params[:type].presence || task.task_type
      if effective_type == "custom_command"
        unless user.has_permission?("system.admin")
          return {
            success: false,
            error: "Custom command tasks require system administrator privileges"
          }
        end

        if task_params.key?(:command) && !valid_custom_command?(task_params[:command])
          return {
            success: false,
            error: "Invalid command. Only rails, bundle, rake, and ruby commands are allowed. Shell metacharacters are forbidden."
          }
        end
      end

      # Update only the provided attributes, mapped onto the real schema.
      task.name = task_params[:name] if task_params.key?(:name)
      task.cron_expression = task_params[:cron_schedule] if task_params.key?(:cron_schedule)
      task.is_active = enabled_from(task_params) if task_params.key?(:enabled)
      task.task_type = task_params[:type] if task_params[:type]
      task.parameters = merge_task_parameters(task.parameters, task_params)

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
        status: "running",
        started_at: Time.current
      )

      # The API server runs no Sidekiq; dispatch the run to the standalone worker
      # over the HTTP seam (WorkerJobService), which enqueues the real
      # Maintenance::ScheduledTaskExecutorJob in the worker's Sidekiq. Never
      # reference an in-process job constant here.
      WorkerJobService.enqueue_job(
        "Maintenance::ScheduledTaskExecutorJob",
        args: [ task.id, execution.id ],
        queue: "maintenance"
      )

      Rails.logger.info "Manual execution of task #{task.name} initiated by #{user&.email}"

      {
        success: true,
        execution: {
          id: execution.id,
          status: execution.status,
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
        when "data_cleanup"
                   execute_data_cleanup_task(task)
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

    # Coerce the admin `enabled` param (JSON boolean or string) into is_active.
    # Absent, nil, or blank defaults to enabled (matches the is_active DB
    # default); anything else casts through ActiveModel's boolean type. Blank/nil
    # must fall back to the default rather than cast to nil — is_active validates
    # inclusion in [true, false], so a nil would fail the save.
    def enabled_from(task_params, default: true)
      value = task_params[:enabled]
      return default if value.nil? || value == ""

      ActiveModel::Type::Boolean.new.cast(value)
    end

    # Fold the admin `description`/`command` params into the `parameters` jsonb
    # without clobbering existing config keys the worker relies on. Only keys
    # actually supplied by the request are overwritten.
    def merge_task_parameters(base, task_params)
      params = (base || {}).deep_dup
      params["description"] = task_params[:description] if task_params.key?(:description)
      params["command"] = task_params[:command] if task_params.key?(:command)
      params
    end

    def format_last_execution(execution)
      return nil unless execution

      {
        id: execution.id,
        status: execution.status,
        started_at: execution.started_at.iso8601,
        completed_at: execution.completed_at&.iso8601,
        duration: execution.completed_at ? (execution.completed_at - execution.started_at).to_i : nil,
        error_message: execution.error_message
      }
    end

    # Operates on an enumerable of loaded executions (counts in Ruby) so callers
    # can pass the eager-loaded association without triggering extra queries.
    def calculate_success_rate(executions)
      return 0 if executions.empty?

      successful = executions.count { |e| e.status == "completed" }

      (successful.to_f / executions.size * 100).round(2)
    end

    def format_task_response(task)
      {
        id: task.id,
        name: task.name,
        description: task.parameters&.dig("description"),
        type: task.task_type,
        cron_schedule: task.cron_expression,
        enabled: task.enabled?,
        command: task.parameters&.dig("command"),
        next_run: task.next_run_at&.iso8601,
        created_at: task.created_at.iso8601,
        updated_at: task.updated_at.iso8601
      }
    end

    # The API server runs no Sidekiq. The standalone worker discovers due tasks
    # by polling the worker-facing controller (is_active AND next_run_at <= now),
    # so "scheduling" a task means computing its next_run_at from the cron
    # expression; "unscheduling" clears it. next_run_at is the real column the
    # worker reads.
    def schedule_task(task)
      return unless task.enabled? && task.cron_expression.present?

      next_run = calculate_next_run_time(task.cron_expression)
      task.update_column(:next_run_at, next_run) if next_run

      Rails.logger.info "Scheduled task '#{task.name}' (#{task.id}) next_run_at=#{next_run}"
    end

    def unschedule_task(task)
      task.update_column(:next_run_at, nil)

      Rails.logger.info "Unscheduled task '#{task.name}' (#{task.id})"
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

    def execute_data_cleanup_task(task)
      results = []

      # Parse command for specific cleanup operations
      if task.command&.include?("audit_logs")
        days = extract_days_from_command(task.command) || 90
        result = DataManagement::CleanupService.cleanup_audit_logs(days)
        results << "Audit logs: #{result[:cleaned_count]} records cleaned"
      end

      if task.command&.include?("sessions")
        result = DataManagement::CleanupService.cleanup_expired_sessions
        results << "Sessions: #{result[:cleaned_count]} expired sessions cleaned"
      end

      if task.command&.include?("temp_files")
        result = DataManagement::CleanupService.cleanup_temp_files
        results << "Temp files: #{result[:cleaned_count]} files cleaned"
      end

      if task.command&.include?("cache")
        result = DataManagement::CleanupService.clear_application_cache
        results << "Cache: #{result[:cleared_entries]} entries cleared"
      end

      {
        success: true,
        output: results.join("; "),
        message: "Data cleanup completed"
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
