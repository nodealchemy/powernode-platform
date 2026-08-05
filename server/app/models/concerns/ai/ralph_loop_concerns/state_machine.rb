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

      def reset!
        raise Ai::RalphLoop::InvalidTransitionError, "Cannot reset loop in #{status} status" unless can_reset?

        transaction do
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
