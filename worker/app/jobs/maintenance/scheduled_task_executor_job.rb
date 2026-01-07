# frozen_string_literal: true

module Maintenance
  # Job for executing scheduled tasks
  #
  # This job is triggered by the scheduler when tasks are due.
  # It executes the task based on its type and updates status via API.
  #
  class ScheduledTaskExecutorJob < BaseJob
    sidekiq_options queue: 'maintenance',
                    retry: 1,
                    dead: true

    # Whitelist of allowed commands for security
    ALLOWED_COMMANDS = %w[rails bundle rake ruby].freeze
    BLOCKED_PATTERNS = [
      /sudo/i,
      /rm\s+-rf/i,
      /rm\s+\//i,
      /dd\s+if=/i,
      /mkfs/i,
      /chmod\s+777/i,
      /:\(\)\{:\|:&\}/i, # Fork bomb
    ].freeze

    def execute(task_id, execution_id = nil)
      log_info "Executing scheduled task", task_id: task_id

      # Create execution record if not provided
      unless execution_id
        execution_id = create_execution_record(task_id)
      end

      # Fetch task details
      tasks = fetch_due_tasks(task_id)
      task = tasks['tasks']&.find { |t| t['id'] == task_id }

      unless task
        update_execution_status(execution_id, "failed",
          error_message: "Task not found: #{task_id}"
        )
        raise "Task not found: #{task_id}"
      end

      # Update status to running
      update_execution_status(execution_id, "running")

      # Execute based on task type
      start_time = Time.current

      result = case task['task_type']
      when 'database_backup'
                 execute_database_backup(task)
      when 'data_cleanup'
                 execute_data_cleanup(task)
      when 'system_health_check'
                 execute_health_check(task)
      when 'report_generation'
                 execute_report_generation(task)
      when 'custom_command'
                 execute_custom_command(task)
      else
                 { success: false, error: "Unknown task type: #{task['task_type']}" }
      end

      duration = (Time.current - start_time).round(2)

      if result[:success]
        log_info "Task completed successfully",
                task_id: task_id,
                task_type: task['task_type'],
                duration: duration

        update_execution_status(execution_id, "completed",
          duration_seconds: duration,
          output: result[:output],
          result: result[:data]
        )
      else
        log_error "Task execution failed", nil,
                 task_id: task_id,
                 task_type: task['task_type'],
                 error: result[:error]

        update_execution_status(execution_id, "failed",
          duration_seconds: duration,
          error_message: result[:error],
          error_details: result[:details]
        )

        raise "Task failed: #{result[:error]}"
      end

      result
    end

    private

    def fetch_due_tasks(task_id = nil)
      # Fetch a specific task or all due tasks
      response = api_client.get("/api/v1/internal/maintenance/scheduled_tasks",
        due_before: 1.minute.from_now.iso8601
      )
      response['data'] || { 'tasks' => [] }
    rescue => e
      log_error "Failed to fetch tasks", e
      { 'tasks' => [] }
    end

    def create_execution_record(task_id)
      response = api_client.post(
        "/api/v1/internal/maintenance/scheduled_tasks/#{task_id}/executions",
        triggered_by: "scheduler",
        job_id: jid
      )
      response.dig('data', 'execution_id')
    rescue => e
      log_error "Failed to create execution record", e, task_id: task_id
      nil
    end

    def update_execution_status(execution_id, status, **params)
      return unless execution_id

      api_client.patch(
        "/api/v1/internal/maintenance/task_executions/#{execution_id}",
        { status: status }.merge(params)
      )
    rescue => e
      log_error "Failed to update execution status", e,
               execution_id: execution_id,
               status: status
    end

    def execute_database_backup(task)
      config = task['configuration'] || {}
      backup_type = config['backup_type'] || 'full'

      # Trigger backup via API (which will enqueue DatabaseBackupJob)
      response = api_client.post(
        "/api/v1/admin/maintenance/backups",
        type: backup_type,
        description: "Scheduled backup: #{task['name']}"
      )

      {
        success: true,
        output: "Backup job initiated",
        data: { job_id: response.dig('data', 'job_id') }
      }
    rescue => e
      {
        success: false,
        error: "Failed to initiate backup: #{e.message}"
      }
    end

    def execute_data_cleanup(task)
      config = task['configuration'] || {}
      cleanup_type = config['cleanup_type'] || 'all'

      results = {}

      case cleanup_type
      when 'audit_logs'
        results[:audit_logs] = cleanup_audit_logs(config['days_to_keep'] || 90)
      when 'sessions'
        results[:sessions] = cleanup_sessions
      when 'temp_files'
        results[:temp_files] = cleanup_temp_files
      when 'all'
        results[:audit_logs] = cleanup_audit_logs(config['days_to_keep'] || 90)
        results[:sessions] = cleanup_sessions
        results[:temp_files] = cleanup_temp_files
      end

      {
        success: true,
        output: "Cleanup completed",
        data: results
      }
    rescue => e
      {
        success: false,
        error: "Cleanup failed: #{e.message}"
      }
    end

    def execute_health_check(task)
      response = api_client.get("/api/v1/admin/maintenance/health")

      health_data = response['data']
      overall_status = health_data&.dig('overall_status') || 'unknown'

      {
        success: overall_status == 'healthy',
        output: "Health check: #{overall_status}",
        data: health_data
      }
    rescue => e
      {
        success: false,
        error: "Health check failed: #{e.message}"
      }
    end

    def execute_report_generation(task)
      config = task['configuration'] || {}
      report_type = config['report_type'] || 'system'

      response = api_client.post(
        "/api/v1/reports/generate",
        type: report_type,
        format: config['format'] || 'json'
      )

      {
        success: true,
        output: "Report generated",
        data: { report_id: response.dig('data', 'id') }
      }
    rescue => e
      {
        success: false,
        error: "Report generation failed: #{e.message}"
      }
    end

    def execute_custom_command(task)
      command = task['command']

      # Validate command for security
      unless valid_command?(command)
        return {
          success: false,
          error: "Command not allowed for security reasons"
        }
      end

      # Execute command with timeout
      stdout, stderr, status = execute_with_timeout(command, 300)

      if status.success?
        {
          success: true,
          output: stdout.truncate(10000),
          data: { exit_code: status.exitstatus }
        }
      else
        {
          success: false,
          error: stderr.presence || "Command failed with exit code #{status.exitstatus}",
          details: { exit_code: status.exitstatus, stdout: stdout.truncate(1000) }
        }
      end
    rescue Timeout::Error
      {
        success: false,
        error: "Command timed out after 300 seconds"
      }
    rescue => e
      {
        success: false,
        error: "Command execution error: #{e.message}"
      }
    end

    def valid_command?(command)
      return false if command.blank?

      # Check against blocked patterns
      BLOCKED_PATTERNS.each do |pattern|
        return false if command.match?(pattern)
      end

      # Command must start with an allowed binary
      first_word = command.split(/\s+/).first
      ALLOWED_COMMANDS.include?(first_word)
    end

    def execute_with_timeout(command, timeout_seconds)
      Timeout.timeout(timeout_seconds) do
        Open3.capture3(command)
      end
    end

    def cleanup_audit_logs(days_to_keep)
      response = api_client.post(
        "/api/v1/admin/maintenance/cleanup/run",
        type: "audit_logs",
        days_to_keep: days_to_keep
      )
      response['data'] || { deleted: 0 }
    rescue => e
      { error: e.message }
    end

    def cleanup_sessions
      response = api_client.post(
        "/api/v1/admin/maintenance/cleanup/run",
        type: "sessions"
      )
      response['data'] || { deleted: 0 }
    rescue => e
      { error: e.message }
    end

    def cleanup_temp_files
      response = api_client.post(
        "/api/v1/admin/maintenance/cleanup/run",
        type: "temp_files"
      )
      response['data'] || { deleted: 0 }
    rescue => e
      { error: e.message }
    end
  end
end
