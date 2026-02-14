# frozen_string_literal: true

module Ai
  module RalphLoopConcerns
    module StateMachine
      extend ActiveSupport::Concern

      # State transition methods

      def start!
        raise InvalidTransitionError, "Cannot start loop in #{status} status" unless can_start?

        update!(
          status: "running",
          started_at: Time.current
        )
      end

      def pause!
        raise InvalidTransitionError, "Cannot pause loop in #{status} status" unless can_pause?

        update!(status: "paused")
      end

      def resume!
        raise InvalidTransitionError, "Cannot resume loop in #{status} status" unless can_resume?

        update!(status: "running")
      end

      def complete!(result: {})
        raise InvalidTransitionError, "Cannot complete loop in #{status} status" unless can_complete?

        update!(
          status: "completed",
          completed_at: Time.current,
          configuration: configuration.merge("final_result" => result)
        )
      end

      def fail!(error_message:, error_code: nil, error_details: {})
        raise InvalidTransitionError, "Cannot fail loop in #{status} status" unless can_fail?

        update!(
          status: "failed",
          completed_at: Time.current,
          error_message: error_message,
          error_code: error_code,
          error_details: error_details
        )
      end

      def cancel!(reason: nil)
        raise InvalidTransitionError, "Cannot cancel loop in #{status} status" unless can_cancel?

        update!(
          status: "cancelled",
          completed_at: Time.current,
          configuration: configuration.merge("cancellation_reason" => reason)
        )
      end

      def reset!
        raise InvalidTransitionError, "Cannot reset loop in #{status} status" unless can_reset?

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

      # State checks

      def can_start?
        status == "pending"
      end

      def can_reset?
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
        current_iteration >= max_iterations
      end
    end
  end
end
