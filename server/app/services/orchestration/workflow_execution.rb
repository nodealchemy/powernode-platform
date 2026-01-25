# frozen_string_literal: true

module Orchestration
  module WorkflowExecution
    def orchestrate_workflow(workflow_config)
      @logger.info "Starting AI workflow orchestration for account #{@account.id}"

      validate_workflow_config!(workflow_config)
      workflow_execution = create_workflow_execution(workflow_config)
      AiExecutionStatusChannel.broadcast_workflow_status(workflow_execution)

      begin
        execute_workflow_by_order(workflow_execution, workflow_config)
      rescue StandardError => e
        @logger.error "Workflow orchestration failed: #{e.message}"
        workflow_execution.update!(
          status: "failed",
          error_message: e.message,
          completed_at: Time.current
        )
        AiExecutionStatusChannel.broadcast_workflow_status(workflow_execution)
        raise Ai::AgentOrchestrationService::OrchestrationError, "Workflow execution failed: #{e.message}"
      end

      workflow_execution
    end

    def execute_workflow(input_variables: {}, user: nil, trigger_type: "manual")
      @logger.info "Starting workflow execution for workflow #{@workflow.id}"

      run = @workflow.runs.create!(
        account: @account,
        triggered_by_user: user || @user,
        trigger_type: trigger_type,
        input_variables: input_variables,
        run_id: SecureRandom.uuid,
        status: "initializing",
        started_at: Time.current,
        total_nodes: @workflow.nodes.count,
        runtime_context: build_workflow_execution_context
      )

      begin
        orchestrator = Mcp::AiWorkflowOrchestrator.new(workflow_run: run, account: @account, user: user || @user)
        orchestrator.execute
        run.reload
        @logger.info "Completed workflow execution for run #{run.run_id} with status: #{run.status}"
      rescue StandardError => e
        @logger.error "Workflow execution failed: #{e.message}"
        run.fail_execution!(e.message, {
          exception_class: e.class.name,
          backtrace: e.backtrace&.first(5)
        })
      end

      run
    end

    def validate_workflow_structure
      errors = []
      nodes = @workflow.nodes.includes(:source_edges, :target_edges)
      edges = @workflow.edges

      start_nodes = nodes.select(&:is_start_node?)
      end_nodes = nodes.select(&:is_end_node?)

      errors << "Workflow must have at least one start node" if start_nodes.empty?
      errors << "Workflow must have at least one end node" if end_nodes.empty?

      connected_nodes = Set.new
      edges.each do |edge|
        connected_nodes.add(edge.source_node_id)
        connected_nodes.add(edge.target_node_id)
      end

      disconnected = nodes.reject { |node| connected_nodes.include?(node.node_id) || node.is_start_node? || node.is_end_node? }
      if disconnected.any?
        errors << "Found #{disconnected.count} disconnected nodes: #{disconnected.map(&:name).join(', ')}"
      end

      if has_circular_dependency?(nodes, edges)
        errors << "Workflow contains circular dependency"
      end

      nodes.each do |node|
        unless node.valid?
          errors << "Node '#{node.name}' has invalid configuration: #{node.errors.full_messages.join(', ')}"
        end
      end

      { valid: errors.empty?, errors: errors }
    end

    def calculate_execution_path(context_variables = {})
      nodes = @workflow.nodes.includes(:source_edges, :target_edges)
      edges = @workflow.edges

      start_nodes = nodes.select(&:is_start_node?)
      return [] if start_nodes.empty?

      path = []
      visited = Set.new

      start_nodes.each do |start_node|
        path.concat(trace_execution_path(start_node, nodes, edges, context_variables, visited))
      end

      path.uniq
    end

    private

    def validate_workflow_config!(config)
      required_keys = %w[name agents execution_order]
      missing_keys = required_keys - config.keys.map(&:to_s)

      if missing_keys.any?
        raise Ai::AgentOrchestrationService::OrchestrationError, "Missing required workflow configuration keys: #{missing_keys.join(', ')}"
      end

      unless config["agents"].is_a?(Array) && config["agents"].any?
        raise Ai::AgentOrchestrationService::OrchestrationError, "Workflow must specify at least one agent"
      end
    end

    def create_workflow_execution(config)
      raise Ai::AgentOrchestrationService::OrchestrationError, "Legacy workflow execution creation is deprecated. Use MCP workflows instead."
    end

    def execute_workflow_by_order(workflow_execution, config)
      workflow_execution.update!(status: "running", started_at: Time.current)

      results = case config["execution_order"]
      when "sequential"
        execute_sequential_workflow(workflow_execution, config)
      when "parallel"
        execute_parallel_workflow(workflow_execution, config)
      when "conditional"
        execute_conditional_workflow(workflow_execution, config)
      else
        raise Ai::AgentOrchestrationService::OrchestrationError, "Unknown execution order: #{config['execution_order']}"
      end

      final_output = compile_workflow_output(results, config)

      workflow_execution.update!(
        status: "completed",
        completed_at: Time.current,
        output_variables: final_output
      )
    end

    def execute_sequential_workflow(workflow_execution, config)
      results = []
      total_agents = config["agents"].size

      config["agents"].each_with_index do |agent_config, index|
        agent = @account.ai_agents.find(agent_config["id"])
        input = build_agent_input(agent_config, results, index)

        progress = (index.to_f / total_agents * 100).round(1)
        workflow_execution.update!(
          metadata: workflow_execution.metadata.merge(
            "progress_percentage" => progress,
            "current_step" => index + 1,
            "total_steps" => total_agents,
            "current_agent" => agent.name
          )
        )

        broadcast_workflow_update(workflow_execution, {
          type: "workflow_progress",
          message: "Processing step #{index + 1}/#{total_agents}: #{agent.name}",
          current_agent: agent.name
        })

        execution = execute_agent_with_orchestration(agent, input,
          workflow_context: workflow_execution,
          step_index: index
        )

        wait_for_execution_completion(execution)

        results << {
          agent_id: agent.id,
          execution_id: execution.id,
          result: execution.reload.output_data
        }
      end

      workflow_execution.update!(
        metadata: workflow_execution.metadata.merge(
          "progress_percentage" => 100,
          "completed_steps" => total_agents,
          "results" => results
        )
      )

      broadcast_workflow_update(workflow_execution, {
        type: "workflow_completed",
        message: "Workflow execution completed successfully"
      })

      results
    end

    def execute_parallel_workflow(workflow_execution, config)
      executions = []

      config["agents"].each_with_index do |agent_config, index|
        agent = @account.ai_agents.find(agent_config["id"])
        input = build_agent_input(agent_config, [], index)

        execution = execute_agent_with_orchestration(agent, input,
          workflow_context: workflow_execution,
          step_index: index
        )

        executions << execution
      end

      wait_for_all_executions_completion(executions)

      results = executions.map do |execution|
        execution.reload
        {
          agent_id: execution.agent.id,
          execution_id: execution.id,
          result: execution.output_data
        }
      end

      workflow_execution.update!(
        metadata: workflow_execution.metadata.merge("results" => results)
      )

      results
    end

    def execute_conditional_workflow(workflow_execution, config)
      results = []

      condition_met = evaluate_workflow_condition(config["condition"] || {})
      agents_to_execute = condition_met ? config["agents"] : config["fallback_agents"] || []

      agents_to_execute.each_with_index do |agent_config, index|
        agent = @account.ai_agents.find(agent_config["id"])
        input = build_agent_input(agent_config, results, index)

        execution = execute_agent_with_orchestration(agent, input,
          workflow_context: workflow_execution,
          step_index: index
        )

        wait_for_execution_completion(execution)

        results << {
          agent_id: agent.id,
          execution_id: execution.id,
          result: execution.reload.output_data
        }
      end

      workflow_execution.update!(
        metadata: workflow_execution.metadata.merge(
          "condition_met" => condition_met,
          "results" => results
        )
      )

      results
    end

    def evaluate_workflow_condition(condition)
      condition.present? ? true : false
    end

    def compile_workflow_output(results, config)
      return {} if results.blank?

      if config["execution_order"] == "sequential"
        last_result = results.last
        {
          "primary_output" => last_result&.dig("result"),
          "all_results" => results,
          "execution_summary" => {
            "total_steps" => results.size,
            "completion_time" => Time.current.iso8601,
            "success" => true
          }
        }
      else
        {
          "results" => results,
          "execution_summary" => {
            "total_executions" => results.size,
            "completion_time" => Time.current.iso8601,
            "success" => true
          }
        }
      end
    end

    def has_circular_dependency?(nodes, edges)
      graph = build_adjacency_graph(edges)
      visited = Set.new
      rec_stack = Set.new

      nodes.each do |node|
        next if visited.include?(node.node_id)
        return true if has_cycle_dfs(node.node_id, graph, visited, rec_stack)
      end

      false
    end

    def build_adjacency_graph(edges)
      graph = Hash.new { |h, k| h[k] = [] }
      edges.each do |edge|
        graph[edge.source_node_id] << edge.target_node_id
      end
      graph
    end

    def has_cycle_dfs(node_id, graph, visited, rec_stack)
      visited.add(node_id)
      rec_stack.add(node_id)

      graph[node_id].each do |neighbor|
        if !visited.include?(neighbor)
          return true if has_cycle_dfs(neighbor, graph, visited, rec_stack)
        elsif rec_stack.include?(neighbor)
          return true
        end
      end

      rec_stack.delete(node_id)
      false
    end

    def trace_execution_path(current_node, nodes, edges, context_variables, visited)
      return [] if visited.include?(current_node.id)
      visited.add(current_node.id)

      path = [current_node]
      outgoing_edges = edges.select { |e| e.source_node_id == current_node.node_id }

      outgoing_edges.each do |edge|
        target_node = nodes.find { |n| n.node_id == edge.target_node_id }
        next unless target_node

        if edge.is_conditional? && context_variables.present?
          next unless evaluate_edge_condition(edge, context_variables)
        end

        path.concat(trace_execution_path(target_node, nodes, edges, context_variables, visited.dup))
      end

      path
    end

    def evaluate_edge_condition(edge, context_variables)
      condition = edge.condition_config
      return true if condition.blank?
      true
    end
  end
end
