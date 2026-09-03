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
      #
      # IMP-7f415874c14a: this reader used to index the `learnings` jsonb column.
      # Left there once the write retired it would have gone permanently empty and
      # SILENTLY stopped feeding the one durable, cross-loop learning store — the
      # quietest failure in the whole change. It now derives from the iteration
      # rows like every other reader.
      #
      # THE LEGACY UNION IS NOT BELT-AND-BRACES. The column is dormant for NEW
      # data, but a loop that was reset before this change carries array entries
      # whose iteration rows are already gone. Deriving from the rows alone would
      # make those permanently unharvestable — a silent loss confined to
      # pre-existing data, which is exactly the kind no test written today catches.
      # Reading the dormant column HERE (a completion/reset path, not the hot one)
      # drains it into the durable store instead. It costs nothing once the column
      # is empty, which it is for every loop from here on.
      #
      # RETURNS true when the harvest is safe to rely on — including when there was
      # nothing to harvest — and false ONLY when extraction actually raised. #reset!
      # branches on that: a rescued failure used to be harmless because
      # #preserve_iteration_learnings! had already committed the entries elsewhere,
      # and with that gone an un-distinguishable nil would let delete_all destroy
      # learnings that never reached any durable store. Do not collapse this back to
      # a nil/truthy result: "nothing to harvest" and "the harvest blew up" must not
      # share a return value.
      def extract_compound_learnings
        entries = harvestable_learning_entries
        return true if account.nil? || entries.empty?

        Ai::Learning::RalphLearningExtractor.new(account: account).extract(self, entries: entries)
        true
      rescue StandardError => e
        Rails.logger.warn("[RalphLoop] CompoundLearning extraction failed for loop #{id}: #{e.message}")
        false
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
      # IMP-7f415874c14a — that "queued redesign" has now landed: the jsonb array is
      # no longer written, so the iteration row IS the only per-iteration record and
      # this delete_all is the sole reason a learning could stop existing.
      #
      # WHAT HAPPENED TO #preserve_iteration_learnings!. It back-filled the doomed
      # rows into the loop-level array. Its DESTINATION is now a dormant column that
      # nothing reads, so keeping it would have been writing to dead storage — and
      # deleting it outright would have silently undone the fix it was added for,
      # because the CONCERN it addressed is unchanged. So the preservation MOVED to
      # the channel that is actually read: the durable CompoundLearning store.
      #
      # THE HARVEST NOW RUNS FIRST, AND delete_all IS CONDITIONAL ON IT. Harvesting
      # after the delete (as #complete! does) was the obvious shape and it is wrong
      # here, for two compounding reasons:
      #   * the rows it reads are gone by then, so it needs a hand-carried capture;
      #   * #extract_compound_learnings RESCUES StandardError. Under
      #     #preserve_iteration_learnings! a swallowed failure was harmless — the
      #     entries were already committed to the jsonb array inside the
      #     transaction. With that gone, one rescued embedding failure (a provider
      #     outage; egress on this fleet is default-deny) would leave the rows
      #     deleted and the learnings in NO durable store, silently and permanently.
      # So: harvest while the rows still exist, and destroy them only once the
      # harvest reports success. On failure the iteration history survives the reset
      # — the loop still resets — and the next reset retries the harvest. delete_all
      # is never the sole reason a learning stops existing, which is the invariant
      # IMP-3acfff02a847 was added to hold.
      #
      # Harvesting before the state transition is safe on its own terms: extraction
      # is idempotent (near-duplicate dedup), so a transaction that then rolls back
      # leaves no duplicate on the retry.
      def reset!
        raise Ai::RalphLoop::InvalidTransitionError, "Cannot reset loop in #{status} status" unless can_reset?

        # MUST precede delete_all — it reads the rows that are about to be dropped.
        harvested = extract_compound_learnings

        transaction do
          # Clear previous iteration history — ONLY once their learnings are durable.
          ralph_iterations.delete_all if harvested

          # Reset loop state.
          #
          # current_iteration is zeroed ONLY when the rows actually went. On the
          # kept-rows path it must stay put: #create_iteration is
          # find_or_create_by!(iteration_number: current_iteration + 1), so a zeroed
          # counter would hand the next claim the SURVIVING iteration 1 — already
          # `completed`, so #complete! raises InvalidTransitionError and the loop
          # cannot run at all. Leaving it means the next run continues after the
          # retained history, which is what "we could not archive it, so we kept
          # it" should mean.
          update!(
            status: "pending",
            current_iteration: harvested ? 0 : current_iteration,
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

        # The harvest above also closes a real gap rather than only guarding a
        # future one: only #complete! harvested. A `failed` or `cancelled` loop
        # never runs that path, so its learnings had never reached the durable
        # store at all — and those are precisely the states reset! is reachable
        # from. Deliberately OUTSIDE any transaction, exactly as #complete! does
        # it: extraction generates embeddings, and a network call must not hold a
        # transaction open.
        unless harvested
          Rails.logger.warn(
            "[RalphLoop] reset #{id}: KEPT #{ralph_iterations.count} iteration rows — their learnings " \
            "could not be harvested into CompoundLearning, and delete_all would have destroyed the only copy"
          )
        end

        harvested
      end

      # The harvest's source: the derived per-iteration entries, plus any entry
      # stranded in the dormant `learnings` column whose iteration row no longer
      # exists (a loop reset before IMP-7f415874c14a). Deduped on text, the same
      # identity #preserve_iteration_learnings! used and for the same reason — the
      # legacy top-level "iteration" stamp is not the producing iteration's number,
      # so (text, iteration) matches nothing on pre-existing entries.
      def harvestable_learning_entries
        entries = learning_entries
        legacy = Array(learnings).select { |e| e.is_a?(Hash) && e["text"].present? }
        return entries if legacy.empty?

        known = entries.map { |e| e["text"] }.to_set
        entries + legacy.reject { |e| known.include?(e["text"]) }.uniq { |e| e["text"] }
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
