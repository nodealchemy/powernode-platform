# frozen_string_literal: true

module Mcp
  # Mcp::ExecutionTracer - Execution tracing and debugging support
  #
  # Provides lightweight execution tracing for workflow debugging and analysis.
  # Records execution flow, timing, and key decision points without heavy overhead.
  #
  class ExecutionTracer
    attr_reader :workflow_run, :traces

    def initialize(workflow_run:)
      @workflow_run = workflow_run
      @traces = []
      @logger = Rails.logger
    end

    # Record workflow execution start
    def trace_start(workflow_info)
      @logger.info "[TRACER] Workflow execution started: #{workflow_info[:name]} (#{workflow_info[:run_id]})"

      add_trace(
        event: 'workflow_started',
        workflow_info: workflow_info,
        timestamp: Time.current.iso8601
      )
    end

    # Record node execution completion
    def trace_node_completion(node, result)
      @logger.debug "[TRACER] Node completed: #{node.node_id} (#{node.name})"

      add_trace(
        event: 'node_completed',
        node_id: node.node_id,
        node_name: node.name,
        node_type: node.node_type,
        duration_ms: result[:execution_time_ms],
        timestamp: Time.current.iso8601
      )
    end

    # Record node execution failure
    def trace_node_failure(node, error)
      @logger.error "[TRACER] Node failed: #{node.node_id} (#{node.name}) - #{error.message}"

      add_trace(
        event: 'node_failed',
        node_id: node.node_id,
        node_name: node.name,
        node_type: node.node_type,
        error_message: error.message,
        error_class: error.class.name,
        timestamp: Time.current.iso8601
      )
    end

    # Record workflow completion
    def trace_completion(status, output)
      @logger.info "[TRACER] Workflow completed: #{status}"

      add_trace(
        event: 'workflow_completed',
        status: status,
        output_summary: output&.dig(:execution_summary),
        timestamp: Time.current.iso8601
      )
    end

    # Record workflow failure
    def trace_failure(error)
      @logger.error "[TRACER] Workflow failed: #{error.message}"

      add_trace(
        event: 'workflow_failed',
        error_message: error.message,
        error_class: error.class.name,
        timestamp: Time.current.iso8601
      )
    end

    # Get all traces
    def all_traces
      @traces
    end

    private

    def add_trace(trace_data)
      @traces << trace_data

      # Optionally persist to workflow run metadata
      persist_trace(trace_data) if should_persist?
    end

    def should_persist?
      # Only persist in development/staging for debugging
      !Rails.env.production? || @workflow_run.runtime_context&.dig('debug_mode')
    end

    def persist_trace(trace_data)
      # Append trace to workflow run metadata
      current_traces = @workflow_run.runtime_context&.dig('execution_traces') || []
      current_traces << trace_data

      @workflow_run.update_column(
        :runtime_context,
        @workflow_run.runtime_context.merge('execution_traces' => current_traces)
      )
    rescue StandardError => e
      @logger.warn "[TRACER] Failed to persist trace: #{e.message}"
    end
  end
end
