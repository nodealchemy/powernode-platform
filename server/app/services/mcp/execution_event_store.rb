# frozen_string_literal: true

module Mcp
  # Mcp::ExecutionEventStore - Event sourcing store for workflow execution
  #
  # Implements event sourcing pattern to record complete workflow execution history.
  # Every significant action in a workflow becomes an immutable event, enabling:
  # - Complete execution audit trail
  # - Debugging and troubleshooting
  # - Execution replay and reconstruction
  # - Compliance and regulatory requirements
  # - Performance analysis and optimization
  #
  # Events are stored in chronological order with:
  # - Event type and timestamp
  # - Event data (payload)
  # - Causation and correlation tracking
  # - Metadata for context
  #
  # @example Recording events
  #   event_store = Mcp::ExecutionEventStore.new(workflow_run: run)
  #   event_store.record_event(
  #     event_type: 'node.execution.started',
  #     event_data: { node_id: 'xyz', node_type: 'ai_agent' }
  #   )
  #
  class ExecutionEventStore
    include ActiveModel::Model
    include ActiveModel::Attributes

    attr_reader :workflow_run, :events

    def initialize(workflow_run:)
      @workflow_run = workflow_run
      @events = []
      @event_sequence = 0
      @logger = Rails.logger
    end

    # =============================================================================
    # EVENT RECORDING
    # =============================================================================

    # Record a new event in the store
    #
    # @param event_type [String] Type of event (e.g., 'node.execution.started')
    # @param event_data [Hash] Event payload data
    # @param metadata [Hash] Additional metadata
    # @param causation_id [String] ID of event that caused this event
    # @param correlation_id [String] ID for correlating related events
    # @return [Hash] The recorded event
    def record_event(event_type:, event_data: {}, metadata: {}, causation_id: nil, correlation_id: nil)
      event = build_event(
        event_type: event_type,
        event_data: event_data,
        metadata: metadata,
        causation_id: causation_id,
        correlation_id: correlation_id
      )

      @events << event
      persist_event(event)

      @logger.debug "[EVENT_STORE] Recorded event: #{event_type} (#{event[:event_id]})"

      event
    end

    # Record multiple events in a batch
    #
    # @param events_data [Array<Hash>] Array of event data hashes
    # @return [Array<Hash>] Recorded events
    def record_events_batch(events_data)
      recorded_events = events_data.map do |event_params|
        record_event(**event_params)
      end

      @logger.info "[EVENT_STORE] Recorded batch of #{recorded_events.count} events"

      recorded_events
    end

    # =============================================================================
    # EVENT QUERYING
    # =============================================================================

    # Get all events
    #
    # @return [Array<Hash>] All events in chronological order
    def all_events
      @events
    end

    # Get events by type
    #
    # @param event_type [String, Array<String>] Event type(s) to filter
    # @return [Array<Hash>] Filtered events
    def events_by_type(event_type)
      types = Array(event_type)
      @events.select { |event| types.include?(event[:event_type]) }
    end

    # Get events within time range
    #
    # @param start_time [Time] Start of time range
    # @param end_time [Time] End of time range
    # @return [Array<Hash>] Events within range
    def events_in_range(start_time, end_time)
      @events.select do |event|
        event[:timestamp] >= start_time && event[:timestamp] <= end_time
      end
    end

    # Get events for specific node
    #
    # @param node_id [String] Node identifier
    # @return [Array<Hash>] Node-related events
    def events_for_node(node_id)
      @events.select do |event|
        event[:event_data][:node_id] == node_id ||
          event[:metadata][:node_id] == node_id
      end
    end

    # Get event by ID
    #
    # @param event_id [String] Event identifier
    # @return [Hash, nil] Event or nil if not found
    def find_event(event_id)
      @events.find { |event| event[:event_id] == event_id }
    end

    # Get latest event of type
    #
    # @param event_type [String] Event type
    # @return [Hash, nil] Latest event or nil
    def latest_event_of_type(event_type)
      events_by_type(event_type).last
    end

    # =============================================================================
    # EVENT ANALYSIS
    # =============================================================================

    # Get event count by type
    #
    # @return [Hash] Event type => count mapping
    def event_counts_by_type
      @events.group_by { |e| e[:event_type] }
             .transform_values(&:count)
    end

    # Get event timeline
    #
    # @return [Array<Hash>] Simplified timeline of events
    def event_timeline
      @events.map do |event|
        {
          time: event[:timestamp],
          type: event[:event_type],
          summary: summarize_event(event)
        }
      end
    end

    # Get execution statistics from events
    #
    # @return [Hash] Execution statistics
    def execution_statistics
      {
        total_events: @events.count,
        event_types: event_counts_by_type,
        first_event_time: @events.first&.dig(:timestamp),
        last_event_time: @events.last&.dig(:timestamp),
        duration_ms: calculate_event_duration,
        node_executions: count_node_executions,
        errors: count_errors
      }
    end

    # =============================================================================
    # EVENT REPLAY & RECONSTRUCTION
    # =============================================================================

    # Replay events to reconstruct state
    #
    # @param up_to_event_id [String] Replay up to this event ID (nil for all)
    # @return [Hash] Reconstructed state
    def replay_events(up_to_event_id: nil)
      state = initialize_replay_state

      events_to_replay = if up_to_event_id
                          events_until(up_to_event_id)
      else
                          @events
      end

      events_to_replay.each do |event|
        apply_event_to_state(event, state)
      end

      state
    end

    # Get state at specific point in time
    #
    # @param timestamp [Time] Point in time
    # @return [Hash] State at that time
    def state_at_time(timestamp)
      events_until_time = events_in_range(@events.first[:timestamp], timestamp)

      state = initialize_replay_state
      events_until_time.each do |event|
        apply_event_to_state(event, state)
      end

      state
    end

    # =============================================================================
    # EVENT STREAM EXPORT
    # =============================================================================

    # Export events as JSON stream
    #
    # @return [String] JSON formatted event stream
    def export_json_stream
      @events.map(&:to_json).join("\n")
    end

    # Export events to structured format
    #
    # @return [Hash] Structured event export
    def export_structured
      {
        workflow_run_id: @workflow_run.id,
        run_id: @workflow_run.run_id,
        workflow_id: @workflow_run.workflow_id,
        exported_at: Time.current.iso8601,
        event_count: @events.count,
        events: @events
      }
    end

    # Generate event log for debugging
    #
    # @return [String] Human-readable event log
    def generate_event_log
      lines = [ "Workflow Execution Event Log" ]
      lines << "=" * 80
      lines << "Workflow Run: #{@workflow_run.run_id}"
      lines << "Total Events: #{@events.count}"
      lines << "=" * 80
      lines << ""

      @events.each_with_index do |event, index|
        lines << "[#{index + 1}] #{event[:timestamp].strftime('%Y-%m-%d %H:%M:%S.%L')}"
        lines << "    Type: #{event[:event_type]}"
        lines << "    #{summarize_event(event)}"
        lines << "    Event ID: #{event[:event_id]}"
        lines << ""
      end

      lines.join("\n")
    end

    # =============================================================================
    # PERSISTENCE
    # =============================================================================

    # Persist event to database
    #
    # @param event [Hash] Event to persist
    def persist_event(event)
      # Reload to get fresh runtime_context from database (avoids circular references)
      @workflow_run.reload

      # Store in workflow run metadata
      current_events = @workflow_run.runtime_context&.dig("events") || []
      current_events << event

      @workflow_run.update_column(
        :runtime_context,
        (@workflow_run.runtime_context || {}).merge("events" => current_events)
      )
    rescue StandardError => e
      @logger.error "[EVENT_STORE] Failed to persist event: #{e.message}"
    end

    # Load events from database
    #
    # @return [Array<Hash>] Loaded events
    def load_events
      stored_events = @workflow_run.runtime_context&.dig("events") || []
      @events = stored_events.map { |e| symbolize_event(e) }
      @event_sequence = @events.count

      @logger.info "[EVENT_STORE] Loaded #{@events.count} events from storage"

      @events
    end

    # =============================================================================
    # PRIVATE METHODS
    # =============================================================================

    private

    def build_event(event_type:, event_data:, metadata:, causation_id:, correlation_id:)
      @event_sequence += 1

      {
        event_id: generate_event_id,
        event_type: event_type,
        event_data: event_data,
        metadata: metadata.merge(
          workflow_run_id: @workflow_run.id,
          run_id: @workflow_run.run_id,
          workflow_id: @workflow_run.workflow_id
        ),
        sequence_number: @event_sequence,
        timestamp: Time.current,
        causation_id: causation_id,
        correlation_id: correlation_id || @workflow_run.run_id
      }
    end

    def generate_event_id
      "evt_#{@workflow_run.run_id}_#{SecureRandom.hex(8)}"
    end

    def symbolize_event(event)
      return event if event.is_a?(Hash) && event.key?(:event_type)

      event.deep_symbolize_keys
    end

    def summarize_event(event)
      case event[:event_type]
      when "workflow.execution.initialized"
        "Workflow execution initialized"
      when "workflow.execution.completed"
        "Workflow execution completed (#{event[:event_data][:status]})"
      when "workflow.execution.failed"
        "Workflow execution failed: #{event[:event_data][:error_message]}"
      when "node.execution.started"
        "Node #{event[:event_data][:node_name] || event[:event_data][:node_id]} started"
      when "node.execution.completed"
        "Node #{event[:event_data][:node_id]} completed in #{event[:event_data][:duration_ms]}ms"
      when "node.execution.failed"
        "Node #{event[:event_data][:node_id]} failed: #{event[:event_data][:error_message]}"
      when "workflow.state.transitioned"
        "State transition: #{event[:event_data][:from_state]} -> #{event[:event_data][:to_state]}"
      when "workflow.validation.completed"
        "Workflow validation completed"
      when "workflow.compensation.started"
        "Compensation started due to: #{event[:event_data][:original_error]}"
      else
        "#{event[:event_type]}: #{event[:event_data].keys.join(', ')}"
      end
    end

    def events_until(event_id)
      index = @events.find_index { |e| e[:event_id] == event_id }
      return @events if index.nil?

      @events[0..index]
    end

    def initialize_replay_state
      {
        current_state: :pending,
        variables: {},
        node_results: {},
        execution_path: [],
        errors: []
      }
    end

    def apply_event_to_state(event, state)
      case event[:event_type]
      when "workflow.execution.initialized"
        state[:variables] = event[:event_data][:input_variables] || {}

      when "workflow.state.transitioned"
        state[:current_state] = event[:event_data][:to_state].to_sym

      when "node.execution.started"
        state[:execution_path] << event[:event_data][:node_id]

      when "node.execution.completed"
        node_id = event[:event_data][:node_id]
        state[:node_results][node_id] = {
          status: :completed,
          output: event[:event_data][:output_data],
          duration_ms: event[:event_data][:duration_ms]
        }

      when "node.execution.failed"
        node_id = event[:event_data][:node_id]
        state[:node_results][node_id] = {
          status: :failed,
          error: event[:event_data][:error_message]
        }
        state[:errors] << {
          node_id: node_id,
          error: event[:event_data][:error_message],
          timestamp: event[:timestamp]
        }
      end
    end

    def calculate_event_duration
      return 0 if @events.count < 2

      first_event = @events.first
      last_event = @events.last
      ((last_event[:timestamp] - first_event[:timestamp]) * 1000).round
    end

    def count_node_executions
      events_by_type("node.execution.started").count
    end

    def count_errors
      events_by_type([ "node.execution.failed", "workflow.execution.failed" ]).count
    end
  end
end
