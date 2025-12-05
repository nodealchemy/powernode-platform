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

      log_info("AI execution timeout cleanup completed",
        executions_cleaned: executions_cleaned,
        nodes_cleaned: nodes_cleaned
      )

      { success: true, executions_cleaned: executions_cleaned, nodes_cleaned: nodes_cleaned }
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
end