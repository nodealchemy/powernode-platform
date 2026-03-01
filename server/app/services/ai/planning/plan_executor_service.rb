# frozen_string_literal: true

module Ai
  module Planning
    class PlanExecutorService
      def initialize(account:, user:)
        @account = account
        @user = user
      end

      def execute_plan(plan:, agent_id:, input_context: {})
        unless plan[:valid]
          Rails.logger.error("[PlanExecutor] Cannot execute invalid plan: #{plan[:validation_errors].join(', ')}")
          raise ArgumentError, "Cannot execute an invalid plan: #{plan[:validation_errors].join(', ')}"
        end

        dag_definition = build_dag_definition(plan, agent_id)

        Rails.logger.info("[PlanExecutor] Executing plan '#{plan[:plan_name]}' with #{plan[:subtasks].size} subtasks")

        executor = Ai::A2a::DagExecutor.new(account: @account, user: @user)
        executor.execute(
          dag_definition: dag_definition,
          input_context: input_context,
          name: plan[:plan_name]
        )
      rescue ArgumentError
        raise
      rescue StandardError => e
        Rails.logger.error("[PlanExecutor] Failed to execute plan '#{plan[:plan_name]}': #{e.message}")
        Rails.logger.error(e.backtrace&.first(5)&.join("\n"))
        raise
      end

      private

      def build_dag_definition(plan, agent_id)
        nodes = plan[:subtasks].map do |subtask|
          {
            id: subtask[:id],
            agent_id: agent_id,
            input_mapping: {
              task: subtask[:description],
              context: "$input_context",
              required_capability: subtask[:required_capability],
              estimated_complexity: subtask[:estimated_complexity]
            }
          }
        end

        edges = plan[:subtasks].flat_map do |subtask|
          (subtask[:dependencies] || []).map do |dep_id|
            { from: dep_id, to: subtask[:id] }
          end
        end

        {
          nodes: nodes,
          edges: edges
        }
      end
    end
  end
end
