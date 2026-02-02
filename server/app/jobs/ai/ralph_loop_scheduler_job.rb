# frozen_string_literal: true

module Ai
  # RalphLoopSchedulerJob - Background job for processing scheduled Ralph Loops
  #
  # This job runs periodically (every minute) via Sidekiq-cron to:
  # - Find Ralph Loops that are due for execution
  # - Start, resume, or run iterations as appropriate
  # - Handle failures with pause/retry logic
  # - Track daily iteration counts
  #
  # Configure in config/schedule.yml:
  #   ralph_loop_scheduler:
  #     cron: "* * * * *"
  #     class: "Ai::RalphLoopSchedulerJob"
  #     queue: scheduled
  #
  class RalphLoopSchedulerJob < ApplicationJob
    queue_as :scheduled

    # Maximum loops to process per job run to prevent overload
    MAX_LOOPS_PER_RUN = 50

    # Timeout for individual loop processing
    LOOP_TIMEOUT = 5.minutes

    def perform
      Rails.logger.info("RalphLoopSchedulerJob: Starting scheduled loop processing")

      processed = 0
      errors = 0

      RalphLoop.due_for_execution.limit(MAX_LOOPS_PER_RUN).find_each do |loop|
        result = process_scheduled_loop(loop)
        processed += 1
        errors += 1 unless result[:success]
      rescue StandardError => e
        errors += 1
        Rails.logger.error("RalphLoopSchedulerJob: Error processing loop #{loop.id}: #{e.message}")
      end

      Rails.logger.info(
        "RalphLoopSchedulerJob: Completed - processed: #{processed}, errors: #{errors}"
      )

      { processed: processed, errors: errors }
    end

    private

    def process_scheduled_loop(loop)
      Rails.logger.info("RalphLoopSchedulerJob: Processing loop #{loop.id} (#{loop.name})")

      # Check if we should skip this execution
      return skip_result(loop, "Outside schedule date range") unless loop.within_schedule_range?
      return skip_result(loop, "Daily limit exceeded") if loop.exceeded_daily_limit?
      return skip_result(loop, "Already running") if loop.should_skip_if_running?

      # Execute the loop based on current status
      service = Ralph::ExecutionService.new(
        ralph_loop: loop,
        account: loop.account
      )

      result = case loop.status
      when "pending"
                 service.start_loop
      when "paused"
                 service.resume_loop
      when "running"
                 service.run_iteration
      else
                 { success: false, error: "Loop in unexpected status: #{loop.status}" }
      end

      if result[:success]
        handle_successful_execution(loop)
      else
        handle_failed_execution(loop, result[:error])
      end

      result
    rescue StandardError => e
      handle_failed_execution(loop, e.message)
      { success: false, error: e.message }
    end

    def handle_successful_execution(loop)
      # Increment daily counter
      loop.increment_daily_iteration_count!

      # Schedule next iteration
      loop.schedule_next_iteration!

      Rails.logger.info(
        "RalphLoopSchedulerJob: Loop #{loop.id} executed successfully, " \
        "next scheduled at: #{loop.next_scheduled_at}"
      )
    end

    def handle_failed_execution(loop, error_message)
      Rails.logger.error("RalphLoopSchedulerJob: Loop #{loop.id} failed: #{error_message}")

      config = loop.schedule_config

      if config["pause_on_failure"]
        # Pause the schedule
        loop.pause_schedule!(reason: "Execution failed: #{error_message}")
        Rails.logger.info("RalphLoopSchedulerJob: Loop #{loop.id} schedule paused due to failure")

      elsif config["retry_on_failure"]
        # Schedule retry after delay
        delay = config["retry_delay_seconds"] || 60
        loop.update!(next_scheduled_at: Time.current + delay.seconds)
        Rails.logger.info("RalphLoopSchedulerJob: Loop #{loop.id} scheduled for retry in #{delay}s")

      else
        # No retry/pause config - just schedule next normal iteration
        loop.schedule_next_iteration!
      end
    end

    def skip_result(loop, reason)
      Rails.logger.info("RalphLoopSchedulerJob: Skipping loop #{loop.id}: #{reason}")
      { success: true, skipped: true, reason: reason }
    end
  end
end
