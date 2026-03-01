# frozen_string_literal: true

module Ai
  module Planning
    class TaskDecompositionService
      COMPLEXITY_LEVELS = %w[trivial simple moderate complex expert].freeze

      DECOMPOSITION_SCHEMA = {
        type: "object",
        required: %w[plan_name subtasks execution_order],
        properties: {
          plan_name: { type: "string", description: "A concise name for the plan" },
          subtasks: {
            type: "array",
            items: {
              type: "object",
              required: %w[id description dependencies required_capability estimated_complexity],
              properties: {
                id: { type: "string", description: "Unique subtask identifier (e.g. task_1)" },
                description: { type: "string", description: "What this subtask accomplishes" },
                dependencies: {
                  type: "array",
                  items: { type: "string" },
                  description: "IDs of subtasks that must complete before this one"
                },
                required_capability: { type: "string", description: "The capability needed to execute this subtask" },
                estimated_complexity: {
                  type: "string",
                  enum: COMPLEXITY_LEVELS,
                  description: "Estimated complexity level"
                }
              }
            }
          },
          execution_order: {
            type: "array",
            items: {
              type: "array",
              items: { type: "string" }
            },
            description: "Batches of subtask IDs that can execute in parallel"
          }
        }
      }.freeze

      COMPLEXITY_COST_WEIGHTS = { "trivial" => 1, "simple" => 2, "moderate" => 5, "complex" => 10, "expert" => 20 }.freeze

      def initialize(account:)
        @account = account
      end

      def decompose(task:, agent_capabilities: [], constraints: {}, llm_client:, model:, **opts)
        messages = build_messages(task, agent_capabilities, constraints)

        result = llm_client.complete_structured(
          messages: messages,
          schema: DECOMPOSITION_SCHEMA,
          model: model,
          **opts
        )

        plan = result.deep_symbolize_keys
        validation_errors = []

        validation_errors.concat(validate_dag!(plan[:subtasks]))
        validation_errors.concat(validate_budget(plan[:subtasks], constraints[:budget_cents])) if constraints[:budget_cents]
        validation_errors.concat(validate_capabilities(plan[:subtasks], agent_capabilities)) if agent_capabilities.present?

        if validation_errors.empty?
          sorted_batches = topological_sort(plan[:subtasks])
          plan[:execution_order] = sorted_batches
        end

        {
          plan_name: plan[:plan_name],
          subtasks: plan[:subtasks],
          execution_order: plan[:execution_order],
          valid: validation_errors.empty?,
          validation_errors: validation_errors
        }
      rescue StandardError => e
        Rails.logger.error("[TaskDecomposition] Failed to decompose task: #{e.message}")
        Rails.logger.error(e.backtrace&.first(5)&.join("\n"))
        { plan_name: nil, subtasks: [], execution_order: [], valid: false, validation_errors: [e.message] }
      end

      private

      def build_messages(task, agent_capabilities, constraints)
        system_prompt = <<~PROMPT
          You are a task planning specialist. Decompose the given task into a directed acyclic graph (DAG) of subtasks.

          Rules:
          - Each subtask must have a unique ID (e.g. task_1, task_2)
          - Dependencies must reference valid subtask IDs
          - The graph must be acyclic (no circular dependencies)
          - Group independent subtasks into parallel execution batches
          - Assign realistic complexity estimates
        PROMPT

        capability_context = if agent_capabilities.present?
                               "\n\nAvailable agent capabilities: #{agent_capabilities.join(', ')}"
                             else
                               ""
                             end

        constraint_context = if constraints.present?
                               parts = []
                               parts << "budget: #{constraints[:budget_cents]} cents" if constraints[:budget_cents]
                               parts << "max steps: #{constraints[:max_steps]}" if constraints[:max_steps]
                               "\n\nConstraints: #{parts.join(', ')}"
                             else
                               ""
                             end

        [
          { role: "system", content: system_prompt },
          { role: "user", content: "Decompose this task into a DAG plan:\n\n#{task}#{capability_context}#{constraint_context}" }
        ]
      end

      def validate_dag!(subtasks)
        errors = []
        ids = subtasks.map { |s| s[:id] }.compact
        duplicates = ids.select { |id| ids.count(id) > 1 }.uniq

        errors << "Duplicate subtask IDs: #{duplicates.join(', ')}" if duplicates.any?

        subtasks.each do |subtask|
          subtask[:dependencies]&.each do |dep|
            errors << "Subtask '#{subtask[:id]}' depends on unknown ID '#{dep}'" unless ids.include?(dep)
          end
        end

        errors.concat(detect_cycles(subtasks, ids)) if errors.empty?
        errors
      end

      def detect_cycles(subtasks, ids)
        adjacency = ids.index_with { |_| [] }
        subtasks.each do |subtask|
          subtask[:dependencies]&.each { |dep| adjacency[dep] << subtask[:id] }
        end

        visited = {}
        errors = []

        ids.each do |node|
          next if visited[node] == :done

          if dfs_has_cycle?(node, adjacency, visited, [])
            errors << "Cycle detected in task dependency graph"
            break
          end
        end

        errors
      end

      def dfs_has_cycle?(node, adjacency, visited, path)
        return true if path.include?(node)
        return false if visited[node] == :done

        path.push(node)
        adjacency[node].each do |neighbor|
          return true if dfs_has_cycle?(neighbor, adjacency, visited, path)
        end
        path.pop
        visited[node] = :done
        false
      end

      def topological_sort(subtasks)
        in_degree = subtasks.each_with_object({}) { |s, h| h[s[:id]] = (s[:dependencies] || []).size }
        dependents = subtasks.each_with_object({}) do |s, h|
          s[:dependencies]&.each { |dep| (h[dep] ||= []) << s[:id] }
        end

        batches = []
        remaining = in_degree.dup

        while remaining.any?
          batch = remaining.select { |_, deg| deg.zero? }.keys
          break if batch.empty?

          batches << batch
          batch.each do |id|
            remaining.delete(id)
            dependents[id]&.each { |dep_id| remaining[dep_id] -= 1 if remaining.key?(dep_id) }
          end
        end

        batches
      end

      def validate_budget(subtasks, budget_cents)
        total_weight = subtasks.sum { |s| COMPLEXITY_COST_WEIGHTS[s[:estimated_complexity]] || 5 }
        estimated_cost = total_weight * 10

        if estimated_cost > budget_cents
          ["Estimated cost (~#{estimated_cost} cents) exceeds budget (#{budget_cents} cents)"]
        else
          []
        end
      end

      def validate_capabilities(subtasks, agent_capabilities)
        errors = []
        subtasks.each do |subtask|
          cap = subtask[:required_capability]
          next if cap.blank? || agent_capabilities.include?(cap)

          errors << "Subtask '#{subtask[:id]}' requires capability '#{cap}' not in agent capabilities"
        end
        errors
      end
    end
  end
end
