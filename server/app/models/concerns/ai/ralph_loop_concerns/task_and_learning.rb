# frozen_string_literal: true

module Ai
  module RalphLoopConcerns
    module TaskAndLearning
      extend ActiveSupport::Concern

      # Task management

      def next_task
        ralph_tasks.pending.order(priority: :desc, position: :asc).find(&:dependencies_satisfied?)
      end

      def blocked_tasks
        ralph_tasks.where(status: "blocked")
      end

      def all_tasks_completed?
        ralph_tasks.where.not(status: %w[passed skipped]).empty?
      end

      def progress_percentage
        return 0 if total_tasks.zero?

        (completed_tasks.to_f / total_tasks * 100).round(1)
      end

      # Learning management

      def add_learning(learning_text, context: {})
        learning_entry = {
          "text" => learning_text,
          "iteration" => current_iteration,
          "timestamp" => Time.current.iso8601,
          "context" => context
        }

        self.learnings = (learnings || []) + [ learning_entry ]
        save!
      end

      def recent_learnings(limit: 10)
        (learnings || []).last(limit)
      end

      # Iteration management

      def increment_iteration!
        update!(current_iteration: current_iteration + 1)
      end

      def create_iteration(task: nil)
        ralph_iterations.create!(
          ralph_task: task,
          iteration_number: current_iteration + 1,
          status: "pending"
        )
      end

      # Summary methods

      def loop_summary
        {
          id: id,
          name: name,
          status: status,
          default_agent_id: default_agent_id,
          default_agent_name: default_agent&.name,
          mcp_server_ids: mcp_server_ids,
          current_iteration: current_iteration,
          max_iterations: max_iterations,
          total_tasks: total_tasks,
          completed_tasks: completed_tasks,
          failed_tasks: failed_tasks,
          # Frontend expects task_count and completed_task_count
          task_count: total_tasks,
          completed_task_count: completed_tasks,
          progress_percentage: progress_percentage,
          started_at: started_at&.iso8601,
          completed_at: completed_at&.iso8601,
          duration_ms: duration_ms,
          created_at: created_at.iso8601,
          # Scheduling fields
          scheduling_mode: scheduling_mode,
          schedule_paused: schedule_paused,
          next_scheduled_at: next_scheduled_at&.iso8601,
          last_scheduled_at: last_scheduled_at&.iso8601,
          daily_iteration_count: daily_iteration_count
        }
      end

      def loop_details
        loop_summary.merge(
          description: description,
          repository_url: repository_url,
          branch: branch,
          progress_text: progress_text,
          learnings: learnings,
          configuration: configuration,
          prd_json: prd_json,
          error_message: error_message,
          error_code: error_code,
          tasks: ralph_tasks.ordered.map(&:task_summary),
          recent_iterations: ralph_iterations.order(iteration_number: :desc).limit(10).map(&:iteration_summary),
          # Scheduling details
          schedule_config: schedule_config,
          schedule_paused_at: schedule_paused_at&.iso8601,
          schedule_paused_reason: schedule_paused_reason,
          webhook_token: webhook_token,
          daily_iteration_reset_at: daily_iteration_reset_at&.iso8601
        )
      end

      # MCP Server integration

      def mcp_server_ids
        configuration&.dig("mcp_server_ids") || []
      end

      def mcp_server_ids=(ids)
        self.configuration = (configuration || {}).merge("mcp_server_ids" => Array(ids).compact)
      end

      def mcp_servers
        return McpServer.none if mcp_server_ids.empty?

        account.mcp_servers.where(id: mcp_server_ids, status: "connected")
      end

      def available_mcp_tools
        mcp_servers.flat_map { |s| s.mcp_tools.where(enabled: true) }
      end
    end
  end
end
