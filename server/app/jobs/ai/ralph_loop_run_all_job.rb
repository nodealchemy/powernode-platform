# frozen_string_literal: true

module Ai
  # RalphLoopRunAllJob - Runs all remaining iterations of a Ralph Loop in background
  #
  # Enqueued by ExecutionService#run_all, checks configuration["run_all_active"]
  # each iteration to allow cancellation. Stops on completion, failure, or timeout.
  #
  class RalphLoopRunAllJob < ApplicationJob
    queue_as :ai_execution
    discard_on StandardError

    # Maximum wall-clock time before stopping
    MAX_RUNTIME = 1.hour

    # Delay between iterations to avoid overwhelming resources
    ITERATION_DELAY = 2.seconds

    def perform(ralph_loop_id, stop_on_error: true)
      ralph_loop = ::Ai::RalphLoop.find_by(id: ralph_loop_id)
      return unless ralph_loop

      start_time = Time.current
      service = ::Ai::Ralph::ExecutionService.new(ralph_loop: ralph_loop, account: ralph_loop.account)

      broadcast_run_all_started(ralph_loop)

      iterations_run = 0
      last_error = nil

      loop do
        ralph_loop.reload

        # Check cancellation flag
        break unless ralph_loop.configuration&.dig("run_all_active")

        # Check loop status
        break unless ralph_loop.status == "running"

        # Check timeout
        if Time.current - start_time > MAX_RUNTIME
          Rails.logger.info("RalphLoopRunAllJob: Timeout reached for loop #{ralph_loop.id}")
          break
        end

        # Check completion conditions
        break if ralph_loop.all_tasks_completed?
        break if ralph_loop.max_iterations_reached?

        # Run one iteration
        result = service.run_iteration
        iterations_run += 1

        unless result[:success]
          last_error = result[:error]
          Rails.logger.warn("RalphLoopRunAllJob: Iteration failed for loop #{ralph_loop.id}: #{last_error}")
          break if stop_on_error
        end

        # Brief delay between iterations
        sleep(ITERATION_DELAY)
      end

      # Deactivate run_all flag
      deactivate_run_all(ralph_loop)

      broadcast_run_all_completed(ralph_loop, iterations_run, last_error)

      Rails.logger.info(
        "RalphLoopRunAllJob: Completed loop #{ralph_loop.id} - " \
        "iterations: #{iterations_run}, error: #{last_error || 'none'}"
      )
    end

    private

    def deactivate_run_all(ralph_loop)
      config = ralph_loop.configuration || {}
      config["run_all_active"] = false
      ralph_loop.update_column(:configuration, config)
    end

    def broadcast_run_all_started(ralph_loop)
      AiOrchestrationChannel.broadcast_ralph_loop_event(ralph_loop, "run_all_started")
    rescue StandardError => e
      Rails.logger.warn("RalphLoopRunAllJob: Failed to broadcast run_all_started: #{e.message}")
    end

    def broadcast_run_all_completed(ralph_loop, iterations_run, last_error)
      ralph_loop.reload
      AiOrchestrationChannel.broadcast_ralph_loop_event(
        ralph_loop, "run_all_completed",
        { iterations_run: iterations_run, error: last_error }
      )
    rescue StandardError => e
      Rails.logger.warn("RalphLoopRunAllJob: Failed to broadcast run_all_completed: #{e.message}")
    end
  end
end
