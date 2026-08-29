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
        return false if ralph_tasks.where(repeating: true).exists?

        ralph_tasks.where.not(status: %w[passed skipped]).empty?
      end

      def progress_percentage
        return 0 if total_tasks.zero?

        (completed_tasks.to_f / total_tasks * 100).round(1)
      end

      # Learning management

      def add_learning(learning_text, context: {})
        # Tier-2(c) §5: atomic read-append-write under a row lock — concurrent
        # appends previously clobbered each other (last save! wins, entries lost).
        # IMP-3acfff02a847: the top-level "iteration" is the PRODUCING iteration's
        # number, not the loop's counter at append time. Every real caller
        # (RalphIteration#complete!, DevLoopTool#capture_learning) already passes the
        # truth as context[:iteration]; current_iteration is only the fallback for a
        # caller that supplies none. The two agree in the steady state — which is
        # exactly why the divergence is invisible — but current_iteration moves
        # independently of the iteration that produced the text (#increment_iteration!
        # can advance it between an iteration starting and its learning landing), and
        # #reset! zeroes it outright. Deriving the stamp from the context makes the
        # top-level field and context.iteration agree by construction.
        #
        # Any migration keying learnings to iterations MUST read context.iteration:
        # it is the field that was always correct, and pre-existing rows written
        # before this change carry a top-level value that only happens to match.
        ctx = context.is_a?(Hash) ? context.symbolize_keys : {}

        with_lock do
          learning_entry = {
            # G15: scrub secrets before a learning (loop output) is persisted.
            "text" => ::DataManagement::Sanitizer.sanitize_output(learning_text),
            "iteration" => ctx.fetch(:iteration, nil) || current_iteration,
            "timestamp" => Time.current.iso8601,
            "context" => context
          }
          self.learnings = (learnings || []) + [ learning_entry ]
          save!
        end
      end

      def recent_learnings(limit: 10)
        (learnings || []).last(limit)
      end

      # Iteration management

      def increment_iteration!
        # Tier-2(c) §5: serialize concurrent increments with a row lock so two
        # iterations completing at once can't both read N and write N+1 (silent
        # counter drift). The max_completed sync still recovers from crash/replay.
        with_lock do
          max_completed = ralph_iterations.maximum(:iteration_number) || current_iteration
          new_iteration = [current_iteration + 1, max_completed].max
          update!(current_iteration: new_iteration)
        end
      end

      def create_iteration(task: nil)
        next_number = current_iteration + 1
        ralph_iterations.find_or_create_by!(iteration_number: next_number) do |iter|
          iter.ralph_task = task
          iter.status = "pending"
        end
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
          account_id: account_id,
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
