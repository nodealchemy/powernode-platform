# frozen_string_literal: true

class AiWorkflowNodeDurationUpdateJob < ApplicationJob
  queue_as :default

  # Send periodic duration updates for running workflow nodes
  def perform(node_execution_id)
    node_execution = AiWorkflowNodeExecution.find_by(id: node_execution_id)

    # Return if node not found
    return unless node_execution

    # CRITICAL FIX: Reload from database to get current status
    # This prevents race conditions where a node completes between job scheduling and execution
    node_execution.reload

    # Only send updates for running nodes
    return unless node_execution.running?

    # Calculate live elapsed time
    elapsed_seconds = node_execution.started_at ? (Time.current - node_execution.started_at).to_i : 0
    elapsed_ms = elapsed_seconds * 1000

    Rails.logger.debug "[DURATION_UPDATE] Sending live duration update for #{node_execution.execution_id}: #{elapsed_seconds}s (status: #{node_execution.status})"

    # Send duration update broadcast
    # CRITICAL FIX: Use correct channel name (AiOrchestrationChannel, not AiWorkflowExecutionChannel)
    # and correct method name (broadcast_node_duration, not broadcast_node_duration_update)
    AiOrchestrationChannel.broadcast_node_duration(
      node_execution,
      elapsed_ms
    )

    # Reload again before scheduling next update to ensure status is current
    node_execution.reload

    # Schedule next update if still running (every 2 seconds)
    if node_execution.running?
      AiWorkflowNodeDurationUpdateJob.set(wait: 2.seconds).perform_later(node_execution_id)
    else
      Rails.logger.debug "[DURATION_UPDATE] Node #{node_execution.execution_id} is no longer running (status: #{node_execution.status}), stopping duration updates"
    end
  rescue ActiveRecord::RecordNotFound
    Rails.logger.debug "[DURATION_UPDATE] Node execution #{node_execution_id} no longer exists, stopping updates"
  rescue => e
    Rails.logger.error "[DURATION_UPDATE] Error updating duration for node #{node_execution_id}: #{e.message}"
    # Don't re-schedule on error to avoid infinite error loops
  end
end