# frozen_string_literal: true

# Background job to perform monthly cleanup of AI workflow data
# Runs on the 1st of every month to archive old executions and clean temp data
class AiWorkflowMonthlyCleanupJob < BaseJob
  queue_as :maintenance

  # Retention periods (configurable)
  EXECUTION_RETENTION_DAYS = 90      # Keep execution details for 90 days
  LOG_RETENTION_DAYS = 30            # Keep detailed logs for 30 days
  ANALYTICS_RETENTION_DAYS = 365     # Keep analytics for 1 year
  TEMP_FILE_RETENTION_DAYS = 7       # Clean temp files older than 7 days

  def execute
    log_info("Starting AI Workflow Monthly Cleanup")

    cleanup_report = {
      started_at: Time.current.iso8601,
      status: 'running',
      tasks: {},
      totals: {
        archived: 0,
        deleted: 0,
        freed_space_bytes: 0,
        errors: 0
      }
    }

    begin
      # Archive old workflow executions
      cleanup_report[:tasks][:archive_executions] = archive_old_executions

      # Clean up execution logs
      cleanup_report[:tasks][:cleanup_logs] = cleanup_execution_logs

      # Archive analytics data
      cleanup_report[:tasks][:archive_analytics] = archive_analytics_data

      # Clean temporary files
      cleanup_report[:tasks][:cleanup_temp_files] = cleanup_temporary_files

      # Clean orphaned records
      cleanup_report[:tasks][:cleanup_orphans] = cleanup_orphaned_records

      # Vacuum and optimize
      cleanup_report[:tasks][:optimize] = optimize_database

      # Calculate totals
      calculate_cleanup_totals(cleanup_report)

      cleanup_report[:status] = cleanup_report[:totals][:errors].positive? ? 'completed_with_errors' : 'completed'
      cleanup_report[:completed_at] = Time.current.iso8601

      # Store cleanup report
      store_cleanup_report(cleanup_report)

      # Send notification
      send_cleanup_notification(cleanup_report)

      log_info("AI Workflow Monthly Cleanup completed: " \
               "archived=#{cleanup_report[:totals][:archived]}, " \
               "deleted=#{cleanup_report[:totals][:deleted]}, " \
               "freed=#{format_bytes(cleanup_report[:totals][:freed_space_bytes])}")
    rescue StandardError => e
      log_error("AI Workflow Monthly Cleanup failed", e)
      cleanup_report[:status] = 'failed'
      cleanup_report[:error] = e.message
    end

    cleanup_report
  end

  private

  def archive_old_executions
    log_info("Archiving old workflow executions (older than #{EXECUTION_RETENTION_DAYS} days)")

    cutoff_date = EXECUTION_RETENTION_DAYS.days.ago.iso8601

    result = with_api_retry do
      api_client.post('admin/ai_workflows/archive_executions', {
        before_date: cutoff_date,
        batch_size: 1000,
        archive_to: 'cold_storage'
      })
    end

    {
      status: 'completed',
      archived_count: result['archived_count'] || 0,
      freed_space_bytes: result['freed_space_bytes'] || 0,
      cutoff_date: cutoff_date
    }
  rescue StandardError => e
    log_error("Failed to archive old executions", e)
    { status: 'failed', error: e.message }
  end

  def cleanup_execution_logs
    log_info("Cleaning up execution logs (older than #{LOG_RETENTION_DAYS} days)")

    cutoff_date = LOG_RETENTION_DAYS.days.ago.iso8601

    result = with_api_retry do
      api_client.post('admin/ai_workflows/cleanup_logs', {
        before_date: cutoff_date,
        batch_size: 5000,
        keep_summary: true  # Keep summary but delete detailed logs
      })
    end

    {
      status: 'completed',
      deleted_count: result['deleted_count'] || 0,
      freed_space_bytes: result['freed_space_bytes'] || 0,
      cutoff_date: cutoff_date
    }
  rescue StandardError => e
    log_error("Failed to cleanup execution logs", e)
    { status: 'failed', error: e.message }
  end

  def archive_analytics_data
    log_info("Archiving analytics data (older than #{ANALYTICS_RETENTION_DAYS} days)")

    cutoff_date = ANALYTICS_RETENTION_DAYS.days.ago.iso8601

    result = with_api_retry do
      api_client.post('admin/ai_workflows/archive_analytics', {
        before_date: cutoff_date,
        aggregate_to: 'monthly',  # Aggregate daily data to monthly before archiving
        batch_size: 10000
      })
    end

    {
      status: 'completed',
      archived_count: result['archived_count'] || 0,
      aggregated_count: result['aggregated_count'] || 0,
      freed_space_bytes: result['freed_space_bytes'] || 0,
      cutoff_date: cutoff_date
    }
  rescue StandardError => e
    log_error("Failed to archive analytics data", e)
    { status: 'failed', error: e.message }
  end

  def cleanup_temporary_files
    log_info("Cleaning up temporary files (older than #{TEMP_FILE_RETENTION_DAYS} days)")

    cutoff_date = TEMP_FILE_RETENTION_DAYS.days.ago.iso8601

    result = with_api_retry do
      api_client.post('admin/ai_workflows/cleanup_temp_files', {
        before_date: cutoff_date,
        include_patterns: [
          'workflow_temp_*',
          'execution_output_*',
          'node_cache_*',
          'checkpoint_*'
        ]
      })
    end

    {
      status: 'completed',
      deleted_count: result['deleted_count'] || 0,
      freed_space_bytes: result['freed_space_bytes'] || 0,
      cutoff_date: cutoff_date
    }
  rescue StandardError => e
    log_error("Failed to cleanup temporary files", e)
    { status: 'failed', error: e.message }
  end

  def cleanup_orphaned_records
    log_info("Cleaning up orphaned records")

    result = with_api_retry do
      api_client.post('admin/ai_workflows/cleanup_orphans', {
        types: [
          'node_executions_without_run',
          'checkpoints_without_run',
          'events_without_workflow',
          'variables_without_workflow'
        ],
        dry_run: false
      })
    end

    {
      status: 'completed',
      orphans_by_type: result['orphans_by_type'] || {},
      deleted_count: result['total_deleted'] || 0
    }
  rescue StandardError => e
    log_error("Failed to cleanup orphaned records", e)
    { status: 'failed', error: e.message }
  end

  def optimize_database
    log_info("Optimizing database tables")

    result = with_api_retry do
      api_client.post('admin/database/optimize', {
        tables: [
          'ai_workflow_runs',
          'ai_workflow_node_executions',
          'ai_workflow_events',
          'ai_workflow_checkpoints'
        ],
        operations: ['vacuum', 'analyze', 'reindex']
      })
    end

    {
      status: 'completed',
      tables_optimized: result['tables_optimized'] || [],
      freed_space_bytes: result['freed_space_bytes'] || 0,
      duration_seconds: result['duration_seconds'] || 0
    }
  rescue StandardError => e
    log_error("Failed to optimize database", e)
    { status: 'failed', error: e.message }
  end

  def calculate_cleanup_totals(cleanup_report)
    cleanup_report[:tasks].each_value do |task|
      next if task[:status] == 'failed'

      cleanup_report[:totals][:archived] += task[:archived_count] || 0
      cleanup_report[:totals][:deleted] += task[:deleted_count] || 0
      cleanup_report[:totals][:freed_space_bytes] += task[:freed_space_bytes] || 0
      cleanup_report[:totals][:errors] += 1 if task[:status] == 'failed'
    end
  end

  def store_cleanup_report(cleanup_report)
    with_api_retry do
      api_client.post('admin/ai_workflow_cleanup_reports', {
        report_type: 'monthly',
        started_at: cleanup_report[:started_at],
        completed_at: cleanup_report[:completed_at],
        status: cleanup_report[:status],
        tasks: cleanup_report[:tasks],
        totals: cleanup_report[:totals]
      })
    end
  rescue StandardError => e
    log_error("Failed to store cleanup report", e)
  end

  def send_cleanup_notification(cleanup_report)
    severity = case cleanup_report[:status]
               when 'completed' then 'info'
               when 'completed_with_errors' then 'warning'
               else 'error'
               end

    with_api_retry do
      api_client.post('admin/notifications/broadcast', {
        notification_type: 'monthly_cleanup_complete',
        title: "AI Workflow Monthly Cleanup #{cleanup_report[:status].humanize}",
        message: "Monthly cleanup completed. " \
                 "Archived: #{cleanup_report[:totals][:archived]}, " \
                 "Deleted: #{cleanup_report[:totals][:deleted]}, " \
                 "Freed: #{format_bytes(cleanup_report[:totals][:freed_space_bytes])}",
        severity: severity,
        target_permissions: ['admin.access', 'system.admin'],
        metadata: {
          totals: cleanup_report[:totals],
          tasks: cleanup_report[:tasks].transform_values { |t| t[:status] }
        }
      })
    end
  rescue StandardError => e
    log_error("Failed to send cleanup notification", e)
  end

  def format_bytes(bytes)
    return '0 B' if bytes.nil? || bytes.zero?

    units = ['B', 'KB', 'MB', 'GB', 'TB']
    exp = (Math.log(bytes) / Math.log(1024)).to_i
    exp = units.size - 1 if exp >= units.size

    "#{(bytes.to_f / 1024**exp).round(2)} #{units[exp]}"
  end
end
