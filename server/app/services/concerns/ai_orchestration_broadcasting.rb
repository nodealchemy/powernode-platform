# frozen_string_literal: true

# AiOrchestrationBroadcasting - Concern for real-time AI workflow status broadcasting
#
# This concern handles ActionCable broadcasts for workflow execution status,
# agent status updates, and system metrics. It enables real-time UI updates
# during workflow execution.
#
# @example Including in a service
#   class Ai::AgentOrchestrationService
#     include AiOrchestrationBroadcasting
#   end
#
module AiOrchestrationBroadcasting
  extend ActiveSupport::Concern

    # Broadcast workflow execution status update to connected clients
    #
    # @param workflow_execution [Ai::WorkflowRun] The workflow execution
    # @param additional_data [Hash] Additional data to include in broadcast
    def broadcast_workflow_update(workflow_execution, additional_data = {})
      return unless workflow_execution&.account_id

      broadcast_data = {
        workflow_id: workflow_execution.id,
        status: workflow_execution.status,
        progress: calculate_workflow_progress(workflow_execution),
        metadata: workflow_execution.metadata,
        timestamp: Time.current.iso8601
      }.merge(additional_data)

      # Broadcast to account channel
      ActionCable.server.broadcast(
        "ai_orchestration_#{workflow_execution.account_id}",
        broadcast_data
      )

      # Also broadcast to user channel if available
      if workflow_execution.user_id
        ActionCable.server.broadcast(
          "ai_orchestration_user_#{workflow_execution.user_id}",
          broadcast_data
        )
      end

      @logger.info "Broadcasted workflow update: #{broadcast_data[:type]} for workflow #{workflow_execution.id}"
    rescue StandardError => e
      @logger.error "Failed to broadcast workflow update: #{e.message}"
    end

    # Broadcast agent status update to connected clients
    #
    # @param agent [Ai::Agent] The agent
    # @param status_data [Hash] Status information
    def broadcast_agent_status(agent, status_data)
      return unless @account&.id

      broadcast_data = {
        type: "agent_status_update",
        agent_id: agent.id,
        status: status_data,
        timestamp: Time.current.iso8601
      }

      ActionCable.server.broadcast(
        "ai_orchestration_#{@account.id}",
        broadcast_data
      )

      @logger.info "Broadcasted agent status update for agent #{agent.id}"
    rescue StandardError => e
      @logger.error "Failed to broadcast agent status: #{e.message}"
    end

    # Broadcast system metrics to connected clients
    def broadcast_system_metrics
      return unless @account&.id

      begin
        metrics = Ai::Analytics::DashboardService.new(account: @account).real_time_metrics

        broadcast_data = {
          type: "system_metrics_update",
          metrics: metrics,
          timestamp: Time.current.iso8601
        }

        ActionCable.server.broadcast(
          "ai_orchestration_#{@account.id}",
          broadcast_data
        )

        @logger.info "Broadcasted system metrics for account #{@account.id}"
      rescue StandardError => e
        @logger.error "Failed to broadcast system metrics: #{e.message}"
      end
    end

    # Get current status for a specific agent
    #
    # @param agent_id [String] The agent ID
    # @param account_id [String] The account ID
    # @return [Hash, nil] Agent status or nil if not found
    def get_agent_status(agent_id, account_id)
      return unless account_id == @account&.id

      agent = Ai::Agent.joins(:account).where(accounts: { id: account_id }).find(agent_id)
      return nil unless agent

      current_executions = agent.executions.where(status: %w[queued processing])
      recent_executions = agent.executions.where(created_at: 1.hour.ago..Time.current)

      {
        agent_id: agent_id,
        current_executions: current_executions.count,
        recent_success_rate: calculate_recent_success_rate(recent_executions),
        avg_response_time: recent_executions.average(:duration_ms) || 0,
        last_execution: recent_executions.order(created_at: :desc).first&.created_at,
        status: current_executions.any? ? "active" : "idle"
      }
    end
end
