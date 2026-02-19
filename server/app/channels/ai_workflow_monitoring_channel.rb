# frozen_string_literal: true

# AiWorkflowMonitoringChannel - Workflow monitoring and analytics channel
#
# This channel is a specialized wrapper around AiOrchestrationChannel
# focused specifically on monitoring, analytics, and system alerts.
#
class AiWorkflowMonitoringChannel < ApplicationCable::Channel
  def subscribed
    return reject unless current_user
    return reject unless authorized_for_monitoring?

    workflow_id = params[:workflow_id]

    if workflow_id
      # Subscribe to specific workflow monitoring
      workflow = Ai::Workflow.find_by(id: workflow_id, account_id: current_user.account_id)
      return reject unless workflow

      stream_from "ai_orchestration:workflow:#{workflow_id}"
      Rails.logger.info "[Ai::WorkflowMonitoringChannel] User #{current_user.id} subscribed to workflow #{workflow_id}"
    else
      # Subscribe to account-level monitoring
      stream_from "ai_orchestration:monitoring:#{current_user.account_id}"
      stream_from "ai_orchestration:account:#{current_user.account_id}"
      Rails.logger.info "[Ai::WorkflowMonitoringChannel] User #{current_user.id} subscribed to account monitoring"
    end

    transmit({
      type: "subscription.confirmed",
      channel: "workflow_monitoring",
      workflow_id: workflow_id,
      timestamp: Time.current.iso8601
    })
  end

  def unsubscribed
    Rails.logger.info "[Ai::WorkflowMonitoringChannel] User #{current_user&.id} unsubscribed"
  end

  # Get dashboard statistics
  def get_dashboard_stats(_data = {})
    stats = {
      total_workflows: Ai::Workflow.where(account_id: current_user.account_id).count,
      active_executions: Ai::WorkflowRun.where(
        account_id: current_user.account_id,
        status: %w[initializing running paused]
      ).count,
      completed_today: Ai::WorkflowRun.where(
        account_id: current_user.account_id,
        status: "completed",
        completed_at: Time.current.beginning_of_day..Time.current.end_of_day
      ).count,
      failed_today: Ai::WorkflowRun.where(
        account_id: current_user.account_id,
        status: "failed",
        completed_at: Time.current.beginning_of_day..Time.current.end_of_day
      ).count
    }

    transmit({
      type: "dashboard_stats",
      stats: stats,
      timestamp: Time.current.iso8601
    })
  rescue StandardError => e
    transmit_error(e.message)
  end

  # Get active executions
  def get_active_executions(_data = {})
    executions = Ai::WorkflowRun.where(
      account_id: current_user.account_id,
      status: %w[initializing running paused]
    ).order(started_at: :desc).limit(50)

    transmit({
      type: "active_executions",
      executions: executions.map { |run| serialize_workflow_run(run) },
      timestamp: Time.current.iso8601
    })
  rescue StandardError => e
    transmit_error(e.message)
  end

  # Class methods for broadcasting
  class << self
    def broadcast_dashboard_update(account_id)
      stats = calculate_dashboard_stats(account_id)

      ActionCable.server.broadcast(
        "ai_orchestration:monitoring:#{account_id}",
        {
          type: "dashboard_stats",
          stats: stats,
          timestamp: Time.current.iso8601
        }
      )

      # Also broadcast active executions update
      broadcast_active_executions_update(account_id)
    end

    def broadcast_active_executions_update(account_id)
      executions = Ai::WorkflowRun.where(
        account_id: account_id,
        status: %w[initializing running paused]
      ).order(started_at: :desc).limit(50)

      ActionCable.server.broadcast(
        "ai_orchestration:monitoring:#{account_id}",
        {
          type: "active_executions",
          executions: executions.map { |run| serialize_workflow_run_for_broadcast(run) },
          timestamp: Time.current.iso8601
        }
      )
    end

    def broadcast_system_alert(account_id, alert_data)
      ActionCable.server.broadcast(
        "ai_orchestration:monitoring:#{account_id}",
        {
          type: "system_alert",
          alert: alert_data.merge(
            timestamp: Time.current.iso8601
          )
        }
      )
    end

    def broadcast_cost_alert(account_id, cost_data)
      ActionCable.server.broadcast(
        "ai_orchestration:monitoring:#{account_id}",
        {
          type: "cost_alert",
          cost_data: cost_data.merge(
            timestamp: Time.current.iso8601
          )
        }
      )
    end

    private

    def calculate_dashboard_stats(account_id)
      today_range = Time.current.beginning_of_day..Time.current.end_of_day

      {
        total_workflows: Ai::Workflow.where(account_id: account_id).count,
        active_executions: Ai::WorkflowRun.where(
          account_id: account_id,
          status: %w[initializing running paused]
        ).count,
        completed_today: Ai::WorkflowRun.where(
          account_id: account_id,
          status: "completed",
          completed_at: today_range
        ).count,
        failed_today: Ai::WorkflowRun.where(
          account_id: account_id,
          status: "failed",
          completed_at: today_range
        ).count
      }
    end

    def serialize_workflow_run_for_broadcast(workflow_run)
      {
        id: workflow_run.id,
        run_id: workflow_run.run_id,
        workflow_id: workflow_run.ai_workflow_id,
        workflow_name: workflow_run.workflow&.name,
        status: workflow_run.status,
        started_at: workflow_run.started_at&.iso8601,
        completed_at: workflow_run.completed_at&.iso8601,
        execution_time_ms: workflow_run.duration_ms,
        total_cost: workflow_run.total_cost
      }
    end
  end

  private

  def authorized_for_monitoring?
    current_user.has_permission?("ai.monitor") ||
      current_user.has_permission?("ai.workflows.read") ||
      current_user.has_permission?("system.admin")
  end

  def serialize_workflow_run(workflow_run)
    {
      id: workflow_run.id,
      run_id: workflow_run.run_id,
      workflow_id: workflow_run.ai_workflow_id,
      workflow_name: workflow_run.workflow&.name,
      status: workflow_run.status,
      started_at: workflow_run.started_at&.iso8601,
      completed_at: workflow_run.completed_at&.iso8601,
      execution_time_ms: workflow_run.execution_time_ms,
      total_cost: workflow_run.total_cost
    }
  end

  def transmit_error(message)
    transmit({
      type: "error",
      error: message,
      timestamp: Time.current.iso8601
    })
  end
end
