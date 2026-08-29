# frozen_string_literal: true

module Ai
  module RalphLoopConcerns
    module StateMachine
      extend ActiveSupport::Concern

      TERMINAL_STATUSES = %w[completed cancelled failed].freeze

      # NOTE: this concern was extracted from Ai::RalphLoop, where
      # InvalidTransitionError is defined. A bare `raise InvalidTransitionError`
      # here resolves against this module's lexical scope and raises NameError
      # instead — guards must use the fully qualified constant.

      # State transition methods

      def start!
        raise Ai::RalphLoop::InvalidTransitionError, "Cannot start loop in #{status} status" unless can_start?

        update!(
          status: "running",
          started_at: Time.current
        )
      end

      def pause!
        raise Ai::RalphLoop::InvalidTransitionError, "Cannot pause loop in #{status} status" unless can_pause?

        update!(status: "paused")
      end

      def resume!
        raise Ai::RalphLoop::InvalidTransitionError, "Cannot resume loop in #{status} status" unless can_resume?

        update!(status: "running")
      end

      def complete!(result: {})
        raise Ai::RalphLoop::InvalidTransitionError, "Cannot complete loop in #{status} status" unless can_complete?

        if ralph_tasks.where(repeating: true).exists?
          Rails.logger.warn("[RalphLoop] Blocked completion of loop #{id} — has repeating tasks")
          return
        end

        update!(
          status: "completed",
          completed_at: Time.current,
          configuration: configuration.merge("final_result" => result)
        )

        # Tier-2(c): harvest the loop's accumulated learnings into durable
        # CompoundLearning records (idempotent, rescue-safe). Batch at completion —
        # off the per-iteration hot path.
        extract_compound_learnings
      end

      # Promote ralph-loop learnings to CompoundLearning so effective_importance /
      # decay can measure durable knowledge. No-op when there's nothing to harvest;
      # never raises (extraction is best-effort and must not block completion).
      def extract_compound_learnings
        return if account.nil? || Array(learnings).empty?

        Ai::Learning::RalphLearningExtractor.new(account: account).extract(self)
      rescue StandardError => e
        Rails.logger.warn("[RalphLoop] CompoundLearning extraction failed for loop #{id}: #{e.message}")
        nil
      end

      def fail!(error_message:, error_code: nil, error_details: {})
        raise Ai::RalphLoop::InvalidTransitionError, "Cannot fail loop in #{status} status" unless can_fail?

        update!(
          status: "failed",
          completed_at: Time.current,
          error_message: error_message,
          error_code: error_code,
          error_details: error_details
        )
      end

      def cancel!(reason: nil)
        raise Ai::RalphLoop::InvalidTransitionError, "Cannot cancel loop in #{status} status" unless can_cancel?

        update!(
          status: "cancelled",
          completed_at: Time.current,
          configuration: configuration.merge("cancellation_reason" => reason)
        )
      end

      # IMP-3acfff02a847: reset! is a do-over of the RUN, not amnesia about what the
      # run TAUGHT. Iteration rows are the record of a run and are meant to go; the
      # learnings they carry are knowledge about the codebase and are not.
      #
      # The evidence that this is preservation-by-intent rather than omission:
      # reset! SHIPPED (c015222d7) with no iteration deletion at all —
      # `ralph_iterations.delete_all` was added separately and deliberately later
      # (4ced01247, "Clear previous iteration history"). Two independent authoring
      # passes enumerated field-by-field what a reset clears, and `learnings`
      # appeared in neither. #complete! promotes learnings OUT of the loop into
      # durable CompoundLearning records; #recent_learnings feeds them forward into
      # later iterations' prompts (that feed-forward is the whole reason the loop
      # compounds); and docs/operations/ralph-loops.md names learnings as a casualty
      # only of delete_ralph_loop — full destruction — never of reset. The
      # reopen_ralph_loop tool contrasts itself with "the destructive reset!, which
      # wipes iteration history and requeues non-skipped tasks": the documented
      # destructive intent covers iteration ROWS and task status, and stops there.
      #
      # Today a learning exists in three places and delete_all destroys one, so the
      # loss is masked. The queued recency-channel redesign retires the loop-level
      # jsonb array, at which point the iteration row is the ONLY per-iteration
      # record and this delete_all silently destroys every learning the loop ever
      # produced. Hence both halves below: back-fill first, then harvest into a
      # store keyed to neither channel.
      def reset!
        raise Ai::RalphLoop::InvalidTransitionError, "Cannot reset loop in #{status} status" unless can_reset?

        transaction do
          # MUST precede delete_all — it reads the rows that are about to be dropped.
          preserve_iteration_learnings!

          # Clear previous iteration history
          ralph_iterations.delete_all

          # Reset loop state
          update!(
            status: "pending",
            current_iteration: 0,
            started_at: nil,
            completed_at: nil,
            error_message: nil,
            error_code: nil,
            error_details: {}
          )

          # Reset all tasks to pending (except those that were skipped intentionally)
          ralph_tasks.where.not(status: "skipped").update_all(
            status: "pending",
            error_message: nil,
            error_code: nil,
            execution_attempts: 0,
            completed_in_iteration: nil,
            iteration_completed_at: nil
          )
        end

        # Harvest into the durable CompoundLearning store, which is keyed to
        # neither the jsonb array nor the iteration rows and therefore survives
        # both this delete_all and the array's eventual retirement. Deliberately
        # OUTSIDE the transaction, exactly as #complete! does it: extraction
        # generates embeddings, and a network call must not hold the transaction
        # open. Idempotent (near-duplicate dedup) and rescue-safe, so resetting the
        # same loop twice harvests once and a provider outage cannot fail the reset.
        #
        # This also closes a real gap rather than only guarding a future one: only
        # #complete! harvested. A `failed` or `cancelled` loop never runs that path,
        # so its learnings had never reached the durable store at all — and those
        # are precisely the states reset! is reachable from.
        extract_compound_learnings
      end

      # IMP-3acfff02a847: copy into the loop-level `learnings` record any learning
      # that exists ONLY on an iteration row, so #reset!'s delete_all can never be
      # the sole reason a learning stops existing.
      #
      # DEDUPE IS ON TEXT ALONE — deliberately, not for want of a sharper key. The
      # obvious key, (text, iteration_number), is WRONG against every row written
      # before this change, because the top-level "iteration" stamp of an existing
      # entry is not the producing iteration's number:
      #   * ExecutionService completes the iteration (RalphIteration#complete! ->
      #     #add_learning) and only THEN calls #increment_iteration!
      #     (iteration_execution.rb:255/439), so the stamp is iteration_number - 1;
      #   * the dev-loop bridge never calls #increment_iteration! at all —
      #     #increment_iteration! is the sole writer of current_iteration — so its
      #     entries carry whatever the counter was stuck at.
      # Keying on the pair would therefore find no match for ANY pre-existing entry
      # and re-append a loop's whole learning history as duplicates on its first
      # reset. Text is the identity that actually survives; the iteration number is
      # attribution. Two iterations emitting byte-identical text collapse to one
      # entry — attribution is lost, the knowledge is not, which is the correct way
      # round for a method whose whole job is that no learning ceases to exist.
      #
      # The text is already scrubbed at both write boundaries — RalphIteration#complete!
      # and DevLoopTool#record_outcome write the SAME sanitized string to the column
      # and the array — so this copies an already-sanitized value; it is not a new
      # capture boundary.
      def preserve_iteration_learnings!
        rows = ralph_iterations.where.not(learning_extracted: nil)
                               .where.not(learning_extracted: "")
                               .order(:iteration_number)
                               .pluck(:iteration_number, :learning_extracted)
        return if rows.empty?

        # Same row lock #add_learning takes: this is a read-append-write of the
        # jsonb array, so without it a concurrent append is silently clobbered.
        with_lock do
          recorded = Array(learnings).filter_map { |entry| entry["text"] if entry.is_a?(Hash) }.to_set
          missing = rows.reject { |_number, text| recorded.include?(text) }.uniq { |_number, text| text }
          next if missing.empty?

          recovered = missing.map do |number, text|
            {
              "text" => text,
              "iteration" => number,
              "timestamp" => Time.current.iso8601,
              "context" => { "iteration" => number, "recovered_from" => "ralph_iteration" }
            }
          end
          update!(learnings: Array(learnings) + recovered)
        end
      end

      # IMP-957902bf8474: reset! is the only terminal-legal transition, and it's
      # destructive by design (wipes ralph_iterations, requeues every non-skipped
      # task). A loop that went `completed` just because its queue ran dry — not
      # because an operator chose a do-over — has no way back to `running` that
      # doesn't erase that history. #reopen! is the non-destructive sibling:
      # terminal -> running only, leaving ralph_iterations and every task's
      # status exactly as they were. Deliberately does NOT touch error_message/
      # error_code/error_details — those stay as the historical record of why a
      # failed/cancelled loop stopped; reset! is still the only way to clear them.
      def reopen!
        raise Ai::RalphLoop::InvalidTransitionError, "Cannot reopen loop in #{status} status" unless can_reopen?

        update!(status: "running", completed_at: nil)
      end

      # State checks

      def can_start?
        status == "pending"
      end

      def can_reset?
        terminal?
      end

      def can_reopen?
        terminal?
      end

      def can_pause?
        status == "running"
      end

      def can_resume?
        status == "paused"
      end

      def can_complete?
        status.in?(%w[running paused])
      end

      def can_fail?
        status.in?(%w[pending running paused])
      end

      def can_cancel?
        !terminal?
      end

      def terminal?
        TERMINAL_STATUSES.include?(status)
      end

      def in_progress?
        !terminal?
      end

      def running?
        status == "running"
      end

      def max_iterations_reached?
        return false if max_iterations.nil? || max_iterations.zero?

        current_iteration >= max_iterations
      end
    end
  end
end
