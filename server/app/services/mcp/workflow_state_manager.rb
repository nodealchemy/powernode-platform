# frozen_string_literal: true

module Mcp
  # Mcp::WorkflowStateManager - Manages workflow execution state transitions
  #
  # Extracted from the monolithic WorkflowOrchestrator to focus on state management.
  # This service ensures valid state transitions and maintains state consistency.
  #
  # Responsibilities:
  # - Manage workflow run state transitions
  # - Validate state transition rules
  # - Track current execution state
  # - Broadcast state changes
  #
  # State Machine:
  #   pending → initializing → running → [completed | failed | cancelled]
  #                                   ↓
  #                                 paused → running
  #
  # Usage:
  #   manager = Mcp::WorkflowStateManager.new(workflow_run: run)
  #   manager.transition!(:pending, :initializing)
  #   manager.transition!(:initializing, :running)
  #   manager.transition_to_completed
  #
  class WorkflowStateManager
    include BaseAiService

    # Valid workflow states
    VALID_STATES = %w[
      pending
      initializing
      running
      paused
      completed
      failed
      cancelled
    ].freeze

    # Valid state transitions
    STATE_TRANSITIONS = {
      "pending" => %w[initializing cancelled],
      "initializing" => %w[running failed cancelled],
      "running" => %w[paused completed failed cancelled],
      "paused" => %w[running cancelled failed],
      "completed" => [],  # Terminal state
      "failed" => [],     # Terminal state
      "cancelled" => []   # Terminal state
    }.freeze

    class StateTransitionError < StandardError; end
    class InvalidStateError < StandardError; end

    attr_reader :workflow_run, :current_state

    def initialize(workflow_run:, **options)
      super(account: workflow_run.account, user: workflow_run.triggered_by_user, **options)

      @workflow_run = workflow_run
      @current_state = workflow_run.status
      @state_history = []
    end

    # =============================================================================
    # STATE TRANSITIONS
    # =============================================================================

    # Transition from one state to another
    #
    # @param from_state [Symbol, String] Expected current state
    # @param to_state [Symbol, String] Target state
    # @raise [StateTransitionError] if transition is invalid
    def transition!(from_state, to_state)
      from_state = from_state.to_s
      to_state = to_state.to_s

      with_monitoring("state_transition", from: from_state, to: to_state) do
        log_info "State transition: #{from_state} → #{to_state}"

        # Use row-level locking to prevent race conditions during state transitions
        @workflow_run.with_lock do
          # Reload to get fresh state after acquiring lock
          @workflow_run.reload
          @current_state = @workflow_run.status

          # Validate states
          validate_state!(from_state)
          validate_state!(to_state)

          # Validate current state matches expected
          unless @current_state == from_state
            raise StateTransitionError,
                  "Current state is #{@current_state}, expected #{from_state}"
          end

          # Validate transition is allowed
          validate_transition!(from_state, to_state)

          # Perform transition (within the lock)
          perform_transition(to_state)
        end

        # Broadcast state change (outside the lock to avoid blocking)
        broadcast_state_change(from_state, to_state)

        log_info "State transition completed", {
          from: from_state,
          to: to_state,
          workflow_id: @workflow_run.workflow_id,
          run_id: @workflow_run.run_id
        }
      end
    end

    # Transition to running state (from any valid previous state)
    def transition_to_running
      case @current_state
      when "pending"
        transition!(:pending, :initializing)
        transition!(:initializing, :running)
      when "initializing"
        transition!(:initializing, :running)
      when "paused"
        transition!(:paused, :running)
      else
        raise StateTransitionError, "Cannot transition to running from #{@current_state}"
      end
    end

    # Transition to paused state
    def transition_to_paused
      transition!(:running, :paused)
    end

    # Transition to completed state
    def transition_to_completed
      case @current_state
      when "running"
        transition!(:running, :completed)
      when "paused"
        # Resume then complete
        transition!(:paused, :running)
        transition!(:running, :completed)
      else
        raise StateTransitionError, "Cannot transition to completed from #{@current_state}"
      end
    end

    # Transition to failed state
    def transition_to_failed
      # Failed can be reached from most non-terminal states
      valid_from_states = %w[initializing running paused]

      if valid_from_states.include?(@current_state)
        transition!(@current_state.to_sym, :failed)
      else
        raise StateTransitionError, "Cannot transition to failed from #{@current_state}"
      end
    end

    # Transition to cancelled state
    def transition_to_cancelled
      # Cancelled can be reached from most non-terminal states
      valid_from_states = %w[pending initializing running paused]

      if valid_from_states.include?(@current_state)
        transition!(@current_state.to_sym, :cancelled)
      else
        raise StateTransitionError, "Cannot transition to cancelled from #{@current_state}"
      end
    end

    # =============================================================================
    # NODE STATE TRACKING
    # =============================================================================

    # Track node execution start
    #
    # @param node_id [String] Node ID
    def execute_node(node_id)
      with_monitoring("node_state_change", node_id: node_id, state: "executing") do
        log_debug "Node entering execution", { node_id: node_id }

        # Update internal state tracking if needed
        # (Could track executing nodes for monitoring)
      end
    end

    # Track node execution completion
    #
    # @param node_id [String] Node ID
    # @param success [Boolean] Whether node succeeded
    def complete_node(node_id, success:)
      state = success ? "completed" : "failed"

      with_monitoring("node_state_change", node_id: node_id, state: state) do
        log_debug "Node #{state}", { node_id: node_id }
      end
    end

    # =============================================================================
    # STATE QUERIES
    # =============================================================================

    # Check if workflow is in a terminal state
    #
    # @return [Boolean] Whether state is terminal
    def terminal_state?
      terminal_states.include?(@current_state)
    end

    # Check if workflow can be paused
    #
    # @return [Boolean] Whether workflow can be paused
    def can_pause?
      @current_state == "running"
    end

    # Check if workflow can be resumed
    #
    # @return [Boolean] Whether workflow can be resumed
    def can_resume?
      @current_state == "paused"
    end

    # Check if workflow can be cancelled
    #
    # @return [Boolean] Whether workflow can be cancelled
    def can_cancel?
      !terminal_state?
    end

    # Get state history
    #
    # @return [Array<Hash>] State transition history
    def state_history
      @state_history.dup
    end

    # Get terminal states
    #
    # @return [Array<String>] Terminal state names
    def terminal_states
      %w[completed failed cancelled]
    end

    private

    # =============================================================================
    # VALIDATION
    # =============================================================================

    # Validate state is valid
    #
    # @param state [String] State to validate
    # @raise [InvalidStateError] if state is invalid
    def validate_state!(state)
      unless VALID_STATES.include?(state)
        raise InvalidStateError, "Invalid state: #{state}. Valid states: #{VALID_STATES.join(', ')}"
      end
    end

    # Validate transition is allowed
    #
    # @param from_state [String] Source state
    # @param to_state [String] Target state
    # @raise [StateTransitionError] if transition is invalid
    def validate_transition!(from_state, to_state)
      allowed_states = STATE_TRANSITIONS[from_state]

      unless allowed_states.include?(to_state)
        raise StateTransitionError,
              "Invalid transition from #{from_state} to #{to_state}. " \
              "Allowed transitions: #{allowed_states.join(', ')}"
      end
    end

    # =============================================================================
    # TRANSITION EXECUTION
    # =============================================================================

    # Perform the actual state transition
    #
    # @param to_state [String] Target state
    def perform_transition(to_state)
      # Record transition in history
      @state_history << {
        from_state: @current_state,
        to_state: to_state,
        timestamp: Time.current,
        workflow_run_id: @workflow_run.id
      }

      # Update current state
      @current_state = to_state

      # Update database
      @workflow_run.update!(status: to_state)

      # Update timestamps based on state
      update_state_timestamps(to_state)
    end

    # Update timestamps based on state transition
    #
    # @param to_state [String] New state
    def update_state_timestamps(to_state)
      case to_state
      when "running"
        # Set started_at if not already set
        @workflow_run.update!(started_at: Time.current) unless @workflow_run.started_at
      when "completed", "failed", "cancelled"
        # Set completed_at for terminal states
        @workflow_run.update!(completed_at: Time.current) unless @workflow_run.completed_at
      end
    end

    # Broadcast state change via WebSocket
    #
    # @param from_state [String] Previous state
    # @param to_state [String] New state
    def broadcast_state_change(from_state, to_state)
      AiOrchestrationChannel.broadcast_workflow_event(
        "workflow.status.changed",
        @workflow_run.workflow_id,
        {
          workflow_run_id: @workflow_run.id,
          run_id: @workflow_run.run_id,
          from_state: from_state,
          to_state: to_state,
          timestamp: Time.current.iso8601
        },
        @workflow_run.account
      )
    end
  end
end
