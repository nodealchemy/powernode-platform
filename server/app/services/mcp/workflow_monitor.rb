# frozen_string_literal: true

module Mcp
  # Mcp::WorkflowMonitor - Real-time workflow execution monitoring
  #
  # Provides monitoring and telemetry for workflow execution including:
  # - Execution progress tracking
  # - Performance metrics
  # - Resource utilization
  # - Real-time status broadcasting
  #
  class WorkflowMonitor
    attr_reader :workflow_run, :metrics

    def initialize(workflow_run:)
      @workflow_run = workflow_run
      @logger = Rails.logger
      @metrics = {
        nodes_completed: 0,
        nodes_failed: 0,
        total_duration_ms: 0,
        total_cost: 0.0
      }
      @started_at = nil
    end

    # Start monitoring the workflow execution
    def start_monitoring(execution_context)
      @started_at = Time.current
      @execution_context = execution_context

      @logger.info "[MONITOR] Monitoring started for workflow run #{@workflow_run.run_id}"

      # Broadcast monitoring start event
      broadcast_event("monitoring_started", {
        run_id: @workflow_run.run_id,
        started_at: @started_at.iso8601
      })
    end

    # Record node completion
    def node_completed(node, result)
      @metrics[:nodes_completed] += 1
      @metrics[:total_duration_ms] += result[:execution_time_ms] || 0
      @metrics[:total_cost] += result[:cost] || 0.0

      @logger.debug "[MONITOR] Node completed: #{node.name} (#{@metrics[:nodes_completed]} total)"

      # NOTE: Progress is tracked automatically via AiWorkflowNodeExecution.update_run_progress
      # which updates completed_nodes/failed_nodes columns and triggers broadcasts

      # Broadcast node completion
      broadcast_event("node_completed", {
        node_id: node.node_id,
        node_name: node.name,
        progress_percentage: calculate_progress_percentage
      })
    end

    # Record node failure
    def node_failed(node, error)
      @metrics[:nodes_failed] += 1

      @logger.error "[MONITOR] Node failed: #{node.name} (#{@metrics[:nodes_failed]} failures)"

      # NOTE: Progress is tracked automatically via AiWorkflowNodeExecution.update_run_progress
      # which updates completed_nodes/failed_nodes columns and triggers broadcasts

      # Broadcast node failure
      broadcast_event("node_failed", {
        node_id: node.node_id,
        node_name: node.name,
        error_message: error.message,
        progress_percentage: calculate_progress_percentage
      })
    end

    # Finalize monitoring
    def finalize
      duration = @started_at ? (Time.current - @started_at) * 1000 : 0

      @logger.info "[MONITOR] Monitoring finalized for workflow run #{@workflow_run.run_id}"
      @logger.info "[MONITOR] Final metrics: #{@metrics.inspect}"

      # Broadcast monitoring completion
      broadcast_event("monitoring_completed", {
        run_id: @workflow_run.run_id,
        duration_ms: duration.round,
        metrics: @metrics
      })
    end

    # Get current metrics
    def current_metrics
      @metrics.merge(
        elapsed_ms: elapsed_time_ms,
        progress_percentage: calculate_progress_percentage
      )
    end

    private

    def calculate_progress_percentage
      total_nodes = @workflow_run.workflow.node_count
      return 0 if total_nodes == 0

      completed_nodes = @metrics[:nodes_completed]
      ((completed_nodes.to_f / total_nodes) * 100).round(2)
    end

    def elapsed_time_ms
      return 0 unless @started_at

      ((Time.current - @started_at) * 1000).round
    end

    def broadcast_event(event_type, data)
      # Broadcast via ActionCable if available
      return unless defined?(McpBroadcastService)

      McpBroadcastService.broadcast_workflow_event(
        event_type,
        @workflow_run.workflow_id,
        {
          workflow_run_id: @workflow_run.id,
          run_id: @workflow_run.run_id,
          **data,
          timestamp: Time.current.iso8601
        },
        @workflow_run.account
      )
    rescue StandardError => e
      @logger.warn "[MONITOR] Failed to broadcast event: #{e.message}"
    end
  end
end
