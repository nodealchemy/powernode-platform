# frozen_string_literal: true

module Mcp
  # Mcp::WorkflowStateMachine - Formal state machine for workflow execution
  #
  # Manages workflow execution state with proper transitions, validation,
  # and state persistence. Implements a finite state machine pattern for
  # predictable workflow behavior.
  #
  # State Diagram:
  #   pending -> initializing -> running -> (completed|failed|cancelled)
  #   running -> paused -> running
  #   any -> cancelling -> cancelled
  #
  # Features:
  # - Formal state transition validation
  # - State persistence and recovery
  # - Event emission on state changes
  # - Timeout and deadline management
  # - State snapshot for debugging
  #
  class WorkflowStateMachine
    include ActiveModel::Model
    include ActiveModel::Attributes

    class StateTransitionError < StandardError; end
    class InvalidStateError < StandardError; end

    # Define all valid workflow states
    STATES = %i[
      pending
      initializing
      running
      paused
      completed
      failed
      cancelled
      cancelling
      timeout
      compensating
    ].freeze

    # Define valid state transitions
    TRANSITIONS = {
      pending: %i[initializing cancelled],
      initializing: %i[running failed cancelled],
      running: %i[paused completed failed cancelled cancelling timeout compensating],
      paused: %i[running cancelled cancelling],
      completed: [],  # Terminal state
      failed: %i[compensating],  # Can attempt compensation
      cancelled: [],  # Terminal state
      cancelling: %i[cancelled],
      timeout: %i[failed compensating],
      compensating: %i[completed failed]
    }.freeze

    attr_reader :workflow_run, :current_state, :state_history, :node_states

    def initialize(workflow_run:)
      @workflow_run = workflow_run
      @current_state = workflow_run.status.to_sym
      @state_history = []
      @node_states = {}
      @transition_callbacks = {}
      @logger = Rails.logger
    end

    # =============================================================================
    # STATE INITIALIZATION
    # =============================================================================

    def initialize_state(execution_context = {})
      @logger.info "[STATE_MACHINE] Initializing state machine for run #{@workflow_run.run_id}"

      # Record initial state
      @state_history << {
        state: @current_state,
        timestamp: Time.current,
        context: execution_context.slice(:workflow_id, :run_id, :user_id)
      }

      # Initialize node state tracking
      @node_states = {}

      @current_state
    end

    # =============================================================================
    # STATE TRANSITIONS
    # =============================================================================

    # Transition to a new state with validation
    #
    # @param from_state [Symbol] Expected current state
    # @param to_state [Symbol] Desired target state
    # @param reason [String] Optional reason for transition
    # @return [Symbol] New current state
    # @raise [StateTransitionError] if transition is invalid
    def transition!(from_state, to_state, reason: nil)
      from_state = from_state.to_sym
      to_state = to_state.to_sym

      @logger.info "[STATE_MACHINE] Attempting transition: #{from_state} -> #{to_state}"

      # Validate states exist
      validate_state!(from_state)
      validate_state!(to_state)

      # Check current state matches expected
      unless @current_state == from_state
        raise StateTransitionError,
              "Current state mismatch: expected #{from_state}, got #{@current_state}"
      end

      # Check transition is valid
      unless can_transition?(from_state, to_state)
        raise StateTransitionError,
              "Invalid transition from #{from_state} to #{to_state}. " \
              "Valid transitions: #{TRANSITIONS[from_state].join(', ')}"
      end

      # Perform transition
      execute_transition(from_state, to_state, reason)

      @current_state
    end

    # Check if a transition is valid without executing it
    #
    # @param from_state [Symbol] Current state
    # @param to_state [Symbol] Target state
    # @return [Boolean] Whether transition is allowed
    def can_transition?(from_state, to_state)
      from_state = from_state.to_sym
      to_state = to_state.to_sym

      return false unless STATES.include?(from_state) && STATES.include?(to_state)
      return true if from_state == to_state  # Allow no-op transitions

      valid_transitions = TRANSITIONS[from_state] || []
      valid_transitions.include?(to_state)
    end

    # Force a state change (for recovery scenarios)
    #
    # @param to_state [Symbol] Target state
    # @param reason [String] Reason for forced transition
    def force_transition!(to_state, reason:)
      to_state = to_state.to_sym
      validate_state!(to_state)

      @logger.warn "[STATE_MACHINE] Forcing state transition to #{to_state}: #{reason}"

      from_state = @current_state
      execute_transition(from_state, to_state, "FORCED: #{reason}")
    end

    # =============================================================================
    # NODE STATE TRACKING
    # =============================================================================

    # Track execution of a specific node
    #
    # @param node_id [String] Node identifier
    def execute_node(node_id)
      @logger.debug "[STATE_MACHINE] Node execution started: #{node_id}"

      @node_states[node_id] = {
        state: :executing,
        started_at: Time.current
      }
    end

    # Mark node as completed
    #
    # @param node_id [String] Node identifier
    # @param result [Hash] Node execution result
    def complete_node(node_id, result = {})
      @logger.debug "[STATE_MACHINE] Node execution completed: #{node_id}"

      if @node_states[node_id]
        @node_states[node_id].merge!({
          state: :completed,
          completed_at: Time.current,
          result: result
        })
      end
    end

    # Mark node as failed
    #
    # @param node_id [String] Node identifier
    # @param error [StandardError, String] Error that caused failure
    def fail_node(node_id, error)
      @logger.debug "[STATE_MACHINE] Node execution failed: #{node_id}"

      if @node_states[node_id]
        @node_states[node_id].merge!({
          state: :failed,
          failed_at: Time.current,
          error: error.is_a?(StandardError) ? error.message : error.to_s
        })
      end
    end

    # =============================================================================
    # STATE QUERIES
    # =============================================================================

    # Check if workflow is in a running state
    #
    # @return [Boolean]
    def running?
      @current_state == :running
    end

    # Check if workflow is in a terminal state
    #
    # @return [Boolean]
    def terminal?
      %i[completed failed cancelled].include?(@current_state)
    end

    # Check if workflow is paused
    #
    # @return [Boolean]
    def paused?
      @current_state == :paused
    end

    # Check if workflow can be paused
    #
    # @return [Boolean]
    def can_pause?
      can_transition?(@current_state, :paused)
    end

    # Check if workflow can be resumed
    #
    # @return [Boolean]
    def can_resume?
      paused? && can_transition?(:paused, :running)
    end

    # Check if workflow can be cancelled
    #
    # @return [Boolean]
    def can_cancel?
      !terminal? && can_transition?(@current_state, :cancelling)
    end

    # Get nodes currently executing
    #
    # @return [Array<String>] Node IDs
    def executing_nodes
      @node_states.select { |_id, state| state[:state] == :executing }.keys
    end

    # Get nodes that have completed
    #
    # @return [Array<String>] Node IDs
    def completed_nodes
      @node_states.select { |_id, state| state[:state] == :completed }.keys
    end

    # Get nodes that have failed
    #
    # @return [Array<String>] Node IDs
    def failed_nodes
      @node_states.select { |_id, state| state[:state] == :failed }.keys
    end

    # =============================================================================
    # STATE CALLBACKS
    # =============================================================================

    # Register a callback for state transitions
    #
    # @param from_state [Symbol] State to transition from (nil for any)
    # @param to_state [Symbol] State to transition to
    # @param block [Proc] Callback to execute
    def on_transition(from_state: nil, to_state:, &block)
      key = [ from_state, to_state ].compact.join("_to_")
      @transition_callbacks[key] ||= []
      @transition_callbacks[key] << block
    end

    # =============================================================================
    # STATE PERSISTENCE
    # =============================================================================

    # Create a snapshot of current state
    #
    # @return [Hash] State snapshot
    def snapshot
      {
        current_state: @current_state,
        state_history: @state_history,
        node_states: @node_states,
        timestamp: Time.current.iso8601,
        workflow_run_id: @workflow_run.id
      }
    end

    # Restore state from a snapshot
    #
    # @param snapshot_data [Hash] Snapshot to restore
    def restore_from_snapshot(snapshot_data)
      @logger.info "[STATE_MACHINE] Restoring state from snapshot"

      @current_state = snapshot_data[:current_state].to_sym
      @state_history = snapshot_data[:state_history] || []
      @node_states = snapshot_data[:node_states] || {}

      # Update workflow run status
      @workflow_run.update_column(:status, @current_state.to_s)
    end

    # Persist current state to database
    def persist_state!
      state_data = snapshot

      # Reload to get fresh runtime_context from database (avoids circular references)
      @workflow_run.reload

      # Build new runtime_context by merging state snapshot
      # Exclude state_machine_snapshot from current context to avoid nesting
      current_context = (@workflow_run.runtime_context || {}).except("state_machine_snapshot", :state_machine_snapshot)

      @workflow_run.update_columns(
        status: @current_state.to_s,
        runtime_context: current_context.merge(
          state_machine_snapshot: state_data
        )
      )
    end

    # =============================================================================
    # STATE HISTORY & DEBUGGING
    # =============================================================================

    # Get complete state transition history
    #
    # @return [Array<Hash>] State transition history
    def transition_history
      @state_history
    end

    # Get duration in current state
    #
    # @return [Float] Duration in seconds
    def time_in_current_state
      return 0 if @state_history.empty?

      last_transition = @state_history.last
      Time.current - last_transition[:timestamp]
    end

    # Get total execution time
    #
    # @return [Float] Duration in seconds
    def total_execution_time
      return 0 if @state_history.empty?

      first_transition = @state_history.first
      Time.current - first_transition[:timestamp]
    end

    # Generate state diagram for debugging
    #
    # @return [String] Mermaid state diagram
    def generate_state_diagram
      transitions = @state_history.map do |entry|
        "  #{entry[:state]}"
      end.join(" --> ")

      <<~MERMAID
        stateDiagram-v2
          #{transitions}

          note right of #{@current_state}
            Current State
            Duration: #{time_in_current_state.round(2)}s
          end note
      MERMAID
    end

    # =============================================================================
    # PRIVATE METHODS
    # =============================================================================

    private

    def validate_state!(state)
      state = state.to_sym

      unless STATES.include?(state)
        raise InvalidStateError, "Invalid state: #{state}. Valid states: #{STATES.join(', ')}"
      end
    end

    def execute_transition(from_state, to_state, reason)
      @logger.info "[STATE_MACHINE] Executing transition: #{from_state} -> #{to_state}"

      # Record transition in history
      transition_record = {
        from_state: from_state,
        to_state: to_state,
        timestamp: Time.current,
        reason: reason
      }

      @state_history << transition_record

      # Update current state
      @current_state = to_state

      # Update workflow run status with proper timestamps for terminal states
      current_time = Time.current
      update_attrs = { status: to_state.to_s }

      # Set appropriate timestamps for terminal states
      case to_state
      when :completed, :failed
        # Ensure started_at is set (defensive coding)
        if @workflow_run.started_at.nil?
          update_attrs[:started_at] = current_time - 1.second
          @logger.warn "[STATE_MACHINE] Setting started_at retroactively for #{to_state} transition"
        end
        # Always set completed_at for terminal states
        update_attrs[:completed_at] = current_time
      when :cancelled
        # Ensure started_at is set (defensive coding)
        if @workflow_run.started_at.nil?
          update_attrs[:started_at] = current_time - 1.second
          @logger.warn "[STATE_MACHINE] Setting started_at retroactively for cancelled transition"
        end
        update_attrs[:cancelled_at] = current_time
        update_attrs[:completed_at] = current_time
      when :running
        # Set started_at when transitioning to running (if not already set)
        update_attrs[:started_at] = current_time if @workflow_run.started_at.nil?
      end

      # Use update_columns (plural) to set multiple fields atomically
      @workflow_run.update_columns(update_attrs)

      # CRITICAL: update_columns bypasses callbacks, so we must manually broadcast status changes
      # This ensures the frontend receives real-time status updates
      broadcast_status_change(from_state, to_state, update_attrs)

      # Execute transition callbacks
      execute_callbacks(from_state, to_state, transition_record)

      # Persist state
      persist_state!

      @logger.info "[STATE_MACHINE] Transition completed: #{from_state} -> #{to_state}"
    end

    def execute_callbacks(from_state, to_state, transition_record)
      # Execute specific transition callbacks
      specific_key = "#{from_state}_to_#{to_state}"
      if @transition_callbacks[specific_key]
        @transition_callbacks[specific_key].each do |callback|
          callback.call(transition_record)
        end
      end

      # Execute wildcard callbacks (any -> to_state)
      wildcard_key = to_state.to_s
      if @transition_callbacks[wildcard_key]
        @transition_callbacks[wildcard_key].each do |callback|
          callback.call(transition_record)
        end
      end
    end

    def broadcast_status_change(from_state, to_state, update_attrs)
      # Since we use update_columns which bypasses callbacks, manually broadcast status changes
      # This replicates the broadcast_status_change callback in AiWorkflowRun model
      @logger.debug "[STATE_MACHINE] Broadcasting status change: #{from_state} -> #{to_state}"

      # Reload to get updated values
      @workflow_run.reload

      workflow_run_data = {
        id: @workflow_run.id,
        run_id: @workflow_run.run_id,
        ai_workflow_id: @workflow_run.ai_workflow_id,
        status: @workflow_run.status,
        trigger_type: @workflow_run.trigger_type,
        started_at: @workflow_run.started_at,
        completed_at: @workflow_run.completed_at,
        created_at: @workflow_run.created_at,
        duration_seconds: @workflow_run.execution_duration_seconds || (@workflow_run.started_at ? (Time.current - @workflow_run.started_at).to_i : nil),
        total_nodes: @workflow_run.total_nodes,
        completed_nodes: @workflow_run.completed_nodes,
        failed_nodes: @workflow_run.failed_nodes,
        cost_usd: @workflow_run.total_cost,
        error_details: @workflow_run.error_details,
        progress_percentage: @workflow_run.progress_percentage
      }

      # Broadcast via AiOrchestrationChannel
      # This broadcasts to:
      # - ai_orchestration:workflow_run:{run_id} (run-specific)
      # - ai_orchestration:workflow:{workflow_id} (workflow-level for history updates)
      # - ai_orchestration:account:{account_id} (account-level)
      AiOrchestrationChannel.broadcast_workflow_run_event(
        "workflow.run.status.changed",
        @workflow_run,
        {
          workflow_run: workflow_run_data,
          workflow_stats: @workflow_run.ai_workflow.respond_to?(:stats) ? @workflow_run.ai_workflow.stats : {}
        }
      )

      @logger.info "[STATE_MACHINE] Broadcasted status change: #{from_state} -> #{to_state}"
    end
  end
end
