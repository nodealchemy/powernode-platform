# frozen_string_literal: true

module Mcp
  # Mcp::WorkflowEventStore - Event sourcing for workflow execution
  #
  # Extracted from the monolithic WorkflowOrchestrator to focus on event recording.
  # This service provides complete event history for debugging, replay, and auditing.
  #
  # Responsibilities:
  # - Record all workflow execution events
  # - Provide event query and filtering
  # - Support event replay and debugging
  # - Enable audit trail and compliance
  #
  # Event Types:
  # - Execution events: started, completed, failed
  # - Node events: started, completed, failed
  # - State events: transitions, pauses, resumes
  # - Error events: failures, retries, recoveries
  #
  # Usage:
  #   store = Mcp::WorkflowEventStore.new(workflow_run: run)
  #   store.record_execution_started
  #   store.record_node_started(node, node_execution)
  #   events = store.get_events(event_type: 'node.started')
  #
  class WorkflowEventStore
    include BaseAiService

    # Event types
    EVENT_TYPES = %w[
      workflow.execution.started
      workflow.execution.completed
      workflow.execution.failed
      workflow.state.transitioned
      node.execution.started
      node.execution.completed
      node.execution.failed
      node.retry.attempted
      error.occurred
      compensation.triggered
    ].freeze

    attr_reader :workflow_run, :events

    def initialize(workflow_run:, **options)
      super(account: workflow_run.account, user: workflow_run.triggered_by_user, **options)

      @workflow_run = workflow_run
      @events = []
      @event_sequence = 0
    end

    # =============================================================================
    # EVENT RECORDING
    # =============================================================================

    # Record workflow execution started
    def record_execution_started
      record_event(
        event_type: 'workflow.execution.started',
        event_data: {
          workflow_id: @workflow_run.ai_workflow_id,
          workflow_name: @workflow_run.ai_workflow.name,
          run_id: @workflow_run.run_id,
          input_variables: @workflow_run.input_variables,
          triggered_by: @user&.id
        }
      )
    end

    # Record workflow execution completed
    #
    # @param result [Hash] Execution result
    def record_execution_completed(result)
      record_event(
        event_type: 'workflow.execution.completed',
        event_data: {
          workflow_id: @workflow_run.ai_workflow_id,
          run_id: @workflow_run.run_id,
          status: 'completed',
          duration_ms: result[:duration_ms],
          node_count: result[:node_count],
          total_cost: result[:total_cost],
          output_variables: result[:variables]
        }
      )
    end

    # Record workflow execution failed
    #
    # @param error [StandardError] Error that occurred
    def record_execution_failed(error)
      record_event(
        event_type: 'workflow.execution.failed',
        event_data: {
          workflow_id: @workflow_run.ai_workflow_id,
          run_id: @workflow_run.run_id,
          status: 'failed',
          error_message: error.message,
          error_class: error.class.name,
          backtrace: error.backtrace&.first(10)
        }
      )
    end

    # Record state transition
    #
    # @param from_state [String] Previous state
    # @param to_state [String] New state
    def record_state_transition(from_state, to_state)
      record_event(
        event_type: 'workflow.state.transitioned',
        event_data: {
          workflow_id: @workflow_run.ai_workflow_id,
          run_id: @workflow_run.run_id,
          from_state: from_state,
          to_state: to_state
        }
      )
    end

    # Record node execution started
    #
    # @param node [AiWorkflowNode] Node being executed
    # @param node_execution [AiWorkflowNodeExecution] Execution record
    def record_node_started(node, node_execution)
      record_event(
        event_type: 'node.execution.started',
        event_data: {
          workflow_id: @workflow_run.ai_workflow_id,
          run_id: @workflow_run.run_id,
          node_id: node.node_id,
          node_type: node.node_type,
          node_name: node.name,
          execution_id: node_execution.execution_id,
          input_data: node_execution.input_data
        }
      )
    end

    # Record node execution completed
    #
    # @param node [AiWorkflowNode] Executed node
    # @param node_execution [AiWorkflowNodeExecution] Execution record
    # @param result [Hash] Execution result
    def record_node_completed(node, node_execution, result)
      record_event(
        event_type: 'node.execution.completed',
        event_data: {
          workflow_id: @workflow_run.ai_workflow_id,
          run_id: @workflow_run.run_id,
          node_id: node.node_id,
          node_type: node.node_type,
          node_name: node.name,
          execution_id: node_execution.execution_id,
          duration_ms: result[:execution_time_ms],
          cost: result[:cost],
          output_data: result[:output_data]
        }
      )
    end

    # Record node execution failed
    #
    # @param node [AiWorkflowNode] Failed node
    # @param node_execution [AiWorkflowNodeExecution] Execution record
    # @param error [StandardError] Error that occurred
    def record_node_failed(node, node_execution, error)
      record_event(
        event_type: 'node.execution.failed',
        event_data: {
          workflow_id: @workflow_run.ai_workflow_id,
          run_id: @workflow_run.run_id,
          node_id: node.node_id,
          node_type: node.node_type,
          node_name: node.name,
          execution_id: node_execution.execution_id,
          error_message: error.message,
          error_class: error.class.name,
          backtrace: error.backtrace&.first(5)
        }
      )
    end

    # Record retry attempt
    #
    # @param node_id [String] Node ID
    # @param attempt [Integer] Retry attempt number
    # @param reason [String] Retry reason
    def record_retry_attempt(node_id, attempt, reason)
      record_event(
        event_type: 'node.retry.attempted',
        event_data: {
          workflow_id: @workflow_run.ai_workflow_id,
          run_id: @workflow_run.run_id,
          node_id: node_id,
          attempt: attempt,
          reason: reason
        }
      )
    end

    # Record error occurrence
    #
    # @param error [StandardError] Error that occurred
    # @param context [Hash] Error context
    def record_error(error, context = {})
      record_event(
        event_type: 'error.occurred',
        event_data: {
          workflow_id: @workflow_run.ai_workflow_id,
          run_id: @workflow_run.run_id,
          error_message: error.message,
          error_class: error.class.name,
          context: context,
          backtrace: error.backtrace&.first(10)
        }
      )
    end

    # Record compensation triggered
    #
    # @param node_id [String] Node ID being compensated
    # @param reason [String] Compensation reason
    def record_compensation(node_id, reason)
      record_event(
        event_type: 'compensation.triggered',
        event_data: {
          workflow_id: @workflow_run.ai_workflow_id,
          run_id: @workflow_run.run_id,
          node_id: node_id,
          reason: reason
        }
      )
    end

    # =============================================================================
    # GENERIC EVENT RECORDING
    # =============================================================================

    # Record a generic event
    #
    # @param event_type [String] Type of event
    # @param event_data [Hash] Event data
    # @param metadata [Hash] Additional metadata
    def record_event(event_type:, event_data: {}, metadata: {})
      with_monitoring('event_recording', event_type: event_type) do
        # Increment sequence
        @event_sequence += 1

        # Build event
        event = {
          event_id: SecureRandom.uuid,
          event_type: event_type,
          event_data: event_data,
          metadata: metadata.merge(
            sequence: @event_sequence,
            workflow_run_id: @workflow_run.id,
            recorded_at: Time.current.iso8601,
            recorded_by: self.class.name
          ),
          timestamp: Time.current
        }

        # Store event
        @events << event

        # Persist to database
        persist_event(event)

        # Log event
        log_debug "Event recorded: #{event_type}", {
          sequence: @event_sequence,
          event_id: event[:event_id]
        }

        event
      end
    end

    # =============================================================================
    # EVENT QUERYING
    # =============================================================================

    # Get all events
    #
    # @param filters [Hash] Filter criteria
    # @return [Array<Hash>] Filtered events
    def get_events(filters = {})
      events = @events.dup

      # Filter by event type
      if filters[:event_type].present?
        events = events.select { |e| e[:event_type] == filters[:event_type] }
      end

      # Filter by node ID
      if filters[:node_id].present?
        events = events.select { |e| e[:event_data][:node_id] == filters[:node_id] }
      end

      # Filter by time range
      if filters[:start_time].present?
        events = events.select { |e| e[:timestamp] >= filters[:start_time] }
      end

      if filters[:end_time].present?
        events = events.select { |e| e[:timestamp] <= filters[:end_time] }
      end

      # Sort by sequence
      events.sort_by { |e| e[:metadata][:sequence] }
    end

    # Get events by type
    #
    # @param event_type [String] Event type
    # @return [Array<Hash>] Events of specified type
    def get_events_by_type(event_type)
      get_events(event_type: event_type)
    end

    # Get events for node
    #
    # @param node_id [String] Node ID
    # @return [Array<Hash>] Events for specified node
    def get_events_for_node(node_id)
      get_events(node_id: node_id)
    end

    # Get event count
    #
    # @return [Integer] Total number of events
    def event_count
      @events.count
    end

    # Get latest event
    #
    # @return [Hash, nil] Latest event
    def latest_event
      @events.max_by { |e| e[:metadata][:sequence] }
    end

    # =============================================================================
    # EVENT REPLAY & DEBUGGING
    # =============================================================================

    # Build execution timeline from events
    #
    # @return [Array<Hash>] Timeline of execution
    def build_timeline
      timeline = []

      @events.each do |event|
        timeline << {
          sequence: event[:metadata][:sequence],
          timestamp: event[:timestamp],
          event_type: event[:event_type],
          summary: summarize_event(event),
          details: event[:event_data]
        }
      end

      timeline.sort_by { |t| t[:sequence] }
    end

    # Get execution summary from events
    #
    # @return [Hash] Execution summary
    def execution_summary
      {
        total_events: event_count,
        event_types: event_type_counts,
        duration: calculate_duration_from_events,
        nodes_executed: count_nodes_executed,
        errors: count_errors,
        retries: count_retries
      }
    end

    # Export events for debugging
    #
    # @param format [Symbol] Export format (:json, :csv)
    # @return [String] Exported events
    def export_events(format: :json)
      case format
      when :json
        @events.to_json
      when :csv
        # Simple CSV export
        events_to_csv
      else
        raise ArgumentError, "Unsupported format: #{format}"
      end
    end

    private

    # =============================================================================
    # PERSISTENCE
    # =============================================================================

    # Persist event to database
    #
    # @param event [Hash] Event to persist
    def persist_event(event)
      # Store in workflow run logs
      @workflow_run.ai_workflow_run_logs.create!(
        log_level: determine_log_level(event[:event_type]),
        log_type: event[:event_type],
        message: summarize_event(event),
        log_data: event[:event_data],
        metadata: event[:metadata]
      )
    rescue StandardError => e
      # Don't fail execution if event persistence fails
      log_error "Failed to persist event", {
        event_type: event[:event_type],
        error: e.message
      }
    end

    # =============================================================================
    # HELPERS
    # =============================================================================

    # Determine log level from event type
    #
    # @param event_type [String] Event type
    # @return [String] Log level
    def determine_log_level(event_type)
      case event_type
      when /failed|error/
        'error'
      when /retry|compensation/
        'warn'
      when /started|completed/
        'info'
      else
        'debug'
      end
    end

    # Summarize event for display
    #
    # @param event [Hash] Event to summarize
    # @return [String] Event summary
    def summarize_event(event)
      case event[:event_type]
      when 'workflow.execution.started'
        "Workflow execution started: #{event[:event_data][:workflow_name]}"
      when 'workflow.execution.completed'
        "Workflow execution completed (#{event[:event_data][:duration_ms]}ms)"
      when 'workflow.execution.failed'
        "Workflow execution failed: #{event[:event_data][:error_message]}"
      when 'node.execution.started'
        "Node started: #{event[:event_data][:node_name]} (#{event[:event_data][:node_type]})"
      when 'node.execution.completed'
        "Node completed: #{event[:event_data][:node_name]} (#{event[:event_data][:duration_ms]}ms)"
      when 'node.execution.failed'
        "Node failed: #{event[:event_data][:node_name]} - #{event[:event_data][:error_message]}"
      else
        event[:event_type]
      end
    end

    # Calculate duration from events
    #
    # @return [Integer, nil] Duration in milliseconds
    def calculate_duration_from_events
      start_event = @events.find { |e| e[:event_type] == 'workflow.execution.started' }
      end_event = @events.find { |e| e[:event_type] =~ /workflow.execution.(completed|failed)/ }

      return nil unless start_event && end_event

      ((end_event[:timestamp] - start_event[:timestamp]) * 1000).round
    end

    # Count nodes executed
    #
    # @return [Integer] Number of nodes executed
    def count_nodes_executed
      @events.count { |e| e[:event_type] == 'node.execution.started' }
    end

    # Count errors
    #
    # @return [Integer] Number of errors
    def count_errors
      @events.count { |e| e[:event_type] =~ /failed|error/ }
    end

    # Count retries
    #
    # @return [Integer] Number of retries
    def count_retries
      @events.count { |e| e[:event_type] == 'node.retry.attempted' }
    end

    # Get event type counts
    #
    # @return [Hash] Count by event type
    def event_type_counts
      @events.group_by { |e| e[:event_type] }
             .transform_values(&:count)
    end

    # Convert events to CSV
    #
    # @return [String] CSV representation
    def events_to_csv
      require 'csv'

      CSV.generate do |csv|
        # Headers
        csv << %w[Sequence Timestamp EventType Summary]

        # Rows
        @events.each do |event|
          csv << [
            event[:metadata][:sequence],
            event[:timestamp].iso8601,
            event[:event_type],
            summarize_event(event)
          ]
        end
      end
    end
  end
end
