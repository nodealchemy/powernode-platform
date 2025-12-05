# frozen_string_literal: true

module Mcp
  # Mcp::WorkflowOrchestrator - Core orchestration engine for MCP workflow execution
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
  # Architecture:
  # - Uses state machine for formal workflow state transitions
  # - Implements event sourcing for debugging and replay
  # - Coordinates with MCP node executors for actual work
  # - Maintains execution context isolation
  #
  # @example Execute a workflow
  #   orchestrator = Mcp::WorkflowOrchestrator.new(workflow_run: run)
  #   result = orchestrator.execute
  #
  class WorkflowOrchestrator
    include ActiveModel::Model
    include ActiveModel::Attributes

    class WorkflowExecutionError < StandardError; end
    class StateTransitionError < StandardError; end
    class NodeExecutionError < StandardError; end
    class CompensationError < StandardError; end

    attr_accessor :workflow_run, :account, :user
    attr_reader :execution_state, :execution_events, :node_results

    def initialize(workflow_run:, account: nil, user: nil)
      @workflow_run = workflow_run
      @workflow = workflow_run.ai_workflow
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

    # =============================================================================
    # MAIN WORKFLOW EXECUTION
    # =============================================================================

    # Execute the workflow with complete orchestration
    #
    # @return [AiWorkflowRun] The completed workflow run
    # @raise [WorkflowExecutionError] if execution fails critically
    def execute
      @logger.info "[MCP_ORCHESTRATOR] Starting workflow execution for run #{@workflow_run.run_id}"
      @execution_tracer.trace_start(workflow_info)

      begin
        # Initialize execution environment
        initialize_execution

        # Validate workflow and MCP requirements
        validate_workflow!
        validate_mcp_requirements!

        # Transition to running state
        transition_state!(:initializing, :running)

        # Execute workflow based on execution mode
        execute_workflow_by_mode

        # Finalize successful execution
        finalize_execution

      rescue StandardError => e
        handle_execution_failure(e)
        raise WorkflowExecutionError, "Workflow execution failed: #{e.message}"
      ensure
        # Ensure monitoring cleanup
        @monitor.finalize
      end

      @workflow_run.reload
    end

    # Execute workflow from a specific node (for checkpoint recovery)
    #
    # @param node_id [String] The node ID to start execution from
    # @param resume_context [Hash] Additional context for resumption
    # @return [AiWorkflowRun] The updated workflow run
    def execute_from_node(node_id, resume_context = {})
      @logger.info "[MCP_ORCHESTRATOR] Resuming execution from node: #{node_id}"

      begin
        # Initialize execution environment
        initialize_execution

        # Merge resume context into execution context
        @execution_context[:variables].merge!(resume_context['variables'] || {}) if resume_context['variables']
        @execution_context[:resume_point] = node_id

        # Transition to running state if not already
        current_state = @state_machine.current_state
        transition_state!(current_state, :running) unless current_state == :running

        # Find the resume node
        resume_node = @workflow.ai_workflow_nodes.find_by(node_id: node_id)
        raise WorkflowExecutionError, "Resume node not found: #{node_id}" unless resume_node

        # Execute from the resume node
        execute_from_resume_point(resume_node)

        # Finalize successful execution
        finalize_execution

      rescue StandardError => e
        handle_execution_failure(e)
        raise WorkflowExecutionError, "Workflow execution failed during resume: #{e.message}"
      ensure
        # Ensure monitoring cleanup
        @monitor.finalize
      end

      @workflow_run.reload
    end

    # =============================================================================
    # EXECUTION INITIALIZATION
    # =============================================================================

    def initialize_execution
      @logger.info "[MCP_ORCHESTRATOR] Initializing execution environment"

      # Record initialization event
      @event_store.record_event(
        event_type: 'workflow.execution.initialized',
        event_data: {
          workflow_id: @workflow.id,
          workflow_name: @workflow.name,
          run_id: @workflow_run.run_id,
          user_id: @user&.id,
          input_variables: @workflow_run.input_variables
        }
      )

      # Initialize execution context
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

      # Initialize state machine
      @state_machine.initialize_state(@execution_context)

      # Start monitoring
      @monitor.start_monitoring(@execution_context)

      # Update workflow run status
      # Exclude node_results to avoid circular references during JSON serialization
      serializable_context = @execution_context.except(:node_results).deep_dup
      @workflow_run.update!(
        status: 'initializing',
        started_at: Time.current,
        runtime_context: serializable_context
      )
    end

    # =============================================================================
    # WORKFLOW VALIDATION
    # =============================================================================

    def validate_workflow!
      @logger.info "[MCP_ORCHESTRATOR] Validating workflow structure"

      # Check workflow status
      unless @workflow.can_execute?
        raise WorkflowExecutionError, "Workflow cannot be executed in current state: #{@workflow.status}"
      end

      # Validate workflow structure
      unless @workflow.has_valid_structure?
        raise WorkflowExecutionError, "Workflow structure is invalid"
      end

      # Validate start nodes exist
      start_nodes = find_start_nodes
      if start_nodes.empty?
        raise WorkflowExecutionError, "No start nodes found in workflow"
      end

      @event_store.record_event(
        event_type: 'workflow.validation.completed',
        event_data: {
          start_nodes_count: start_nodes.count,
          total_nodes: @workflow.node_count,
          total_edges: @workflow.edge_count
        }
      )
    end

    def validate_mcp_requirements!
      @logger.info "[MCP_ORCHESTRATOR] Validating MCP tool requirements"

      mcp_config = @workflow.mcp_orchestration_config || {}
      tool_requirements = mcp_config['tool_requirements'] || []

      tool_requirements.each do |requirement|
        tool_id = requirement['tool_id']
        min_version = requirement['min_version']

        # Check tool availability in registry
        tool_manifest = @mcp_registry.get_tool(tool_id)
        unless tool_manifest
          raise WorkflowExecutionError, "Required MCP tool not found: #{tool_id}"
        end

        # Check version compatibility if specified
        if min_version.present?
          tool_version = Gem::Version.new(tool_manifest['version'])
          required_version = Gem::Version.new(min_version)

          unless tool_version >= required_version
            raise WorkflowExecutionError,
                  "Tool #{tool_id} version #{tool_manifest['version']} is below required #{min_version}"
          end
        end
      end

      @event_store.record_event(
        event_type: 'workflow.mcp_validation.completed',
        event_data: {
          tools_validated: tool_requirements.count
        }
      )
    end

    # =============================================================================
    # EXECUTION MODES
    # =============================================================================

    def execute_workflow_by_mode
      execution_mode = @workflow.mcp_orchestration_config&.dig('execution_mode') || 'sequential'

      @logger.info "[MCP_ORCHESTRATOR] Executing in #{execution_mode} mode"

      case execution_mode
      when 'sequential'
        execute_sequential_mode
      when 'parallel'
        execute_parallel_mode
      when 'conditional'
        execute_conditional_mode
      when 'dag' # Directed Acyclic Graph - optimal execution order
        execute_dag_mode
      else
        execute_sequential_mode # Safe default
      end
    end

    def execute_from_resume_point(resume_node)
      @logger.info "[MCP_ORCHESTRATOR] Executing from resume point: #{resume_node.node_id}"

      # Start execution queue with the resume node
      execution_queue = [resume_node]

      while execution_queue.any?
        current_node = execution_queue.shift

        # Skip if already executed (for convergent flows)
        next if @node_results.key?(current_node.node_id)

        # Check if all prerequisites are complete (for convergent nodes)
        unless prerequisites_complete?(current_node)
          # Re-queue at end if prerequisites not ready
          execution_queue << current_node
          next
        end

        # Execute node
        node_result = execute_node(current_node)

        # Find next nodes based on execution result
        next_nodes = find_next_nodes(current_node, node_result)
        execution_queue.concat(next_nodes)

        # Record execution path
        @execution_context[:execution_path] << current_node.node_id
      end
    end

    def execute_sequential_mode
      @logger.info "[MCP_ORCHESTRATOR] Executing workflow sequentially"

      start_nodes = find_start_nodes
      execution_queue = start_nodes.to_a

      # Track requeue attempts to detect deadlocks/circular dependencies
      requeue_counts = Hash.new(0)
      max_requeues_per_node = 100  # Safety limit to prevent infinite loops

      while execution_queue.any?
        current_node = execution_queue.shift

        # Skip if already executed (for convergent flows)
        next if @node_results.key?(current_node.node_id)

        # Check if all prerequisites are complete (for convergent nodes)
        unless prerequisites_complete?(current_node)
          # Detect deadlock: if we've requeued this node too many times, fail
          requeue_counts[current_node.node_id] += 1
          if requeue_counts[current_node.node_id] > max_requeues_per_node
            @logger.error "[MCP_ORCHESTRATOR] Deadlock detected: node #{current_node.node_id} requeued #{requeue_counts[current_node.node_id]} times"
            raise "Workflow execution deadlock: Node '#{current_node.node_id}' prerequisites never satisfied. This indicates a circular dependency or broken workflow structure."
          end

          # Re-queue at end if prerequisites not ready
          execution_queue << current_node
          next
        end

        # Execute node
        node_result = execute_node(current_node)

        # Find next nodes based on execution result
        next_nodes = find_next_nodes(current_node, node_result)
        execution_queue.concat(next_nodes)

        # Record execution path
        @execution_context[:execution_path] << current_node.node_id
      end
    end

    def execute_parallel_mode
      @logger.info "[MCP_ORCHESTRATOR] Executing workflow in parallel mode"

      # Use Mcp::ParallelExecutionCoordinator for proper parallel orchestration
      coordinator = Mcp::ParallelExecutionCoordinator.new(
        orchestrator: self,
        workflow: @workflow,
        execution_context: @execution_context
      )

      coordinator.execute_parallel

      # Merge results from parallel execution
      @node_results.merge!(coordinator.node_results)
      @execution_context[:execution_path].concat(coordinator.execution_path)
    end

    def execute_conditional_mode
      @logger.info "[MCP_ORCHESTRATOR] Executing workflow with conditional branching"

      start_nodes = find_start_nodes

      start_nodes.each do |start_node|
        execute_conditional_branch(start_node)
      end
    end

    def execute_dag_mode
      @logger.info "[MCP_ORCHESTRATOR] Executing workflow in DAG optimization mode"

      # Build execution plan based on dependency graph
      execution_plan = build_dag_execution_plan

      # Execute in optimal order respecting dependencies
      execution_plan.each_with_index do |node_batch, batch_index|
        @logger.debug "[MCP_ORCHESTRATOR] Executing batch #{batch_index + 1}/#{execution_plan.count}"

        if node_batch.count > 1
          # Execute batch in parallel
          execute_node_batch_parallel(node_batch)
        else
          # Execute single node
          execute_node(node_batch.first)
        end
      end
    end

    # =============================================================================
    # NODE EXECUTION
    # =============================================================================

    def execute_node(node)
      @logger.info "[MCP_ORCHESTRATOR] Executing node: #{node.node_id} (#{node.name})"

      # Create node execution context
      node_context = Mcp::NodeExecutionContext.new(
        node: node,
        workflow_run: @workflow_run,
        execution_context: @execution_context,
        previous_results: @node_results
      )

      # Create node execution record
      node_execution = create_node_execution_record(node, node_context)

      begin
        # Transition state to executing this node
        @state_machine.execute_node(node.node_id)

        # Start node execution (triggers WebSocket broadcast via @pending_status_change)
        node_execution.start_execution!

        # Record execution start event
        @event_store.record_event(
          event_type: 'node.execution.started',
          event_data: {
            node_id: node.node_id,
            node_type: node.node_type,
            node_name: node.name
          }
        )

        # Get MCP node executor for this node type
        executor = get_mcp_node_executor(node, node_execution, node_context)

        # Execute node via MCP
        result = executor.execute

        # Handle successful execution
        handle_node_success(node, node_execution, result, node_context)

        result

      rescue StandardError => e
        # Handle node execution failure
        handle_node_failure(node, node_execution, e, node_context)
        raise NodeExecutionError, "Node #{node.node_id} failed: #{e.message}"
      end
    end

    def get_mcp_node_executor(node, node_execution, node_context)
      executor_class = case node.node_type
                      when 'ai_agent'
                        Mcp::NodeExecutors::AiAgent
                      when 'api_call'
                        Mcp::NodeExecutors::ApiCall
                      when 'transform'
                        Mcp::NodeExecutors::Transform
                      when 'condition'
                        Mcp::NodeExecutors::Condition
                      when 'webhook'
                        Mcp::NodeExecutors::Webhook
                      when 'delay'
                        Mcp::NodeExecutors::Delay
                      when 'loop'
                        Mcp::NodeExecutors::Loop
                      when 'merge'
                        Mcp::NodeExecutors::Merge
                      when 'split'
                        Mcp::NodeExecutors::Split
                      when 'sub_workflow'
                        Mcp::NodeExecutors::SubWorkflow
                      when 'human_approval'
                        Mcp::NodeExecutors::HumanApproval
                      when 'trigger', 'start'
                        Mcp::NodeExecutors::Start
                      when 'end'
                        Mcp::NodeExecutors::End
                      # Knowledge Base Article Management
                      when 'kb_article_create'
                        Mcp::NodeExecutors::KbArticleCreate
                      when 'kb_article_read'
                        Mcp::NodeExecutors::KbArticleRead
                      when 'kb_article_update'
                        Mcp::NodeExecutors::KbArticleUpdate
                      when 'kb_article_search'
                        Mcp::NodeExecutors::KbArticleSearch
                      when 'kb_article_publish'
                        Mcp::NodeExecutors::KbArticlePublish
                      # Page Content Management
                      when 'page_create'
                        Mcp::NodeExecutors::PageCreate
                      when 'page_read'
                        Mcp::NodeExecutors::PageRead
                      when 'page_update'
                        Mcp::NodeExecutors::PageUpdate
                      when 'page_publish'
                        Mcp::NodeExecutors::PagePublish
                      else
                        raise NodeExecutionError, "Unknown node type: #{node.node_type}"
                      end

      executor_class.new(
        node: node,
        node_execution: node_execution,
        node_context: node_context,
        orchestrator: self
      )
    end

    def handle_node_success(node, node_execution, result, node_context)
      @logger.info "[MCP_ORCHESTRATOR] Node execution successful: #{node.node_id}"

      # Store node result
      @node_results[node.node_id] = result

      # Update execution context with node output using v1.0 standard format
      # Build output_data from standard keys for compatibility with execution context
      output_for_context = build_output_for_context(result)
      if output_for_context.present?
        update_execution_context(node, output_for_context)
      end

      # Record compensation handler if node supports it
      if result[:compensation_handler].present?
        @compensation_stack << {
          node_id: node.node_id,
          handler: result[:compensation_handler],
          context: {
            node_id: node.node_id,
            node_type: node.node_type,
            variables: node_context.scoped_variables.deep_dup
          }
        }
      end

      # Complete node execution with standard format output
      node_execution.complete_execution!(
        output_for_context,
        result.dig(:metadata, :cost) || result[:cost] || 0.0
      )

      # CRITICAL FIX: Explicitly update progress and cost AFTER node completion
      # This was previously done in after_update callbacks which caused stack overflow
      # By calling these explicitly here, we avoid nested update! calls during callbacks
      node_execution.update_run_progress
      cost = result.dig(:metadata, :cost) || result[:cost] || 0.0
      node_execution.add_cost_to_run_explicit(cost) if cost > 0

      # Update additional metadata
      if result.dig(:metadata, :duration_ms).present?
        node_execution.update_column(:duration_ms, result.dig(:metadata, :duration_ms))
      end
      if result[:metadata].present?
        # Only save serializable metadata (no complex objects or circular references)
        serializable_metadata = result[:metadata].deep_dup.except(:compensation_handler)
        node_execution.update_column(:metadata, node_execution.metadata.merge(serializable_metadata))
      end

      # Record completion event
      @event_store.record_event(
        event_type: 'node.execution.completed',
        event_data: {
          node_id: node.node_id,
          node_type: node.node_type,
          duration_ms: result.dig(:metadata, :duration_ms) || result[:execution_time_ms],
          cost: result.dig(:metadata, :cost) || result[:cost]
        }
      )

      # Trace execution
      @execution_tracer.trace_node_completion(node, result)

      # Update monitoring
      @monitor.node_completed(node, result)
    end

    def handle_node_failure(node, node_execution, error, node_context)
      @logger.error "[MCP_ORCHESTRATOR] Node execution failed: #{node.node_id} - #{error.message}"

      # Fail node execution (triggers WebSocket broadcast via @pending_status_change)
      node_execution.fail_execution!(
        error.message,
        {
          'exception_class' => error.class.name,
          'backtrace' => error.backtrace&.first(10)
        }
      )

      # Record failure event
      @event_store.record_event(
        event_type: 'node.execution.failed',
        event_data: {
          node_id: node.node_id,
          node_type: node.node_type,
          error_message: error.message,
          error_class: error.class.name
        }
      )

      # Trace failure
      @execution_tracer.trace_node_failure(node, error)

      # Update monitoring
      @monitor.node_failed(node, error)

      # Check if we should trigger compensation
      if should_compensate_on_failure?
        trigger_compensation(error)
      end
    end

    # =============================================================================
    # WORKFLOW NAVIGATION
    # =============================================================================

    def find_start_nodes
      # Find nodes marked as start nodes
      start_nodes = @workflow.ai_workflow_nodes.where(is_start_node: true)

      # Fallback: nodes with no incoming edges
      if start_nodes.empty?
        all_target_node_ids = @workflow.ai_workflow_edges.pluck(:target_node_id)
        start_nodes = @workflow.ai_workflow_nodes.where.not(node_id: all_target_node_ids)
      end

      start_nodes
    end

    def find_next_nodes(current_node, node_result)
      # Find outgoing edges from current node
      outgoing_edges = @workflow.ai_workflow_edges.where(source_node_id: current_node.node_id)

      # Evaluate each edge to determine valid paths
      valid_edges = outgoing_edges.select do |edge|
        evaluate_edge_condition(edge, node_result)
      end

      # Sort by priority
      valid_edges = valid_edges.sort_by { |edge| edge.priority || 0 }

      # Get target nodes
      target_node_ids = valid_edges.map(&:target_node_id)
      @workflow.ai_workflow_nodes.where(node_id: target_node_ids)
    end

    def evaluate_edge_condition(edge, node_result)
      # Handle nil node_result (shouldn't happen but add safety)
      return false if node_result.nil?

      # Default edges always pass
      return true if edge.edge_type == 'default'

      # Success edges only pass if node succeeded
      if edge.edge_type == 'success'
        return node_result[:success] == true
      end

      # Error edges only pass if node failed
      if edge.edge_type == 'error'
        return node_result[:success] == false
      end

      # Conditional edges require expression evaluation
      if edge.is_conditional? && edge.condition.present?
        return evaluate_conditional_expression(edge.condition, node_result)
      end

      # Default to true for unknown edge types
      true
    end

    def evaluate_conditional_expression(condition, node_result)
      # Use Mcp::ConditionalEvaluator for complex expression evaluation
      evaluator = Mcp::ConditionalEvaluator.new(
        condition: condition,
        context: @execution_context,
        node_result: node_result
      )

      evaluator.evaluate
    rescue StandardError => e
      @logger.error "[MCP_ORCHESTRATOR] Conditional evaluation failed: #{e.message}"
      false
    end

    def prerequisites_complete?(node)
      # Get all incoming edges for this node
      incoming_edges = @workflow.ai_workflow_edges.where(target_node_id: node.node_id)

      # If no incoming edges, node is ready (it's a start node or orphaned)
      return true if incoming_edges.empty?

      # Check which source nodes have conditional incoming edges (indicating they're from a conditional branch)
      source_nodes_with_conditional_incoming = incoming_edges.select do |edge|
        source_node_id = edge.source_node_id
        source_node_incoming = @workflow.ai_workflow_edges.where(target_node_id: source_node_id)
        source_node_incoming.any?(&:is_conditional?)
      end

      # If this is a convergence point after conditional branches (multiple sources, some from conditional paths),
      # use "at least one" logic instead of "all"
      is_conditional_convergence = incoming_edges.count > 1 && source_nodes_with_conditional_incoming.any?

      if is_conditional_convergence
        # For convergent nodes after conditional branches, require at least ONE edge to be satisfied
        incoming_edges.any? do |edge|
          source_node_id = edge.source_node_id

          # Check if source node has a result in @node_results
          if @node_results.key?(source_node_id)
            source_result = @node_results[source_node_id]

            # Verify the edge condition is satisfied
            evaluate_edge_condition(edge, source_result)
          else
            # Source node not yet executed
            false
          end
        end
      else
        # For non-conditional flows, require ALL edges to be satisfied
        incoming_edges.all? do |edge|
          source_node_id = edge.source_node_id

          # Check if source node has a result in @node_results
          if @node_results.key?(source_node_id)
            source_result = @node_results[source_node_id]

            # Verify the edge condition is satisfied
            evaluate_edge_condition(edge, source_result)
          else
            # Source node not yet executed
            false
          end
        end
      end
    end

    # =============================================================================
    # EXECUTION CONTEXT MANAGEMENT
    # =============================================================================

    def update_execution_context(node, output_data)
      # Store node output in execution context
      @execution_context[:node_results][node.node_id] = output_data

      # Extract and store variables if present
      if output_data.is_a?(Hash)
        # Auto-extract variables based on node configuration
        variable_mapping = node.configuration&.dig('output_variables') || {}

        variable_mapping.each do |var_name, output_path|
          value = extract_value_from_path(output_data, output_path)
          @execution_context[:variables][var_name] = value if value.present?
        end

        # Also store direct variable assignments if present
        if output_data['variables'].is_a?(Hash)
          @execution_context[:variables].merge!(output_data['variables'])
        end
      end

      # Persist updated context (excluding node_results to avoid circular references)
      serializable_context = @execution_context.except(:node_results).deep_dup
      @workflow_run.update_column(:runtime_context, serializable_context)
    end

    def extract_value_from_path(data, path)
      return data if path.blank?

      path.to_s.split('.').reduce(data) do |current, key|
        break nil unless current.is_a?(Hash) || current.is_a?(Array)

        if current.is_a?(Array) && key =~ /\A\d+\z/
          current[key.to_i]
        else
          current[key.to_s] || current[key.to_sym]
        end
      end
    end

    # =============================================================================
    # ERROR RECOVERY & COMPENSATION
    # =============================================================================

    def should_compensate_on_failure?
      compensation_strategy = @workflow.mcp_orchestration_config&.dig('compensation_strategy')
      compensation_strategy == 'automatic' || @compensation_stack.any?
    end

    def trigger_compensation(original_error)
      @logger.warn "[MCP_ORCHESTRATOR] Triggering compensation due to failure"

      @event_store.record_event(
        event_type: 'workflow.compensation.started',
        event_data: {
          original_error: original_error.message,
          compensation_handlers: @compensation_stack.count
        }
      )

      compensation_errors = []

      # Execute compensation handlers in reverse order (LIFO)
      @compensation_stack.reverse.each do |compensation|
        begin
          execute_compensation_handler(compensation)
        rescue StandardError => e
          @logger.error "[MCP_ORCHESTRATOR] Compensation failed for node #{compensation[:node_id]}: #{e.message}"
          compensation_errors << {
            node_id: compensation[:node_id],
            error: e.message
          }
        end
      end

      if compensation_errors.any?
        @event_store.record_event(
          event_type: 'workflow.compensation.partial_failure',
          event_data: { errors: compensation_errors }
        )
      else
        @event_store.record_event(
          event_type: 'workflow.compensation.completed',
          event_data: { handlers_executed: @compensation_stack.count }
        )
      end
    end

    def execute_compensation_handler(compensation)
      @logger.info "[MCP_ORCHESTRATOR] Executing compensation for node: #{compensation[:node_id]}"

      handler = compensation[:handler]
      handler.call(compensation[:context]) if handler.respond_to?(:call)
    end

    # =============================================================================
    # EXECUTION FINALIZATION
    # =============================================================================

    def finalize_execution
      @logger.info "[MCP_ORCHESTRATOR] Finalizing workflow execution"

      # Determine final status
      failed_nodes = @workflow_run.ai_workflow_node_executions.where(status: 'failed')
      final_status = failed_nodes.any? ? 'failed' : 'completed'

      # Transition to final state
      transition_state!(:running, final_status.to_sym)

      # Generate final output
      final_output = generate_final_output

      # Recalculate progress counters from actual node executions
      @workflow_run.update_progress!

      # Update workflow run
      @workflow_run.update!(
        status: final_status,
        completed_at: Time.current,
        output_variables: final_output,
        duration_ms: calculate_total_duration,
        total_cost: calculate_total_cost
      )

      # Broadcast completion to frontend via AiOrchestrationChannel
      # CRITICAL: Frontend needs this for live preview updates
      AiOrchestrationChannel.broadcast_workflow_run_event(
        'workflow.execution.completed',
        @workflow_run,
        {
          workflow_run: {
            id: @workflow_run.id,
            run_id: @workflow_run.run_id,
            status: final_status,
            completed_at: @workflow_run.completed_at&.iso8601,
            duration_seconds: (@workflow_run.duration_ms || 0) / 1000.0,
            cost_usd: @workflow_run.total_cost,
            output: final_output,
            outputVariables: final_output,
            output_variables: final_output,
            progress_percentage: 100,
            completed_nodes: @workflow_run.completed_nodes,
            failed_nodes: @workflow_run.failed_nodes,
            total_nodes: @workflow_run.total_nodes
          }
        }
      )

      # Record completion event
      @event_store.record_event(
        event_type: 'workflow.execution.completed',
        event_data: {
          status: final_status,
          duration_ms: calculate_total_duration,
          total_cost: calculate_total_cost,
          nodes_executed: @node_results.count
        }
      )

      # Trace completion
      @execution_tracer.trace_completion(final_status, final_output)

      # Broadcast completion via MCP channel
      broadcast_completion(final_status, final_output)
    end

    def generate_final_output
      # CRITICAL: Use End node output as primary final output
      # Find the End node result
      end_node = @workflow.ai_workflow_nodes.find_by(node_type: 'end')
      end_node_result = end_node ? @node_results[end_node.node_id] : nil

      if end_node_result.present?
        # Use End node's output as the primary final output
        # The End node already includes all necessary data:
        # - output: Status message
        # - result: Final output from last node
        # - data: All node outputs, execution path, input variables
        # - metadata: Execution statistics
        @logger.info "[MCP_ORCHESTRATOR] Using End node output as final workflow output"
        end_node_result
      else
        # Fallback: Generate output from orchestrator state (no End node in workflow)
        @logger.warn "[MCP_ORCHESTRATOR] No End node found, generating fallback output"
        {
          workflow_id: @workflow.id,
          run_id: @workflow_run.run_id,
          status: @workflow_run.status,
          execution_summary: {
            total_nodes: @node_results.count,
            execution_path: @execution_context[:execution_path],
            duration_ms: calculate_total_duration,
            total_cost: calculate_total_cost
          },
          variables: @execution_context[:variables],
          node_results: @node_results,
          mcp_metadata: {
            protocol_version: McpProtocolService::MCP_VERSION,
            orchestrator_version: '2.0.0',
            execution_mode: @workflow.mcp_orchestration_config&.dig('execution_mode') || 'sequential'
          }
        }
      end
    end

    def handle_execution_failure(error)
      @logger.error "[MCP_ORCHESTRATOR] Workflow execution failed: #{error.message}"

      # Transition to failed state
      begin
        transition_state!(@state_machine.current_state, :failed)
      rescue StateTransitionError
        # State may already be failed
      end

      # CRITICAL FIX: Clean up any nodes still in active (running/pending) status
      # When workflow fails, we must mark all active nodes as cancelled to prevent them
      # from being stuck in running status forever
      cleanup_active_nodes(error)

      # Update workflow run
      @workflow_run.update!(
        status: 'failed',
        error_details: {
          error_message: error.message,
          exception_class: error.class.name,
          backtrace: error.backtrace&.first(20)
        },
        completed_at: Time.current
      )

      # Record failure event
      @event_store.record_event(
        event_type: 'workflow.execution.failed',
        event_data: {
          error_message: error.message,
          error_class: error.class.name
        }
      )

      # Trace failure
      @execution_tracer.trace_failure(error)

      # Broadcast failure
      broadcast_failure(error)
    end

    # =============================================================================
    # STATE MANAGEMENT
    # =============================================================================

    def transition_state!(from_state, to_state)
      @state_machine.transition!(from_state, to_state)

      @event_store.record_event(
        event_type: 'workflow.state.transitioned',
        event_data: {
          from_state: from_state,
          to_state: to_state
        }
      )
    rescue StandardError => e
      raise StateTransitionError, "Failed to transition from #{from_state} to #{to_state}: #{e.message}"
    end

    # =============================================================================
    # NODE CLEANUP
    # =============================================================================

    # Clean up any nodes still in active status when workflow fails
    # Prevents nodes from being stuck in "running" status forever
    def cleanup_active_nodes(error)
      active_nodes = @workflow_run.ai_workflow_node_executions.active

      if active_nodes.any?
        @logger.warn "[MCP_ORCHESTRATOR] Cleaning up #{active_nodes.count} active node(s) due to workflow failure"

        active_nodes.each do |node_execution|
          begin
            # Cancel the node execution with failure reason
            node_execution.cancel_execution!("Workflow failed: #{error.message}")

            @logger.info "[MCP_ORCHESTRATOR] Cancelled node: #{node_execution.node_id} (#{node_execution.ai_workflow_node.name})"
          rescue StandardError => cleanup_error
            # Log but don't fail the cleanup process
            @logger.error "[MCP_ORCHESTRATOR] Failed to cancel node #{node_execution.node_id}: #{cleanup_error.message}"
          end
        end

        @event_store.record_event(
          event_type: 'workflow.nodes.cleanup',
          event_data: {
            nodes_cancelled: active_nodes.count,
            reason: 'workflow_failure'
          }
        )
      end
    end

    # =============================================================================
    # HELPER METHODS
    # =============================================================================

    def create_node_execution_record(node, node_context)
      @workflow_run.ai_workflow_node_executions.create!(
        ai_workflow_node_id: node.id,
        node_id: node.node_id,
        node_type: node.node_type,
        status: 'pending',
        started_at: Time.current,
        input_data: node_context.input_data,
        metadata: {
          mcp_execution: true,
          mcp_tool_id: node.mcp_tool_id,
          execution_context_snapshot: {
            variables: node_context.scoped_variables.deep_dup,
            has_previous_results: node_context.previous_results.any?
          }
        }
      )
    end

    def calculate_total_duration
      return 0 unless @workflow_run.started_at

      ((Time.current - @workflow_run.started_at) * 1000).round
    end

    def calculate_total_cost
      @workflow_run.ai_workflow_node_executions.sum(:cost) || 0.0
    end

    def broadcast_completion(status, output)
      McpBroadcastService.broadcast_workflow_event(
        'workflow_execution_completed',
        @workflow.id,
        {
          workflow_run_id: @workflow_run.id,
          run_id: @workflow_run.run_id,
          status: status,
          output: output,
          timestamp: Time.current.iso8601
        },
        @account
      )
    end

    def broadcast_failure(error)
      McpBroadcastService.broadcast_workflow_event(
        'workflow_execution_failed',
        @workflow.id,
        {
          workflow_run_id: @workflow_run.id,
          run_id: @workflow_run.run_id,
          error: error.message,
          timestamp: Time.current.iso8601
        },
        @account
      )
    end

    def workflow_info
      {
        id: @workflow.id,
        name: @workflow.name,
        version: @workflow.version,
        run_id: @workflow_run.run_id
      }
    end

    # Allow access to execution context for node executors
    def execution_context
      @execution_context
    end

    # Allow node executors to update variables
    def set_variable(name, value)
      @execution_context[:variables][name] = value
      # Update runtime context without node_results to avoid circular references
      serializable_context = @execution_context.except(:node_results).deep_dup
      @workflow_run.update_column(:runtime_context, serializable_context)
    end

    def get_variable(name)
      @execution_context[:variables][name]
    end

    # Build output data for execution context from v1.0 standard format
    # Converts: { output, data, result, metadata } → flat structure for context
    def build_output_for_context(result)
      output_data = {}

      # Include primary output
      if result[:output].present?
        output_data['output'] = result[:output]
      end

      # Merge data section keys at top level
      if result[:data].present? && result[:data].is_a?(Hash)
        output_data.merge!(result[:data])
      end

      # Include result if present
      if result[:result].present?
        output_data['result'] = result[:result]
      end

      output_data
    end

    # =============================================================================
    # ADVANCED EXECUTION METHODS (Phase 2)
    # =============================================================================

    # Execute a conditional branch node (if/else, switch/case)
    # Evaluates condition and executes appropriate branch path
    def execute_conditional_branch(node, visited = Set.new)
      return if visited.include?(node.node_id)
      visited.add(node.node_id)

      @logger.info "[MCP_ORCHESTRATOR] Executing conditional branch: #{node.node_id}"

      # Execute the condition node itself to evaluate the condition
      node_result = execute_node(node)

      # Find all outgoing edges
      outgoing_edges = @workflow.ai_workflow_edges.where(source_node_id: node.node_id)

      # Evaluate each edge to find the path(s) to take
      selected_edges = outgoing_edges.select do |edge|
        evaluate_edge_condition(edge, node_result)
      end

      # Sort by priority - lower priority executes first
      selected_edges = selected_edges.sort_by { |edge| edge.priority || 0 }

      @logger.debug "[MCP_ORCHESTRATOR] Conditional branch selected #{selected_edges.count} path(s)"

      # Execute nodes along selected branches
      selected_edges.each do |edge|
        target_node = @workflow.ai_workflow_nodes.find_by(node_id: edge.target_node_id)
        next unless target_node && !visited.include?(target_node.node_id)

        # Recursively execute the branch
        if target_node.node_type == 'condition'
          execute_conditional_branch(target_node, visited)
        else
          execute_node(target_node)
          # Continue execution after this node
          next_nodes = find_next_nodes(target_node, @node_results[target_node.node_id])
          next_nodes.each do |next_node|
            execute_sequential_from(next_node, visited) unless visited.include?(next_node.node_id)
          end
        end
      end
    end

    # Helper method to execute sequentially from a given node
    def execute_sequential_from(node, visited = Set.new)
      return if visited.include?(node.node_id)
      return unless prerequisites_complete?(node)

      visited.add(node.node_id)

      if node.node_type == 'condition'
        execute_conditional_branch(node, visited)
      else
        node_result = execute_node(node)
        next_nodes = find_next_nodes(node, node_result)

        next_nodes.each do |next_node|
          execute_sequential_from(next_node, visited)
        end
      end
    end

    # Build execution plan based on DAG dependency analysis
    # Returns array of node batches where each batch can be executed in parallel
    def build_dag_execution_plan
      # Build dependency graph
      dependencies = {}
      reverse_dependencies = {}

      @workflow.ai_workflow_nodes.each do |node|
        dependencies[node.node_id] = []
        reverse_dependencies[node.node_id] = []
      end

      @workflow.ai_workflow_edges.each do |edge|
        dependencies[edge.target_node_id] ||= []
        dependencies[edge.target_node_id] << edge.source_node_id

        reverse_dependencies[edge.source_node_id] ||= []
        reverse_dependencies[edge.source_node_id] << edge.target_node_id
      end

      # Topological sort using Kahn's algorithm to find execution levels
      execution_batches = []
      in_degree = {}

      @workflow.ai_workflow_nodes.each do |node|
        in_degree[node.node_id] = dependencies[node.node_id]&.count || 0
      end

      # Start with nodes that have no dependencies (in_degree == 0)
      while in_degree.values.any? { |d| d >= 0 }
        # Find all nodes with in_degree == 0 (no unprocessed dependencies)
        ready_nodes = in_degree.select { |_, degree| degree == 0 }.keys

        break if ready_nodes.empty?

        # Add this batch to the execution plan
        batch_nodes = @workflow.ai_workflow_nodes.where(node_id: ready_nodes).to_a
        execution_batches << batch_nodes if batch_nodes.any?

        # Mark these nodes as processed and update in_degrees
        ready_nodes.each do |node_id|
          in_degree[node_id] = -1 # Mark as processed

          # Decrease in_degree of dependent nodes
          reverse_dependencies[node_id]&.each do |dependent_id|
            in_degree[dependent_id] -= 1 if in_degree[dependent_id] > 0
          end
        end
      end

      @logger.debug "[MCP_ORCHESTRATOR] Built DAG execution plan with #{execution_batches.count} batches"
      execution_batches
    end

    # Execute multiple nodes in parallel
    # Uses threads for concurrent execution with timeout protection
    def execute_node_batch_parallel(node_batch)
      return [] if node_batch.empty?

      @logger.info "[MCP_ORCHESTRATOR] Executing batch of #{node_batch.count} nodes in parallel"

      results = {}
      threads = []
      mutex = Mutex.new

      node_batch.each do |node|
        next unless prerequisites_complete?(node)

        threads << Thread.new do
          begin
            result = execute_node(node)
            mutex.synchronize { results[node.node_id] = result }
          rescue StandardError => e
            mutex.synchronize do
              results[node.node_id] = {
                success: false,
                error: e.message,
                output: nil,
                metadata: { node_id: node.node_id, error_class: e.class.name }
              }
            end
            @logger.error "[MCP_ORCHESTRATOR] Parallel node execution failed: #{node.node_id} - #{e.message}"
          end
        end
      end

      # Wait for all threads with timeout
      timeout_seconds = @workflow.timeout_seconds || 300
      deadline = Time.current + timeout_seconds

      threads.each do |thread|
        remaining = [deadline - Time.current, 0].max
        thread.join(remaining)

        if thread.alive?
          thread.kill
          @logger.warn "[MCP_ORCHESTRATOR] Thread killed due to timeout"
        end
      end

      @logger.info "[MCP_ORCHESTRATOR] Parallel batch completed with #{results.count} results"
      results
    end

    # Execute workflow using parallel execution strategy
    def execute_parallel_workflow
      @logger.info "[MCP_ORCHESTRATOR] Starting parallel workflow execution"

      # Build execution plan
      execution_batches = build_dag_execution_plan

      # Execute each batch
      execution_batches.each_with_index do |batch, index|
        @logger.debug "[MCP_ORCHESTRATOR] Executing batch #{index + 1}/#{execution_batches.count}"

        if batch.size == 1
          # Single node - execute normally
          execute_node(batch.first)
        else
          # Multiple nodes - execute in parallel
          execute_node_batch_parallel(batch)
        end

        # Check for workflow cancellation
        @workflow_run.reload
        if @workflow_run.status == 'cancelled'
          @logger.info "[MCP_ORCHESTRATOR] Workflow cancelled during parallel execution"
          break
        end
      end
    end
  end
end
