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

    attr_reader :workflow_run, :workflow, :execution_context, :node_results

    class ExecutionError < StandardError; end
    class NodeExecutionError < StandardError; end

    def initialize(workflow_run:, state_manager: nil, event_store: nil, **options)
      super(account: workflow_run.account, user: workflow_run.triggered_by_user, **options)

      @workflow_run = workflow_run
      @workflow = workflow_run.ai_workflow
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
      with_monitoring('workflow_execution', workflow_id: @workflow.id, run_id: @workflow_run.run_id) do
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

    # =============================================================================
    # EXECUTION MODES
    # =============================================================================

    # Execute workflow based on configured mode
    def execute_by_mode
      execution_mode = @workflow.mcp_orchestration_config&.dig('execution_mode') || 'sequential'

      log_info "Executing in #{execution_mode} mode"

      case execution_mode
      when 'sequential'
        execute_sequential
      when 'parallel'
        execute_parallel
      when 'conditional'
        execute_conditional
      when 'dag'
        execute_dag
      else
        log_warn "Unknown execution mode: #{execution_mode}, defaulting to sequential"
        execute_sequential
      end
    end

    # Execute nodes sequentially
    def execute_sequential
      queue = find_start_nodes.to_a
      visited = Set.new

      while queue.any?
        current_node = queue.shift

        # Skip if already executed (convergent flows)
        next if @node_results.key?(current_node.node_id)

        # Check prerequisites
        unless prerequisites_complete?(current_node)
          # Re-queue if prerequisites not ready
          queue << current_node unless visited.include?(current_node.node_id)
          visited << current_node.node_id
          next
        end

        # Execute node
        result = execute_node(current_node)

        # Find and queue next nodes
        next_nodes = find_next_nodes(current_node, result)
        queue.concat(next_nodes)

        # Clear visited for this node (allow re-evaluation)
        visited.delete(current_node.node_id)
      end
    end

    # Execute nodes in parallel where possible
    def execute_parallel
      # Group nodes into batches that can run in parallel
      batches = build_parallel_batches

      batches.each_with_index do |batch, index|
        log_info "Executing batch #{index + 1}/#{batches.count}", {
          nodes: batch.map(&:node_id)
        }

        if batch.count > 1
          execute_batch_parallel(batch)
        else
          execute_node(batch.first)
        end
      end
    end

    # Execute conditional branches
    def execute_conditional
      start_nodes = find_start_nodes

      start_nodes.each do |node|
        execute_conditional_branch(node)
      end
    end

    # Execute in DAG optimization mode
    def execute_dag
      # Build optimal execution plan
      execution_plan = build_dag_execution_plan

      execution_plan.each_with_index do |batch, index|
        log_debug "Executing DAG batch #{index + 1}/#{execution_plan.count}"

        if batch.count > 1
          execute_batch_parallel(batch)
        else
          execute_node(batch.first)
        end
      end
    end

    # =============================================================================
    # NODE EXECUTION
    # =============================================================================

    # Execute a single node
    #
    # @param node [AiWorkflowNode] Node to execute
    # @return [Hash] Node execution result
    def execute_node(node)
      with_monitoring('node_execution', node_id: node.node_id, node_type: node.node_type) do
        log_info "Executing node: #{node.name} (#{node.node_type})"

        # Create execution record
        node_execution = create_node_execution_record(node)

        begin
          # Transition state
          @state_manager.execute_node(node.node_id)

          # Update status using state transition method to trigger broadcasts
          # CRITICAL FIX: Use start_execution! instead of update! to trigger WebSocket broadcasts
          node_execution.start_execution!

          # Record event
          @event_store.record_node_started(node, node_execution)

          # Get node executor
          executor = get_node_executor(node, node_execution)

          # Execute node
          result = executor.execute

          # Handle success
          handle_node_success(node, node_execution, result)

          result

        rescue StandardError => e
          # Handle failure
          handle_node_failure(node, node_execution, e)
          raise NodeExecutionError, "Node #{node.node_id} failed: #{e.message}"
        end
      end
    end

    # Execute multiple nodes in parallel
    #
    # @param nodes [Array<AiWorkflowNode>] Nodes to execute
    def execute_batch_parallel(nodes)
      # Note: This is a simplified implementation
      # In production, you'd use Sidekiq or similar for true parallelism
      results = nodes.map do |node|
        Thread.new { execute_node(node) }
      end.map(&:value)

      results
    rescue StandardError => e
      log_error "Parallel batch execution failed", { error: e.message }
      raise
    end

    # =============================================================================
    # NODE EXECUTOR MANAGEMENT
    # =============================================================================

    # Get appropriate executor for node type
    #
    # @param node [AiWorkflowNode] Node to execute
    # @param node_execution [AiWorkflowNodeExecution] Execution record
    # @return [Mcp::NodeExecutors::Base] Node executor instance
    def get_node_executor(node, node_execution)
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
                      when 'start'
                        Mcp::NodeExecutors::Start
                      when 'end'
                        Mcp::NodeExecutors::End
                      else
                        raise NodeExecutionError, "Unknown node type: #{node.node_type}"
                      end

      node_context = Mcp::NodeExecutionContext.new(
        node: node,
        workflow_run: @workflow_run,
        execution_context: @execution_context,
        previous_results: @node_results
      )

      executor_class.new(
        node: node,
        node_execution: node_execution,
        node_context: node_context,
        orchestrator: self
      )
    end

    # =============================================================================
    # NODE SUCCESS/FAILURE HANDLING
    # =============================================================================

    # Handle successful node execution
    #
    # @param node [AiWorkflowNode] Executed node
    # @param node_execution [AiWorkflowNodeExecution] Execution record
    # @param result [Hash] Execution result
    def handle_node_success(node, node_execution, result)
      log_info "Node completed successfully: #{node.node_id}"

      # Store result
      @node_results[node.node_id] = result

      # Update execution context
      if result[:output_data].present?
        update_execution_context(node, result[:output_data])
      end

      # Update execution record using state transition method to trigger broadcasts
      # CRITICAL FIX: Use complete_execution! instead of update! to trigger WebSocket broadcasts
      node_execution.complete_execution!(
        result[:output_data],
        result[:cost] || 0  # Pass cost if present
      )

      # Update additional metadata if present (complete_execution! doesn't handle all fields)
      if result[:execution_time_ms].present? || result[:metadata].present?
        node_execution.update!(
          duration_ms: result[:execution_time_ms],
          metadata: (node_execution.metadata || {}).merge(result[:metadata] || {})
        )
      end

      # Record event
      @event_store.record_node_completed(node, node_execution, result)

      # Broadcast to WebSocket
      broadcast_node_execution(node, 'completed', result)

      # Track cost if present
      track_cost('node_execution', result[:cost]) if result[:cost].present?
    end

    # Handle failed node execution
    #
    # @param node [AiWorkflowNode] Failed node
    # @param node_execution [AiWorkflowNodeExecution] Execution record
    # @param error [StandardError] Error that occurred
    def handle_node_failure(node, node_execution, error)
      log_error "Node execution failed: #{node.node_id}", {
        error: error.message,
        node_type: node.node_type
      }

      # Update execution record using state transition method to trigger broadcasts
      # CRITICAL FIX: Use fail_execution! instead of update! to trigger WebSocket broadcasts
      node_execution.fail_execution!(
        error.message,
        {
          exception_class: error.class.name,
          backtrace: error.backtrace&.first(10)
        }
      )

      # Record event
      @event_store.record_node_failed(node, node_execution, error)

      # Broadcast to WebSocket
      broadcast_node_execution(node, 'failed', { error: error.message })
    end

    # =============================================================================
    # EXECUTION PLANNING
    # =============================================================================

    # Build parallel execution batches
    #
    # @return [Array<Array<AiWorkflowNode>>] Batches of nodes
    def build_parallel_batches
      batches = []
      remaining_nodes = @workflow.ai_workflow_nodes.to_a
      executed_node_ids = Set.new

      while remaining_nodes.any?
        # Find nodes that can execute now
        ready_nodes = remaining_nodes.select do |node|
          prerequisites_satisfied?(node, executed_node_ids)
        end

        break if ready_nodes.empty?

        # Add to batch
        batches << ready_nodes

        # Mark as executed
        ready_nodes.each { |node| executed_node_ids << node.node_id }

        # Remove from remaining
        remaining_nodes -= ready_nodes
      end

      batches
    end

    # Build DAG execution plan
    #
    # @return [Array<Array<AiWorkflowNode>>] Optimal execution order
    def build_dag_execution_plan
      # Use topological sort to determine optimal order
      # This is a simplified implementation
      build_parallel_batches
    end

    # Execute conditional branch
    #
    # @param node [AiWorkflowNode] Starting node
    # @param visited [Set] Set of visited node IDs
    def execute_conditional_branch(node, visited = Set.new)
      return if visited.include?(node.node_id)

      visited << node.node_id

      # Execute current node
      result = execute_node(node)

      # Find next nodes based on result
      next_nodes = find_next_nodes(node, result)

      # Recursively execute each branch
      next_nodes.each do |next_node|
        execute_conditional_branch(next_node, visited)
      end
    end

    # =============================================================================
    # HELPERS
    # =============================================================================

    # Check if node prerequisites are satisfied
    #
    # @param node [AiWorkflowNode] Node to check
    # @param executed_node_ids [Set] Set of executed node IDs
    # @return [Boolean] Whether prerequisites are satisfied
    def prerequisites_satisfied?(node, executed_node_ids)
      incoming_edges = @workflow.ai_workflow_edges.where(target_node_id: node.node_id)

      # No incoming edges means node is ready
      return true if incoming_edges.empty?

      # All source nodes must be executed
      incoming_edges.all? do |edge|
        executed_node_ids.include?(edge.source_node_id)
      end
    end

    # Create node execution record
    #
    # @param node [AiWorkflowNode] Node to create record for
    # @return [AiWorkflowNodeExecution] Created record
    def create_node_execution_record(node)
      @workflow_run.ai_workflow_node_executions.create!(
        ai_workflow_node_id: node.id,
        node_id: node.node_id,
        node_type: node.node_type,
        status: 'pending',
        started_at: Time.current,
        input_data: build_node_input_data(node),
        metadata: {
          mcp_execution: true,
          mcp_tool_id: node.mcp_tool_id,
          executor: self.class.name
        }
      )
    end

    # Build input data for node with edge data mapping support
    #
    # This method resolves input data for a node by:
    # 1. Reading edge data_mapping configuration from incoming edges
    # 2. Resolving variable paths like {{node_id.output_key}}
    # 3. Auto-passing previous results if no explicit mapping exists
    # 4. Including workflow variables as base context
    #
    # @param node [AiWorkflowNode] Node to build input for
    # @return [Hash] Input data with resolved mappings
    def build_node_input_data(node)
      input_data = {}

      # Get incoming edges to this node
      incoming_edges = @workflow.ai_workflow_edges.where(target_node_id: node.node_id)

      # Track if any explicit mapping was found
      has_explicit_mapping = false

      # Process data mapping from each incoming edge
      incoming_edges.each do |edge|
        mapping_config = edge.configuration&.dig('data_mapping')

        if mapping_config.present?
          has_explicit_mapping = true
          log_debug "Applying data mapping for #{node.name}", {
            edge: "#{edge.source_node_id} → #{edge.target_node_id}",
            mappings: mapping_config.keys
          }

          # Apply each mapping rule
          mapping_config.each do |source_path, target_key|
            value = resolve_variable_path(source_path)

            if value.present?
              input_data[target_key] = value
              log_debug "Mapped #{source_path} → #{target_key}", {
                value_type: value.class.name,
                value_size: value.is_a?(String) ? value.length : nil
              }
            else
              log_warn "Could not resolve variable path", {
                path: source_path,
                target_key: target_key
              }
            end
          end
        end
      end

      # Auto-pass previous node outputs if no explicit mapping configured
      if !has_explicit_mapping && incoming_edges.any?
        log_debug "No explicit data mapping found, auto-passing previous results", {
          node: node.name,
          incoming_edges: incoming_edges.count
        }

        # Get the most recent previous node's output (for simple sequential flows)
        source_nodes = incoming_edges.map(&:source_node_id)

        source_nodes.each do |source_node_id|
          source_result = @node_results[source_node_id]

          if source_result.present? && source_result[:output_data].present?
            # Pass the output_data from previous node
            source_result[:output_data].each do |key, value|
              # Use namespaced keys to avoid conflicts
              namespaced_key = "#{source_node_id}_#{key}"
              input_data[namespaced_key] = value

              # Also pass without namespace if it's a standard key
              if key == 'agent_output' || key == 'output' || key == 'result'
                input_data[key] = value
              end
            end

            log_debug "Auto-passed data from #{source_node_id}", {
              keys: source_result[:output_data].keys
            }
          end
        end
      end

      # Always include workflow variables as base context
      @execution_context[:variables]&.each do |key, value|
        # Don't overwrite explicitly mapped or auto-passed data
        input_data[key] ||= value
      end

      log_info "Built input data for #{node.name}", {
        keys: input_data.keys,
        has_mapping: has_explicit_mapping,
        auto_passed: !has_explicit_mapping && incoming_edges.any?
      }

      input_data
    end

    # Resolve variable path expressions
    #
    # Supports formats:
    # - {{node_id.output_key}} -> Get output from specific node
    # - {{input.variable}} -> Get workflow input variable
    # - {{context.key}} -> Get from execution context
    # - Plain strings -> Return as-is
    #
    # @param path [String] Variable path to resolve
    # @return [Object, nil] Resolved value
    def resolve_variable_path(path)
      return path unless path.is_a?(String)

      # Match variable syntax: {{source.key}}
      if path =~ /^\{\{(.+?)\.(.+?)\}\}$/
        source = $1
        key = $2

        case source
        when 'input'
          # Resolve from workflow input variables
          @execution_context[:variables]&.dig(key)

        when 'context'
          # Resolve from execution context
          @execution_context&.dig(key.to_sym)

        else
          # Resolve from node results
          node_result = @node_results[source]

          if node_result.present?
            # Try to get from output_data first, then from top level
            node_result.dig(:output_data, key) || node_result.dig(key.to_sym)
          else
            log_warn "Could not find node result for #{source}"
            nil
          end
        end
      else
        # Return plain strings as-is
        path
      end
    end

    # Resolve nested path in hash
    #
    # @param data [Hash] Hash to traverse
    # @param path [String] Dot-separated path (e.g., "user.profile.name")
    # @return [Object, nil] Value at path
    def resolve_nested_path(data, path)
      return data if path.blank?

      keys = path.split('.')
      keys.reduce(data) do |current, key|
        break nil unless current.is_a?(Hash) || current.respond_to?(:[])

        # Try symbol and string keys
        current[key.to_sym] || current[key] || current[key.to_s]
      end
    end

    # Generate final execution result
    #
    # @return [Hash] Execution result
    def generate_execution_result
      {
        status: determine_final_status,
        node_count: @node_results.count,
        execution_path: @execution_context[:execution_path],
        variables: @execution_context[:variables],
        node_results: @node_results,
        duration_ms: calculate_execution_duration,
        total_cost: calculate_total_cost
      }
    end

    # Determine final execution status
    #
    # @return [String] Status (completed or failed)
    def determine_final_status
      failed_nodes = @workflow_run.ai_workflow_node_executions.where(status: 'failed')
      failed_nodes.any? ? 'failed' : 'completed'
    end

    # Calculate total execution duration
    #
    # @return [Integer] Duration in milliseconds
    def calculate_execution_duration
      return 0 unless @workflow_run.started_at

      ((Time.current - @workflow_run.started_at) * 1000).round
    end

    # Calculate total cost
    #
    # @return [Float] Total cost in USD
    def calculate_total_cost
      @workflow_run.ai_workflow_node_executions.sum(:cost) || 0.0
    end

    # Handle execution failure
    #
    # @param error [StandardError] Error that occurred
    def handle_execution_failure(error)
      log_error "Workflow execution failed", {
        workflow_id: @workflow.id,
        run_id: @workflow_run.run_id,
        error: error.message
      }

      # Transition to failed state
      @state_manager.transition_to_failed

      # Record event
      @event_store.record_execution_failed(error)

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
    end

    # Broadcast node execution update
    #
    # @param node [AiWorkflowNode] Node
    # @param status [String] Execution status
    # @param data [Hash] Additional data
    def broadcast_node_execution(node, status, data = {})
      # Get the node execution record to use the channel's proper broadcast method
      node_execution = @workflow_run.ai_workflow_node_executions
                                    .find_by(node_id: node.node_id)

      if node_execution
        # Use the channel's class method which sets the correct 'event' field
        # and broadcasts to all appropriate streams (run, workflow, account)
        AiOrchestrationChannel.broadcast_node_execution(
          node_execution,
          'workflow.node.execution.updated'
        )
      else
        log_warn "Node execution not found for broadcast", {
          node_id: node.node_id,
          node_name: node.name
        }
      end
    rescue StandardError => e
      log_error "Failed to broadcast node execution", {
        node_id: node.node_id,
        error: e.message
      }
    end

    # Allow access to execution context (for node executors)
    def get_variable(name)
      @execution_context[:variables][name]
    end

    def set_variable(name, value)
      @execution_context[:variables][name] = value
      @workflow_run.update_column(:runtime_context, @execution_context)
    end

    # =============================================================================
    # WORKFLOW VALIDATION
    # =============================================================================

    # Validate workflow is ready for execution
    #
    # Checks:
    # - Workflow has at least one start node
    # - Workflow has at least one end node
    # - All non-start nodes have incoming edges
    # - Warns if nodes lack data mapping configuration
    # - Validates no disconnected subgraphs
    #
    # @raise [ExecutionError] If workflow is not executable
    def validate_workflow_executable!
      log_info "Validating workflow structure"

      nodes = @workflow.ai_workflow_nodes.to_a
      edges = @workflow.ai_workflow_edges.to_a

      # Check for start and end nodes
      start_nodes = nodes.select { |n| n.node_type == 'start' }
      end_nodes = nodes.select { |n| n.node_type == 'end' }

      if start_nodes.empty?
        raise ExecutionError, "Workflow must have at least one start node"
      end

      if end_nodes.empty?
        raise ExecutionError, "Workflow must have at least one end node"
      end

      # Check each node has required connections
      validation_warnings = []
      validation_errors = []

      nodes.each do |node|
        # Skip start nodes (they don't need incoming edges)
        next if node.node_type == 'start'

        # Get incoming edges
        incoming = edges.select { |e| e.target_node_id == node.node_id }

        # Check for incoming connections
        if incoming.empty?
          validation_errors << "Node '#{node.name}' (#{node.node_id}) has no incoming edges"
          next
        end

        # NEW STANDARD: All nodes with incoming edges will receive previous outputs automatically
        # No configuration required - data flow is mandatory and automatic
        log_debug "Node '#{node.name}' will receive #{incoming.count} predecessor outputs automatically"

        # Check for explicit data mapping (optional enhancement)
        has_data_mapping = incoming.any? { |e| e.configuration&.dig('data_mapping').present? }

        if has_data_mapping
          log_debug "Node '#{node.name}' has explicit data mapping configured"
        end
      end

      # Check for disconnected subgraphs
      reachable_nodes = find_reachable_nodes(start_nodes, edges)
      unreachable_nodes = nodes.reject { |n| reachable_nodes.include?(n.node_id) }

      if unreachable_nodes.any?
        unreachable_names = unreachable_nodes.map { |n| "'#{n.name}'" }.join(', ')
        validation_errors << "Disconnected nodes (not reachable from start): #{unreachable_names}"
      end

      # Check if all nodes can reach an end node
      nodes_without_path_to_end = find_nodes_without_path_to_end(nodes, edges, end_nodes)

      if nodes_without_path_to_end.any?
        dead_end_names = nodes_without_path_to_end.map { |n| "'#{n.name}'" }.join(', ')
        validation_warnings << "Dead-end nodes (no path to end node): #{dead_end_names}"
      end

      # Log warnings
      if validation_warnings.any?
        log_warn "Workflow validation warnings:", {
          count: validation_warnings.size,
          warnings: validation_warnings
        }
      end

      # Fail if errors found
      if validation_errors.any?
        error_message = "Workflow validation failed:\n" + validation_errors.join("\n")
        raise ExecutionError, error_message
      end

      log_info "Workflow validation passed", {
        nodes: nodes.size,
        edges: edges.size,
        start_nodes: start_nodes.size,
        end_nodes: end_nodes.size,
        warnings: validation_warnings.size
      }
    end

    # Find all nodes reachable from start nodes
    #
    # @param start_nodes [Array<AiWorkflowNode>] Starting nodes
    # @param edges [Array<AiWorkflowEdge>] All edges
    # @return [Set<String>] Set of reachable node IDs
    def find_reachable_nodes(start_nodes, edges)
      reachable = Set.new
      queue = start_nodes.map(&:node_id)

      while queue.any?
        current_id = queue.shift
        next if reachable.include?(current_id)

        reachable << current_id

        # Find outgoing edges from current node
        outgoing = edges.select { |e| e.source_node_id == current_id }
        outgoing.each do |edge|
          queue << edge.target_node_id unless reachable.include?(edge.target_node_id)
        end
      end

      reachable
    end

    # Find nodes that cannot reach any end node
    #
    # @param nodes [Array<AiWorkflowNode>] All nodes
    # @param edges [Array<AiWorkflowEdge>] All edges
    # @param end_nodes [Array<AiWorkflowNode>] End nodes
    # @return [Array<AiWorkflowNode>] Nodes without path to end
    def find_nodes_without_path_to_end(nodes, edges, end_nodes)
      # Build reverse edge map (target -> sources)
      reverse_edges = {}
      edges.each do |edge|
        reverse_edges[edge.target_node_id] ||= []
        reverse_edges[edge.target_node_id] << edge.source_node_id
      end

      # Find all nodes that can reach an end node (working backwards)
      can_reach_end = Set.new
      queue = end_nodes.map(&:node_id)

      while queue.any?
        current_id = queue.shift
        next if can_reach_end.include?(current_id)

        can_reach_end << current_id

        # Find incoming edges to current node
        incoming = reverse_edges[current_id] || []
        incoming.each do |source_id|
          queue << source_id unless can_reach_end.include?(source_id)
        end
      end

      # Return nodes that can't reach end
      nodes.reject { |n| can_reach_end.include?(n.node_id) || n.node_type == 'end' }
    end
  end
end
