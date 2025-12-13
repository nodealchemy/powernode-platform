# frozen_string_literal: true

module AiWorkflowNodeExecution::Broadcasting
  extend ActiveSupport::Concern

  included do
    after_commit :broadcast_node_status_change_if_needed, on: [ :update ]
    after_commit :log_status_broadcast_check, on: [ :update ]
    after_commit :check_workflow_failure_on_node_failure, on: [ :update ]
  end

  # Public method to force broadcast status update (useful for fixing sync issues)
  def force_status_broadcast!
    Rails.logger.info "Force broadcasting status for node: #{ai_workflow_node.name} (#{status})"
    broadcast_node_status_change
  end

  private

  def should_broadcast_status_change?
    return false unless saved_change_to_status?

    old_status, new_status = saved_change_to_status

    # Only broadcast on meaningful status transitions
    broadcast_transitions = [
      [ "running", "completed" ],
      [ "running", "failed" ],
      [ "running", "cancelled" ],
      [ "pending", "running" ],
      [ "waiting_approval", "running" ]
    ]

    broadcast_transitions.include?([ old_status, new_status ])
  end

  def log_status_broadcast_check
    # Status broadcast logging handled by broadcast_node_status_change_if_needed
  end

  def broadcast_node_status_change
    Rails.logger.info "[NodeExecution] Broadcasting node status change: #{execution_id} -> #{status} (#{ai_workflow_node.name})"

    begin
      if defined?(AiOrchestrationChannel)
        AiOrchestrationChannel.broadcast_node_execution(self)
      else
        Rails.logger.warn "[NodeExecution] AiOrchestrationChannel not available, skipping WebSocket broadcast"
      end
    rescue NameError => e
      Rails.logger.error "[NodeExecution] WebSocket broadcast failed (channel not loaded): #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
    rescue StandardError => e
      Rails.logger.error "[NodeExecution] WebSocket broadcast failed: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
    end
  end

  def broadcast_node_status_change_if_needed
    # Use @pending_status_change because saved_change_to_status? is cleared in after_commit
    if @pending_status_change
      old_status, new_status = @pending_status_change

      broadcast_transitions = [
        [ "running", "completed" ],
        [ "running", "failed" ],
        [ "running", "cancelled" ],
        [ "pending", "running" ],
        [ "waiting_approval", "running" ]
      ]

      should_broadcast = broadcast_transitions.include?([ old_status, new_status ])

      if should_broadcast
        broadcast_node_status_change
      end

      # Clear the pending change after broadcasting
      @pending_status_change = nil
    end
  end

  def check_workflow_failure_on_node_failure
    # Check if this node failure should trigger workflow failure
    if @pending_status_change
      old_status, new_status = @pending_status_change

      # Only trigger on transition to failed status
      if new_status == "failed" && old_status != "failed"
        begin
          ai_workflow_run.log(
            "error",
            "node_execution_failed",
            "Node #{ai_workflow_node.name} failed",
            {
              "node_id" => node_id,
              "execution_id" => execution_id,
              "error_details" => error_details
            },
            self
          )
        rescue StandardError => e
          Rails.logger.error "Failed to log node failure: #{e.message}"
        end
      end
    end
  end
end
