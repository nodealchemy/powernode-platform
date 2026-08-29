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

      # IMP-7f415874c14a — THE WRITE TO THE `learnings` JSONB ARRAY IS RETIRED.
      #
      # This used to be `self.learnings = (learnings || []) + [entry]` under a row
      # lock: an O(n) read-modify-write of the WHOLE column on every completion.
      # Production measured 548 kB across 354 entries; at the loop's 1000-iteration
      # ceiling that is ~n²/2 ≈ 1.5 GB of cumulative write traffic, on a row lock
      # #increment_iteration! also contends for. IMP-44964469b565 derived the READ
      # from ai_ralph_iterations, which fixed the read cost only — retiring the
      # write is what fixes this, and it is why the lock is gone from here.
      #
      # THE COLUMN IS DELIBERATELY NOT DROPPED. It stays dormant and empty. A
      # migration on a live install buys nothing here, and leaving it keeps the
      # read+write switch a single contiguous revertible range. Do not "finish the
      # job" by dropping it; every reader is derived from ai_ralph_iterations and
      # a drop would only remove the fallback that makes a revert cheap.
      #
      # WHY THIS IS NOT A NO-OP. #add_learning is a public model API. Both real
      # callers (RalphIteration#complete!, DevLoopTool#capture_learning) already
      # write `learning_extracted` themselves, so for them this IS a no-op — but a
      # caller that does not would otherwise have its learning silently vanish.
      # So it back-fills the surviving channel: the producing iteration's row, and
      # ONLY when that row carries nothing yet. It never CLOBBERS — the array held
      # many entries per iteration, the column holds one, and losing the first to
      # a later append would be strictly worse than dropping the later one.
      #
      # context[:iteration] is the producing iteration's number (IMP-3acfff02a847);
      # current_iteration is the fallback for a caller supplying none. Deriving the
      # target row from the context is what makes this land on the right iteration.
      #
      # G15: the scrub stays here. sanitize_output is effectively idempotent, so
      # callers that already scrubbed are unaffected, and .to_s is load-bearing —
      # sanitize_output passes a non-String through UNTOUCHED.
      def add_learning(learning_text, context: {})
        ctx = context.is_a?(Hash) ? context.symbolize_keys : {}
        text = ::DataManagement::Sanitizer.sanitize_output(learning_text.to_s).presence
        return if text.nil?

        number = ctx.fetch(:iteration, nil) || current_iteration
        iteration = ralph_iterations.find_by(iteration_number: number)
        return if iteration.nil? || iteration.learning_extracted.present?

        iteration.update!(learning_extracted: text)
      end

      # IMP-7f415874c14a — the FULL derived learning list, oldest first, in the
      # exact entry shape the jsonb array used to carry. Every reader that used to
      # index `learnings` reads this instead: ExecutionService#learnings and its
      # #learnings_by_iteration, #loop_details, the API progress endpoint, and
      # RalphLearningExtractor#extract via #extract_compound_learnings.
      #
      # A reader left on the raw column does not error — it goes PERMANENTLY EMPTY
      # for new data. That silence is why the migration had to be simultaneous.
      #
      # Unbounded on purpose: these callers always returned the whole array. The
      # bounded sibling is #recent_learnings.
      def learning_entries
        learning_iterations.order(iteration_number: :asc).map { |i| learning_entry_for(i) }
      end

      # IMP-44964469b565 — RECENCY CHANNEL: derived from ai_ralph_iterations,
      # not from the loop-level `learnings` jsonb array.
      #
      # IMP-7f415874c14a: the array is no longer written either — see #add_learning.
      # ai_ralph_iterations is now the SOLE per-iteration record of a learning, and
      # the parity audit at iteration 497 established the derivation is lossless
      # against production (0 of 354 array entries unrecoverable from the rows).
      #
      # Why the query is cheap: ORDER BY iteration_number DESC LIMIT k walks the
      # existing unique index [ralph_loop_id, iteration_number] backwards, so it
      # costs O(k) instead of deserializing an unbounded jsonb array to keep 5.
      #
      # ORDER IS UNCHANGED: ascending, oldest first, newest LAST — identical to
      # the `(learnings || []).last(limit)` this replaces. DESC is the SELECTION
      # of the newest k; the slice is reversed back before it is returned. All
      # three readers (Ralph::TaskExecutor#format_learnings,
      # ExecutionService::IterationExecution#format_learnings and
      # DevLoopTool#iteration_context) render this list in order, so flipping it
      # would silently reverse every prompt's "Previous Learnings" block.
      #
      # Blank guard: DevLoopTool writes learning_extracted directly, without
      # RalphIteration#complete!'s `.presence` normalisation, so "" is reachable
      # and must not render "- ".
      #
      # #reset! DECISION: reset! deletes the iteration rows, so this goes EMPTY
      # after a reset. That is intended — a reset is "start this run over", and
      # the recency channel is per-run context. Nothing is lost:
      # #reset! runs #extract_compound_learnings BEFORE its delete_all, and deletes
      # only if that harvest succeeded, so every learning reaches the durable
      # CompoundLearning store, which is re-injected as `relevant_learnings`.
      def recent_learnings(limit: 10)
        learning_iterations
          .order(iteration_number: :desc)
          .limit(limit)
          .to_a
          .reverse
          .map { |iteration| learning_entry_for(iteration) }
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
          # IMP-7f415874c14a: derived, not the (now dormant) `learnings` column.
          learnings: learning_entries,
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

      private

      # The single source of truth both learning readers select from. `where.not`
      # on an array containing nil is deliberate and correct: Rails renders it as
      # NOT (col = '' OR col IS NULL). The hand-written-looking NOT IN (NULL, '')
      # would match NOTHING — same intent, empty result, no error.
      def learning_iterations
        ralph_iterations.where.not(learning_extracted: [ nil, "" ]).includes(:ralph_task)
      end

      # Shape parity with the jsonb entries #add_learning used to write — readers index
      # "text"; the MCP payload carries the rest. Iteration rows also carry
      # git_commit_sha / cost / status / ralph_task_id: deliberately NOT
      # surfaced. Enriching the payload is a separate increment.
      #
      # The one field the row cannot reconstruct is context["files"], which only
      # DevLoopTool#capture_learning ever set. No reader indexes it; it is
      # dropped rather than invented, and would need its own column to return.
      def learning_entry_for(iteration)
        {
          "text" => iteration.learning_extracted,
          "iteration" => iteration.iteration_number,
          "timestamp" => (iteration.completed_at || iteration.updated_at)&.iso8601,
          "context" => {
            "iteration" => iteration.iteration_number,
            "task_key" => iteration.ralph_task&.task_key
          }.compact
        }
      end
    end
  end
end
