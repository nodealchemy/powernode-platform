# frozen_string_literal: true

module AiWorkflowRun::Broadcasting
  extend ActiveSupport::Concern

  included do
    # Callbacks for real-time broadcasting
    after_update :broadcast_status_change, if: :saved_change_to_status?
    after_update :broadcast_progress_change, if: -> { saved_change_to_completed_nodes? || saved_change_to_failed_nodes? }
    after_update :broadcast_duration_update, if: -> { running? && !saved_change_to_status? && !saved_change_to_completed_nodes? && !saved_change_to_failed_nodes? }
    after_create :broadcast_execution_started
    after_update :broadcast_execution_completed, if: -> { saved_change_to_status? && status == "completed" }
    after_update :broadcast_execution_failed, if: -> { saved_change_to_status? && status == "failed" }

    # Account-level monitoring broadcasts (for dashboard real-time updates)
    after_commit :broadcast_monitoring_dashboard_update, if: :saved_change_to_status?
  end

  # Public method to manually trigger duration updates (can be called from external services)
  def broadcast_live_duration!
    broadcast_duration_update if running?
  end

  private

  def broadcast_status_change
    # Prepare common workflow run data
    workflow_run_data = build_workflow_run_data

    # Broadcast to run-specific channel (for workflow execution modal)
    AiOrchestrationChannel.broadcast_workflow_run_event(
      "workflow.run.status.changed",
      self,
      {
        workflow_run: workflow_run_data,
        workflow_stats: ai_workflow.respond_to?(:stats) ? ai_workflow.stats : {}
      }
    )

    # Broadcast to workflow-level channel (for workflow history updates)
    ActionCable.server.broadcast(
      "workflow_#{ai_workflow_id}",
      {
        type: "workflow_run_status_changed",
        workflow_run: workflow_run_data,
        workflow_stats: ai_workflow.respond_to?(:stats) ? ai_workflow.stats : {},
        timestamp: Time.current.iso8601
      }
    )
  end

  def broadcast_progress_change
    # Broadcast progress updates without status change
    workflow_run_data = build_workflow_run_data

    # Broadcast to run-specific channel (for workflow execution modal)
    AiOrchestrationChannel.broadcast_workflow_run_event(
      "workflow.run.progress.changed",
      self,
      {
        workflow_run: workflow_run_data,
        event_type: "progress_changed"
      }
    )

    # Broadcast to workflow-level channel (for workflow history updates)
    ActionCable.server.broadcast(
      "workflow_#{ai_workflow_id}",
      {
        type: "workflow_progress_changed",
        workflow_run: workflow_run_data,
        workflow_stats: ai_workflow.respond_to?(:stats) ? ai_workflow.stats : {},
        timestamp: Time.current.iso8601
      }
    )
  end

  def broadcast_duration_update
    # Broadcast live duration updates for running workflows
    return unless running? && started_at

    workflow_run_data = build_workflow_run_data(live_duration: true)

    # Broadcast to run-specific channel (for workflow execution modal)
    AiOrchestrationChannel.broadcast_workflow_run_event(
      "workflow.run.duration.updated",
      self,
      {
        workflow_run: workflow_run_data,
        event_type: "duration_update"
      }
    )

    # Broadcast to workflow-level channel (for workflow history updates)
    ActionCable.server.broadcast(
      "workflow_#{ai_workflow_id}",
      {
        type: "workflow_duration_update",
        workflow_run: workflow_run_data,
        workflow_stats: ai_workflow.respond_to?(:stats) ? ai_workflow.stats : {},
        timestamp: Time.current.iso8601
      }
    )

    Rails.logger.debug "[AI_WORKFLOW_RUN] Duration update broadcast sent for run #{run_id}: #{workflow_run_data[:duration_seconds]}s"
  end

  def broadcast_execution_started
    workflow_run_data = {
      id: id,
      run_id: run_id,
      workflow_id: ai_workflow_id,
      trigger_type: trigger_type,
      status: status,
      started_at: started_at,
      total_nodes: total_nodes
    }

    # Broadcast to run-specific channel
    AiOrchestrationChannel.broadcast_workflow_run_event(
      "workflow.execution.started",
      self,
      {
        workflow_run: workflow_run_data,
        event_type: "execution_started"
      }
    )

    # Broadcast to workflow-level channel
    ActionCable.server.broadcast(
      "workflow_#{ai_workflow_id}",
      {
        type: "workflow_execution_started",
        workflow_run: workflow_run_data,
        timestamp: Time.current.iso8601
      }
    )
  end

  def broadcast_execution_completed
    workflow_run_data = {
      id: id,
      run_id: run_id,
      workflow_id: ai_workflow_id,
      trigger_type: trigger_type,
      status: status,
      completed_at: completed_at,
      duration_seconds: execution_duration_seconds,
      completed_nodes: completed_nodes,
      failed_nodes: failed_nodes,
      cost_usd: total_cost,
      output_variables: output_variables,
      progress_percentage: progress_percentage
    }

    # Broadcast to run-specific channel
    AiOrchestrationChannel.broadcast_workflow_run_event(
      "workflow.execution.completed",
      self,
      {
        workflow_run: workflow_run_data,
        workflow_stats: ai_workflow.respond_to?(:stats) ? ai_workflow.stats : {},
        event_type: "execution_completed"
      }
    )

    # Broadcast to workflow-level channel
    ActionCable.server.broadcast(
      "workflow_#{ai_workflow_id}",
      {
        type: "workflow_execution_completed",
        workflow_run: workflow_run_data,
        workflow_stats: ai_workflow.respond_to?(:stats) ? ai_workflow.stats : {},
        timestamp: Time.current.iso8601
      }
    )
  end

  def broadcast_execution_failed
    workflow_run_data = {
      id: id,
      run_id: run_id,
      workflow_id: ai_workflow_id,
      trigger_type: trigger_type,
      status: status,
      output_variables: output_variables,
      error_details: error_details,
      failed_at: completed_at,
      duration_seconds: execution_duration_seconds,
      progress_percentage: progress_percentage
    }

    # Broadcast to run-specific channel
    AiOrchestrationChannel.broadcast_workflow_run_event(
      "workflow.execution.failed",
      self,
      {
        workflow_run: workflow_run_data,
        event_type: "execution_failed"
      }
    )

    # Broadcast to workflow-level channel
    ActionCable.server.broadcast(
      "workflow_#{ai_workflow_id}",
      {
        type: "workflow_execution_failed",
        workflow_run: workflow_run_data,
        timestamp: Time.current.iso8601
      }
    )
  end

  def build_workflow_run_data(live_duration: false)
    duration = if live_duration && running? && started_at
                 (Time.current - started_at).to_i
               else
                 execution_duration_seconds || (started_at ? (Time.current - started_at).to_i : nil)
               end

    {
      id: id,
      run_id: run_id,
      ai_workflow_id: ai_workflow_id,
      status: status,
      trigger_type: trigger_type,
      started_at: started_at,
      completed_at: completed_at,
      created_at: created_at,
      duration_seconds: duration,
      total_nodes: total_nodes,
      completed_nodes: completed_nodes,
      failed_nodes: failed_nodes,
      cost_usd: total_cost,
      output_variables: output_variables,
      error_details: error_details,
      progress_percentage: progress_percentage
    }
  end

  def broadcast_monitoring_dashboard_update
    # Broadcast dashboard stats to account-level monitoring channel
    # This enables real-time dashboard updates without polling
    AiWorkflowMonitoringChannel.broadcast_dashboard_update(account_id)
  rescue StandardError => e
    Rails.logger.warn "[AI_WORKFLOW_RUN] Failed to broadcast monitoring update for account #{account_id}: #{e.message}"
  end
end
