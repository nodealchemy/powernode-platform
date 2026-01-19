# frozen_string_literal: true

module Mcp
  # Mcp::WorkflowExecutor - Core workflow execution engine
  #
  # Extracted from the monolithic WorkflowOrchestrator to follow Single Responsibility Principle.
  # This service focuses solely on executing workflow nodes and managing execution flow.
  #
  # Responsibilities:
  # - Execute workflow nodes in correct order
  # - Handle different execution modes (sequential, parallel, conditional, DAG)
  # - Manage node prerequisites and dependencies
  # - Coordinate with node executors
  #
  # Does NOT handle:
  # - State transitions (delegated to WorkflowStateManager)
  # - Event recording (delegated to WorkflowEventStore)
  # - Compensation (delegated to SagaCoordinator)
  #
  # Usage:
  #   executor = Mcp::WorkflowExecutor.new(
  #     workflow_run: run,
  #     state_manager: state_manager,
  #     event_store: event_store
  #   )
  #   result = executor.execute
  #
  class WorkflowExecutor
    include BaseAiService
    include AiWorkflowService

    # Include extracted modules
    include ExecutionModes
    include NodeManagement
    include DataFlow
    include Planning
    include ResultHandling
    include Validation
    include Broadcasting

    attr_reader :workflow_run, :workflow, :execution_context, :node_results

    # Use unified exception hierarchy
    ExecutionError = AiExceptions::ExecutionError
    NodeExecutionError = AiExceptions::NodeExecutionError

    def initialize(workflow_run:, state_manager: nil, event_store: nil, **options)
      super(account: workflow_run.account, user: workflow_run.triggered_by_user, **options)

      @workflow_run = workflow_run
      @workflow = workflow_run.workflow
      @state_manager = state_manager || Mcp::WorkflowStateManager.new(workflow_run: @workflow_run)
      @event_store = event_store || Mcp::WorkflowEventStore.new(workflow_run: @workflow_run)

      @node_results = {}
      @execution_context = {}
    end

    # =============================================================================
    # MAIN EXECUTION
    # =============================================================================

    # Execute the workflow
    #
    # @return [Hash] Execution result
    def execute
      with_monitoring("workflow_execution", workflow_id: @workflow.id, run_id: @workflow_run.run_id) do
        with_workflow_context(@workflow_run) do
          log_info "Starting workflow execution", {
            workflow: @workflow.name,
            run_id: @workflow_run.run_id
          }

          # Validate workflow is ready to execute
          validate_workflow_executable!

          # Transition to running state
          @state_manager.transition!(:initializing, :running)

          # Execute based on execution mode
          execute_by_mode

          # Generate final result
          generate_execution_result
        end
      end
    rescue StandardError => e
      handle_execution_failure(e)
      raise ExecutionError, "Workflow execution failed: #{e.message}"
    end
  end
end
