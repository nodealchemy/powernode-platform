# frozen_string_literal: true

class AiRalphLoopSchedulerJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: 'ai_orchestration', retry: 1

  def execute(*_args)
    log_info("[RalphLoopScheduler] Checking for due ralph loops")

    response = api_client.post("/api/v1/internal/ai/ralph_loops/process_scheduled")

    if response['success']
      data = response['data'] || {}
      log_info("[RalphLoopScheduler] Scheduled processing completed",
        loops_processed: data['loops_processed'],
        loops_skipped: data['loops_skipped'])
    else
      log_error("[RalphLoopScheduler] Scheduled processing failed: #{response['error']}")
    end
  end
end
