# frozen_string_literal: true

module Mcp
  # Mcp::AiWorkflowOrchestrator - Core orchestration engine for MCP workflow execution
  #
  # This service replaces the legacy dual-system execution with a unified MCP-based
  # orchestrator that properly manages workflow state, node execution, and event sourcing.
  #
  # Key responsibilities:
  # - Workflow execution orchestration via MCP protocol
  # - State machine management for workflow transitions
  # - Event sourcing for complete execution history
  # - Error recovery and compensation handling
  # - Real-time execution monitoring and telemetry
  #
  class AiWorkflowOrchestrator
    include ActiveModel::Model
    include ActiveModel::Attributes

    # Include extracted modules
    include Orchestrator::Validation
    include Orchestrator::ExecutionModes
    include Orchestrator::NodeExecution
    include Orchestrator::Navigation
    include Orchestrator::ContextManagement
    include Orchestrator::Compensation
    include Orchestrator::Finalization
    include Orchestrator::AdvancedExecution
    include Orchestrator::LoopPrevention

    class WorkflowExecutionError < StandardError; end
    class StateTransitionError < StandardError; end
    class NodeExecutionError < StandardError; end
    class CompensationError < StandardError; end

    attr_accessor :workflow_run, :account, :user
    attr_reader :execution_state, :execution_events, :node_results

    def initialize(workflow_run:, account: nil, user: nil)
      @workflow_run = workflow_run
      @workflow = workflow_run.workflow
      @account = account || workflow_run.account
      @user = user || workflow_run.triggered_by_user
      @logger = Rails.logger

      # Initialize execution components
      @state_machine = Mcp::WorkflowStateMachine.new(workflow_run: @workflow_run)
      @event_store = Mcp::ExecutionEventStore.new(workflow_run: @workflow_run)
      @execution_tracer = Mcp::ExecutionTracer.new(workflow_run: @workflow_run)
      @monitor = Mcp::WorkflowMonitor.new(workflow_run: @workflow_run)

      # Initialize MCP protocol services
      @mcp_protocol = McpProtocolService.new(account: @account)
      @mcp_registry = McpRegistryService.new(account: @account)

      # Execution state tracking
      @execution_state = {}
      @node_results = {}
      @compensation_stack = []
      @execution_context = {}
    end

    # Execute the workflow with complete orchestration
    def execute
      @logger.info "[MCP_ORCHESTRATOR] Starting workflow execution for run #{@workflow_run.run_id}"
      @execution_tracer.trace_start(workflow_info)

      begin
        initialize_execution
        validate_workflow!
        validate_mcp_requirements!
        transition_state!(:initializing, :running)
        execute_workflow_by_mode
        finalize_execution

      rescue StandardError => e
        handle_execution_failure(e)
        raise WorkflowExecutionError, "Workflow execution failed: #{e.message}"
      ensure
        @monitor.finalize
      end

      @workflow_run.reload
    end

    # Execute workflow from a specific node (for checkpoint recovery)
    def execute_from_node(node_id, resume_context = {})
      @logger.info "[MCP_ORCHESTRATOR] Resuming execution from node: #{node_id}"

      begin
        initialize_execution

        @execution_context[:variables].merge!(resume_context["variables"] || {}) if resume_context["variables"]
        @execution_context[:resume_point] = node_id

        current_state = @state_machine.current_state
        transition_state!(current_state, :running) unless current_state == :running

        resume_node = @workflow.workflow_nodes.find_by(node_id: node_id)
        raise WorkflowExecutionError, "Resume node not found: #{node_id}" unless resume_node

        execute_from_resume_point(resume_node)
        finalize_execution

      rescue StandardError => e
        handle_execution_failure(e)
        raise WorkflowExecutionError, "Workflow execution failed during resume: #{e.message}"
      ensure
        @monitor.finalize
      end

      @workflow_run.reload
    end

    private

    def initialize_execution
      @logger.info "[MCP_ORCHESTRATOR] Initializing execution environment"

      @event_store.record_event(
        event_type: "workflow.execution.initialized",
        event_data: {
          workflow_id: @workflow.id,
          workflow_name: @workflow.name,
          run_id: @workflow_run.run_id,
          user_id: @user&.id,
          input_variables: @workflow_run.input_variables
        }
      )

      @execution_context = {
        workflow_id: @workflow.id,
        workflow_run_id: @workflow_run.id,
        run_id: @workflow_run.run_id,
        account_id: @account.id,
        user_id: @user&.id,
        started_at: Time.current,
        variables: @workflow_run.input_variables&.dup || {},
        node_results: {},
        execution_path: [],
        compensation_handlers: []
      }

      # Initialize loop prevention tracking
      initialize_loop_prevention

      @state_machine.initialize_state(@execution_context)
      @monitor.start_monitoring(@execution_context)

      # Load persistent contexts (agent memories, knowledge bases)
      load_persistent_contexts

      serializable_context = @execution_context.except(:node_results).deep_dup
      @workflow_run.update!(
        status: "initializing",
        started_at: Time.current,
        runtime_context: serializable_context
      )
    end

    def transition_state!(from_state, to_state)
      @state_machine.transition!(from_state, to_state)

      @event_store.record_event(
        event_type: "workflow.state.transitioned",
        event_data: {
          from_state: from_state,
          to_state: to_state
        }
      )
    rescue StandardError => e
      raise StateTransitionError, "Failed to transition from #{from_state} to #{to_state}: #{e.message}"
    end

    def workflow_info
      {
        id: @workflow.id,
        name: @workflow.name,
        version: @workflow.version,
        run_id: @workflow_run.run_id
      }
    end
  end

  # Alias for backwards compatibility
  WorkflowOrchestrator = AiWorkflowOrchestrator
end
