# frozen_string_literal: true

class AiExecutionTimeoutCleanupJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: 'maintenance', retry: false

  TIMEOUT_THRESHOLDS = {
    'pending' => 300, # 5 minutes
    'running' => 600  # 10 minutes
  }.freeze

  def execute
    log_info("Starting AI execution timeout cleanup")

    begin
      executions_cleaned = cleanup_hanging_executions
      nodes_cleaned = cleanup_hanging_workflow_nodes
      runs_cleaned = cleanup_stale_workflow_runs

      log_info("AI execution timeout cleanup completed",
        executions_cleaned: executions_cleaned,
        nodes_cleaned: nodes_cleaned,
        runs_cleaned: runs_cleaned
      )

      { success: true, executions_cleaned: executions_cleaned, nodes_cleaned: nodes_cleaned, runs_cleaned: runs_cleaned }
    rescue BackendApiClient::ApiError => e
      log_error("AI execution timeout cleanup failed due to API error",
        error: e.message,
        status_code: e.respond_to?(:status_code) ? e.status_code : nil
      )
      raise
    rescue StandardError => e
      log_error("AI execution timeout cleanup failed unexpectedly",
        error: e.message,
        error_class: e.class.name
      )
      raise
    end
  end

  private

  def cleanup_hanging_executions
    total_cleaned = 0

    TIMEOUT_THRESHOLDS.each do |status, timeout_seconds|
      cutoff_time = timeout_seconds.seconds.ago

      # Find hanging executions via backend API
      response = backend_api_get("/api/v1/ai/executions", {
        status: status,
        before: cutoff_time.iso8601,
        limit: 50
      })

      next unless response['success']

      hanging_executions = response['data']['executions'] || []

      hanging_executions.each do |execution|
        cancel_hanging_execution(execution, status, timeout_seconds)
        total_cleaned += 1
      end

      log_info("Cleaned up hanging #{status} executions", count: hanging_executions.size) if hanging_executions.any?
    end

    total_cleaned
  end

  def cleanup_hanging_workflow_nodes
    # Find hanging workflow node executions
    response = backend_api_get("/api/v1/ai/workflow_node_executions", {
      status: 'running',
      before: 10.minutes.ago.iso8601,
      limit: 20
    })

    return 0 unless response['success']

    hanging_nodes = response['data']['node_executions'] || []

    hanging_nodes.each do |node_execution|
      cancel_hanging_node(node_execution)
    end

    log_info("Cleaned up hanging workflow nodes", count: hanging_nodes.size) if hanging_nodes.any?

    hanging_nodes.size
  end

  def cancel_hanging_execution(execution, status, timeout_seconds)
    execution_id = execution['id']
    duration = Time.current - Time.parse(execution['created_at'])

    log_warn("Cancelling hanging AI execution",
      execution_id: execution_id,
      status: status,
      duration_seconds: duration.round(1),
      timeout_threshold: timeout_seconds
    )

    # Cancel via backend API
    cancel_response = backend_api_post("/api/v1/ai/executions/#{execution_id}/cancel", {
      reason: "Timeout: execution hung in #{status} state for #{duration.round(1)}s (threshold: #{timeout_seconds}s)"
    })

    if cancel_response['success']
      log_info("Successfully cancelled hanging execution", execution_id: execution_id)
    else
      log_error("Failed to cancel hanging execution",
        execution_id: execution_id,
        error: cancel_response['error']
      )
    end
  end

  def cancel_hanging_node(node_execution)
    node_id = node_execution['id']
    duration = Time.current - Time.parse(node_execution['created_at'])

    log_warn("Cancelling hanging workflow node execution",
      node_execution_id: node_id,
      duration_seconds: duration.round(1)
    )

    # Cancel via backend API
    cancel_response = backend_api_patch("/api/v1/ai/workflow_node_executions/#{node_id}", {
      node_execution: {
        status: 'failed',
        error_details: {
          'timeout_reason' => 'Node execution timeout',
          'duration_seconds' => duration.round(1),
          'cancelled_at' => Time.current.iso8601
        },
        completed_at: Time.current.iso8601
      }
    })

    if cancel_response['success']
      log_info("Successfully cancelled hanging node execution", node_execution_id: node_id)
    else
      log_error("Failed to cancel hanging node execution",
        node_execution_id: node_id,
        error: cancel_response['error']
      )
    end
  end

  # Workflow run timeout thresholds (based on time since last activity)
  WORKFLOW_RUN_TIMEOUTS = {
    'initializing' => 900,  # 15 minutes - should start executing within this time
    'running' => 2700       # 45 minutes - no progress within this window
  }.freeze

  def cleanup_stale_workflow_runs
    total_cleaned = 0

    WORKFLOW_RUN_TIMEOUTS.each do |status, timeout_seconds|
      # Fetch runs in this status (we'll check activity time client-side)
      response = backend_api_get("/api/v1/ai/workflow_runs", {
        status: status,
        limit: 50
      })

      next unless response['success']

      runs = response['data']['workflow_runs'] || []

      # Filter to only runs with no recent activity
      stale_runs = runs.select { |run| run_is_stale?(run, status, timeout_seconds) }

      stale_runs.each do |run|
        cancel_stale_workflow_run(run, status, timeout_seconds)
        total_cleaned += 1
      end

      log_info("Cleaned up stale #{status} workflow runs", count: stale_runs.size) if stale_runs.any?
    end

    total_cleaned
  end

  def run_is_stale?(run, status, timeout_seconds)
    # Get the most recent activity timestamp
    last_activity = determine_last_activity(run, status)
    return false unless last_activity

    # Check if no progress has been made within the timeout window
    time_since_activity = Time.current - last_activity
    time_since_activity > timeout_seconds
  end

  def determine_last_activity(run, status)
    # For initializing runs, use created_at (they haven't started yet)
    if status == 'initializing'
      timestamp = run['created_at']
      return timestamp ? Time.parse(timestamp) : nil
    end

    # For running workflows, check for most recent activity:
    # 1. updated_at - indicates any change to the run
    # 2. If node executions exist, check their timestamps
    # 3. Fall back to started_at
    updated_at = run['updated_at'] ? Time.parse(run['updated_at']) : nil
    started_at = run['started_at'] ? Time.parse(run['started_at']) : nil

    # Use updated_at as primary indicator of activity
    # If updated_at equals created_at, it means no progress has been made
    last_activity = updated_at || started_at

    # Additional check: if completed_nodes increased recently, there's progress
    # This is reflected in updated_at, so we rely on that

    last_activity
  end

  def cancel_stale_workflow_run(run, status, timeout_seconds)
    run_id = run['id'] || run['run_id']
    last_activity = determine_last_activity(run, status)
    time_since_activity = last_activity ? (Time.current - last_activity).round(1) : 'unknown'

    log_warn("Cancelling stale workflow run",
      run_id: run_id,
      status: status,
      time_since_last_activity: time_since_activity,
      timeout_threshold: timeout_seconds,
      completed_nodes: run['completed_nodes'],
      total_nodes: run['total_nodes']
    )

    # Cancel via backend API
    cancel_response = backend_api_patch("/api/v1/ai/workflow_runs/#{run_id}", {
      workflow_run: {
        status: 'failed',
        error_details: {
          'timeout_reason' => "Workflow run stuck in #{status} state with no progress",
          'time_since_last_activity' => time_since_activity,
          'timeout_threshold' => timeout_seconds,
          'completed_nodes' => run['completed_nodes'],
          'total_nodes' => run['total_nodes'],
          'cancelled_at' => Time.current.iso8601,
          'cancelled_by' => 'AiExecutionTimeoutCleanupJob'
        },
        completed_at: Time.current.iso8601
      }
    })

    if cancel_response['success']
      log_info("Successfully cancelled stale workflow run", run_id: run_id)
    else
      log_error("Failed to cancel stale workflow run",
        run_id: run_id,
        error: cancel_response['error']
      )
    end
  end
end