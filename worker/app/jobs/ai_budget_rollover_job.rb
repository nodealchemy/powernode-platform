# frozen_string_literal: true

class AiBudgetRolloverJob < BaseJob
  sidekiq_options queue: 'ai_orchestration', retry: 2

  def execute(*_args)
    log_info("[BudgetRollover] Starting budget rollover processing")

    response = with_api_retry(max_attempts: 2) do
      api_client.post("/api/v1/ai/autonomy/budgets/rollover_expired")
    end

    if response['success']
      data = response['data'] || {}
      log_info("[BudgetRollover] Rolled over #{data['rolled_over']} budgets (#{data['failed']} failed)")
    else
      log_error("[BudgetRollover] Rollover endpoint returned error", error: response['error'])
    end
  end
end
