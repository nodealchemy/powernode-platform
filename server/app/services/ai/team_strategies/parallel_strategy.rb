# frozen_string_literal: true

module Ai
  module TeamStrategies
    class ParallelStrategy < BaseStrategy
      # Execute all members in parallel via DAG with no edges (independent nodes).
      # Results are synthesized after all agents complete.
      def execute(input:)
        members = sorted_members.to_a

        Rails.logger.info "[ParallelStrategy] Executing #{members.size} members in parallel for team #{team.id}"

        dag_definition = build_parallel_dag(members, input)
        dag_executor = Ai::A2a::DagExecutor.new(account: account, user: execution_user)

        dag_execution = dag_executor.execute(
          dag_definition: dag_definition,
          input_context: { "task" => input },
          name: "team-#{team.id}-parallel"
        )

        build_results_from_dag(dag_execution, members)
      rescue StandardError => e
        Rails.logger.error "[ParallelStrategy] DAG execution failed: #{e.message}"
        raise
      end

      private

      def build_parallel_dag(members, _input)
        nodes = members.map do |member|
          {
            id: "agent-#{member.agent_id}",
            agent_id: member.agent_id,
            input_mapping: { "task" => "$.task" },
            config: { role: member.role || "worker" }
          }
        end

        # No edges — all nodes are independent
        { nodes: nodes, edges: [] }
      end

      def build_results_from_dag(dag_execution, members)
        results = members.map do |member|
          node_id = "agent-#{member.agent_id}"
          node_result = dag_execution.node_results&.dig(node_id)

          record_task(
            agent: member.agent,
            role: member.role || "worker",
            output: node_result&.dig(:output) || node_result&.dig("output"),
            cost: node_result&.dig(:cost) || node_result&.dig("cost") || 0.0,
            tokens: node_result&.dig(:tokens_used) || node_result&.dig("tokens_used") || 0,
            duration_ms: node_result&.dig(:duration_ms) || node_result&.dig("duration_ms") || 0
          )
        end

        finalize_results(results)
      end

      def execution_user
        execution.respond_to?(:user) ? execution.user : nil
      end
    end
  end
end
