# frozen_string_literal: true

# Background job to clean up stuck workflow executions
class WorkflowCleanupJob < BaseJob
  sidekiq_options queue: :maintenance

  # Time thresholds for determining stuck runs
  STUCK_THRESHOLD = 10.minutes
  INITIALIZING_THRESHOLD = 5.minutes

  def execute
    log_info("[WorkflowCleanupJob] Starting cleanup of stuck workflow runs")

    cleaned_count = 0
    error_count = 0

    # Find and clean up stuck runs
    stuck_runs = fetch_stuck_runs

    stuck_runs.each do |run_data|
      begin
        result = cleanup_stuck_run(run_data)
        if result[:success]
          cleaned_count += 1
          log_info("[WorkflowCleanupJob] Cleaned up run #{run_data['run_id']}: #{result[:message]}")
        else
          error_count += 1
          log_error("[WorkflowCleanupJob] Failed to clean run #{run_data['run_id']}: #{result[:error]}")
        end
      rescue => e
        error_count += 1
        log_error("[WorkflowCleanupJob] Error processing run #{run_data['run_id']}: #{e.message}")
      end
    end

    log_info("[WorkflowCleanupJob] Cleanup complete. Cleaned: #{cleaned_count}, Errors: #{error_count}")

    # Schedule next cleanup
    self.class.set(wait: 5.minutes).perform_later
  end

  private

  def fetch_stuck_runs
    # Check for stuck initializing/running workflows
    stuck_response = api_client.get('/ai/workflow_runs', {
      status: ['initializing', 'running'],
      per_page: 100
    })

    runs = stuck_response.dig('data', 'workflow_runs') || []
    stuck_runs = runs.select { |run| is_stuck?(run) }

    # Also check for "completed" workflows that actually have failures
    completed_response = api_client.get('/ai/workflow_runs', {
      status: 'completed',
      per_page: 50,
      created_after: 1.day.ago.iso8601
    })

    completed_runs = completed_response.dig('data', 'workflow_runs') || []
    mismarked_runs = completed_runs.select { |run| has_failed_nodes?(run) }
    stuck_runs.concat(mismarked_runs)

    stuck_runs
  end

  def is_stuck?(run)
    status = run['status']
    started_at = parse_time(run['started_at'])
    created_at = parse_time(run['created_at'])

    case status
    when 'initializing'
      # Stuck if initializing for more than 5 minutes
      created_at && (Time.current - created_at) > INITIALIZING_THRESHOLD
    when 'running'
      # Check if all nodes are completed but status is still running (orphaned workflow)
      completed_nodes = run['completed_nodes'] || 0
      total_nodes = run['total_nodes'] || 0

      if completed_nodes >= total_nodes && total_nodes > 0
        # All nodes complete but status still running - this is an orphaned workflow
        return true
      end

      # Stuck if no progress for more than 10 minutes
      if started_at
        last_activity = parse_time(run['updated_at']) || started_at
        (Time.current - last_activity) > STUCK_THRESHOLD
      else
        # Running but never started - definitely stuck
        created_at && (Time.current - created_at) > INITIALIZING_THRESHOLD
      end
    else
      false
    end
  end

  def cleanup_stuck_run(run_data)
    run_id = run_data['run_id'] || run_data['id']
    status = run_data['status']

    # Check if this is a "completed" workflow that actually has failures
    if status == 'completed' && has_failed_nodes?(run_data)
      return fix_mismarked_completed_workflow(run_data)
    end

    # Check if this is an orphaned workflow (all nodes complete)
    completed_nodes = run_data['completed_nodes'] || 0
    total_nodes = run_data['total_nodes'] || 0
    failed_nodes = run_data['failed_nodes'] || 0

    if completed_nodes >= total_nodes && total_nodes > 0
      # This is an orphaned workflow - complete it instead of canceling
      return complete_orphaned_workflow(run_data)
    end

    # For truly stuck workflows, attempt to cancel via API
    response = api_client.post("/ai/workflow_runs/#{run_id}/cancel", {
      reason: "Automatically cancelled: stuck in #{status} state for too long"
    })

    if response.success?
      {
        success: true,
        message: "Cancelled stuck #{status} run"
      }
    else
      # If cancellation fails, try direct status update
      fallback_cleanup(run_id, status)
    end
  end

  def complete_orphaned_workflow(run_data)
    run_id = run_data['run_id'] || run_data['id']
    failed_nodes = run_data['failed_nodes'] || 0

    # Determine final status based on failed nodes
    final_status = failed_nodes > 0 ? 'failed' : 'completed'

    log_info("[WorkflowCleanupJob] Completing orphaned workflow #{run_id} as #{final_status} (#{run_data['completed_nodes']}/#{run_data['total_nodes']} nodes, #{failed_nodes} failed)")

    # Update workflow status directly
    response = api_client.patch("/ai/workflow_runs/#{run_id}", {
      workflow_run: {
        status: final_status,
        completed_at: Time.current.iso8601
      }
    })

    # api_client raises on error, so reaching here means success
    broadcast_completion_event(run_data, final_status)

    {
      success: true,
      message: "Completed orphaned workflow as #{final_status}"
    }
  end

  def fallback_cleanup(run_id, status)
    # Try to mark as failed if cancellation doesn't work
    response = api_client.patch("/ai/workflow_runs/#{run_id}", {
      workflow_run: {
        status: 'failed',
        error_details: {
          error: 'WorkflowTimeout',
          message: "Workflow stuck in #{status} state and was automatically terminated",
          cleaned_at: Time.current.iso8601
        }
      }
    })

    {
      success: true,
      message: "Marked stuck run as failed"
    }
  end

  def broadcast_completion_event(run_data, final_status)
    # Broadcast real-time completion event
    begin
      ActionCable.server.broadcast(
        "ai_workflow_execution_#{run_data['run_id']}",
        {
          type: 'execution_completed',
          status: final_status,
          run_id: run_data['run_id'],
          workflow_run: run_data.merge('status' => final_status),
          completed_at: Time.current.iso8601,
          cleanup: true,
          message: "Workflow status corrected by cleanup job"
        }
      )
    rescue StandardError => e
      log_warn("[WorkflowCleanupJob] Failed to broadcast completion for #{run_data['run_id']}: #{e.message}")
    end
  end

  def has_failed_nodes?(run_data)
    failed_nodes = run_data['failed_nodes'] || 0
    failed_nodes > 0
  end

  def fix_mismarked_completed_workflow(run_data)
    run_id = run_data['run_id'] || run_data['id']
    failed_nodes = run_data['failed_nodes'] || 0

    log_info("[WorkflowCleanupJob] Fixing mismarked completed workflow #{run_id} with #{failed_nodes} failed nodes")

    # Update workflow status to failed since it has failed nodes
    response = api_client.patch("/ai/workflow_runs/#{run_id}", {
      workflow_run: {
        status: 'failed',
        failed_at: Time.current.iso8601,
        error_details: {
          error: 'WorkflowStatusCorrection',
          message: "Workflow was incorrectly marked as completed despite having #{failed_nodes} failed nodes",
          corrected_at: Time.current.iso8601,
          original_status: 'completed'
        }
      }
    })

    # Broadcast status correction event
    broadcast_status_correction_event(run_data)

    {
      success: true,
      message: "Corrected mismarked completed workflow to failed status"
    }
  end

  def broadcast_status_correction_event(run_data)
    # Broadcast real-time status correction event
    begin
      ActionCable.server.broadcast(
        "ai_workflow_execution_#{run_data['run_id']}",
        {
          type: 'status_corrected',
          status: 'failed',
          run_id: run_data['run_id'],
          workflow_run: run_data.merge('status' => 'failed'),
          corrected_at: Time.current.iso8601,
          cleanup: true,
          message: "Workflow status corrected from completed to failed by cleanup job"
        }
      )
    rescue StandardError => e
      log_warn("[WorkflowCleanupJob] Failed to broadcast status correction for #{run_data['run_id']}: #{e.message}")
    end
  end

  def parse_time(time_string)
    return nil if time_string.nil?
    Time.parse(time_string)
  rescue ArgumentError
    nil
  end

  def api_client
    @api_client ||= BackendApiClient.new
  end
end