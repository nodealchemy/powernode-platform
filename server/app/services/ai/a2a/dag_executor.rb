# frozen_string_literal: true

module Ai
  module A2a
    class DagExecutor
      class DagError < StandardError; end
      class CycleDetectedError < DagError; end
      class NodeFailedError < DagError; end
      class TimeoutError < DagError; end

      attr_reader :execution, :account, :user

      def initialize(account:, user:)
        @account = account
        @user = user
        @a2a_service = Service.new(account: account, user: user)
      end

      # Execute a DAG of agents
      def execute(dag_definition:, input_context: {}, name: nil)
        validate_dag!(dag_definition)

        @execution = create_execution(dag_definition, name, input_context)

        begin
          @execution.update!(status: "running", started_at: Time.current)

          # Build execution plan
          execution_plan = build_execution_plan(dag_definition)
          @execution.update!(execution_plan: execution_plan)

          # Execute in topological order
          shared_context = input_context.dup
          final_outputs = {}

          execution_plan.each_with_index do |batch, batch_index|
            Rails.logger.info "DAG #{@execution.id}: Executing batch #{batch_index + 1} with #{batch.size} nodes"

            batch_results = execute_batch(batch, dag_definition, shared_context)

            # Merge outputs into shared context
            batch_results.each do |node_id, result|
              shared_context[node_id] = result[:output]
              final_outputs[node_id] = result
            end

            # Checkpoint after each batch
            save_checkpoint(batch_index, shared_context)
          end

          complete_execution!(final_outputs)
        rescue StandardError => e
          fail_execution!(e.message)
          raise
        end

        @execution
      end

      # Resume a paused/failed execution
      def resume(execution_id)
        @execution = Ai::DagExecution.find(execution_id)

        raise DagError, "Execution is not resumable" unless @execution.resumable?
        raise DagError, "Execution is not in failed state" unless @execution.status == "failed"

        # Restore from checkpoint
        checkpoint = @execution.checkpoint_data
        batch_index = checkpoint["last_batch_index"] || 0
        shared_context = checkpoint["shared_context"] || {}

        @execution.update!(status: "running")

        begin
          dag_definition = @execution.dag_definition.with_indifferent_access
          execution_plan = @execution.execution_plan

          # Continue from checkpoint
          remaining_batches = execution_plan[batch_index + 1..]
          final_outputs = checkpoint["final_outputs"] || {}

          remaining_batches.each_with_index do |batch, idx|
            actual_index = batch_index + 1 + idx

            batch_results = execute_batch(batch, dag_definition, shared_context)

            batch_results.each do |node_id, result|
              shared_context[node_id] = result[:output]
              final_outputs[node_id] = result
            end

            save_checkpoint(actual_index, shared_context, final_outputs)
          end

          complete_execution!(final_outputs)
        rescue StandardError => e
          fail_execution!(e.message)
          raise
        end

        @execution
      end

      # Cancel a running execution
      def cancel(execution_id, reason: nil)
        execution = Ai::DagExecution.find(execution_id)

        return false unless %w[pending running].include?(execution.status)

        # Cancel any running tasks
        execution.account.ai_a2a_tasks
                 .where(dag_execution_id: execution.id, status: %w[pending active])
                 .find_each do |task|
          task.cancel!(reason: reason || "DAG execution cancelled")
        end

        execution.update!(
          status: "cancelled",
          completed_at: Time.current,
          error_message: reason
        )

        true
      end

      private

      def validate_dag!(dag_definition)
        nodes = dag_definition[:nodes] || []
        edges = dag_definition[:edges] || []

        raise DagError, "DAG must have at least one node" if nodes.empty?

        # Check for cycles using topological sort
        detect_cycles!(nodes, edges)

        # Validate node references
        node_ids = nodes.map { |n| n[:id] }.to_set

        edges.each do |edge|
          unless node_ids.include?(edge[:from]) && node_ids.include?(edge[:to])
            raise DagError, "Invalid edge references: #{edge[:from]} -> #{edge[:to]}"
          end
        end
      end

      def detect_cycles!(nodes, edges)
        graph = build_adjacency_list(nodes, edges)
        visited = Set.new
        rec_stack = Set.new

        nodes.each do |node|
          if has_cycle?(node[:id], graph, visited, rec_stack)
            raise CycleDetectedError, "Cycle detected in DAG"
          end
        end
      end

      def has_cycle?(node_id, graph, visited, rec_stack)
        return true if rec_stack.include?(node_id)
        return false if visited.include?(node_id)

        visited.add(node_id)
        rec_stack.add(node_id)

        (graph[node_id] || []).each do |neighbor|
          return true if has_cycle?(neighbor, graph, visited, rec_stack)
        end

        rec_stack.delete(node_id)
        false
      end

      def build_adjacency_list(nodes, edges)
        graph = {}
        nodes.each { |n| graph[n[:id]] = [] }
        edges.each { |e| graph[e[:from]] << e[:to] }
        graph
      end

      def build_execution_plan(dag_definition)
        nodes = dag_definition[:nodes]
        edges = dag_definition[:edges]

        # Calculate in-degrees
        in_degree = Hash.new(0)
        nodes.each { |n| in_degree[n[:id]] = 0 }
        edges.each { |e| in_degree[e[:to]] += 1 }

        # Build reverse adjacency (dependencies)
        dependencies = Hash.new { |h, k| h[k] = [] }
        edges.each { |e| dependencies[e[:to]] << e[:from] }

        # Kahn's algorithm for topological sort with batching
        plan = []
        queue = nodes.select { |n| in_degree[n[:id]].zero? }.map { |n| n[:id] }

        while queue.any?
          # All nodes in current queue can run in parallel
          plan << queue.dup

          next_queue = []
          queue.each do |node_id|
            (build_adjacency_list(nodes, edges)[node_id] || []).each do |neighbor|
              in_degree[neighbor] -= 1
              next_queue << neighbor if in_degree[neighbor].zero?
            end
          end

          queue = next_queue
        end

        plan
      end

      def execute_batch(node_ids, dag_definition, shared_context)
        nodes = dag_definition[:nodes]
        results = {}

        # Execute nodes in parallel
        threads = node_ids.map do |node_id|
          Thread.new do
            node = nodes.find { |n| n[:id] == node_id }
            result = execute_node(node, shared_context)
            [node_id, result]
          end
        end

        # Collect results
        threads.each do |thread|
          node_id, result = thread.value
          results[node_id] = result

          # Update execution state
          update_node_state(node_id, result)
        end

        results
      end

      def execute_node(node, shared_context)
        node_id = node[:id]
        agent_id = node[:agent_id]
        input_mapping = node[:input_mapping] || {}
        condition = node[:condition]

        Rails.logger.info "DAG #{@execution.id}: Executing node #{node_id}"

        # Check condition
        if condition.present? && !evaluate_condition(condition, shared_context)
          Rails.logger.info "DAG #{@execution.id}: Skipping node #{node_id} - condition not met"
          return { status: "skipped", output: nil }
        end

        # Build input from context
        input = build_node_input(input_mapping, shared_context)

        # Submit A2A task
        agent = account.ai_agents.find(agent_id)
        task = @a2a_service.submit_task(
          agent: agent,
          message: { role: "user", parts: [{ type: "text", text: input.to_json }] },
          metadata: {
            dag_execution_id: @execution.id,
            dag_node_id: node_id
          },
          sync: true
        )

        # Link task to execution
        task.update!(
          dag_execution_id: @execution.id,
          dag_node_id: node_id
        )

        if task.status == "completed"
          { status: "completed", output: task.output, task_id: task.id }
        else
          raise NodeFailedError, "Node #{node_id} failed: #{task.error_message}"
        end
      end

      def build_node_input(input_mapping, shared_context)
        result = {}

        input_mapping.each do |target_key, source|
          if source.is_a?(Hash) && source[:from_node]
            # Reference to another node's output
            node_output = shared_context[source[:from_node]]
            value = source[:path] ? dig_path(node_output, source[:path]) : node_output
            result[target_key] = value
          elsif source.is_a?(String) && source.start_with?("$")
            # Variable reference
            var_name = source[1..]
            result[target_key] = shared_context[var_name]
          else
            # Literal value
            result[target_key] = source
          end
        end

        result
      end

      def dig_path(obj, path)
        path.split(".").reduce(obj) do |current, key|
          return nil if current.nil?

          if current.is_a?(Hash)
            current[key] || current[key.to_sym]
          elsif current.is_a?(Array) && key =~ /^\d+$/
            current[key.to_i]
          else
            nil
          end
        end
      end

      def evaluate_condition(condition, context)
        # Simple condition evaluation
        # Format: { "field": "node_id.path", "operator": "eq", "value": "expected" }
        field_value = dig_path(context, condition[:field])

        case condition[:operator]
        when "eq"
          field_value == condition[:value]
        when "neq"
          field_value != condition[:value]
        when "gt"
          field_value.to_f > condition[:value].to_f
        when "lt"
          field_value.to_f < condition[:value].to_f
        when "contains"
          field_value.to_s.include?(condition[:value].to_s)
        when "exists"
          !field_value.nil?
        else
          true
        end
      end

      def create_execution(dag_definition, name, input_context)
        Ai::DagExecution.create!(
          account: account,
          triggered_by: user,
          name: name || "DAG Execution #{Time.current.strftime('%Y%m%d-%H%M%S')}",
          status: "pending",
          dag_definition: dag_definition,
          shared_context: input_context,
          total_nodes: dag_definition[:nodes].size,
          resumable: true
        )
      end

      def update_node_state(node_id, result)
        node_states = @execution.node_states.dup
        node_states[node_id] = {
          status: result[:status],
          completed_at: Time.current.iso8601,
          task_id: result[:task_id]
        }

        case result[:status]
        when "completed"
          @execution.increment!(:completed_nodes)
        when "failed"
          @execution.increment!(:failed_nodes)
        end

        @execution.update!(node_states: node_states)
      end

      def save_checkpoint(batch_index, shared_context, final_outputs = {})
        @execution.update!(
          checkpoint_data: {
            last_batch_index: batch_index,
            shared_context: shared_context,
            final_outputs: final_outputs,
            checkpoint_at: Time.current.iso8601
          },
          last_checkpoint_at: Time.current
        )
      end

      def complete_execution!(final_outputs)
        @execution.update!(
          status: "completed",
          completed_at: Time.current,
          duration_ms: ((Time.current - @execution.started_at) * 1000).to_i,
          final_outputs: final_outputs
        )
      end

      def fail_execution!(error_message)
        @execution.update!(
          status: "failed",
          completed_at: Time.current,
          duration_ms: @execution.started_at ? ((Time.current - @execution.started_at) * 1000).to_i : nil,
          error_message: error_message
        )
      end
    end
  end
end
