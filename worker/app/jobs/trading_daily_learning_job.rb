# frozen_string_literal: true

class TradingDailyLearningJob < BaseJob
  sidekiq_options queue: 'trading', retry: 1

  def execute
    log_info("Running daily trading learning extraction")

    response = api_client.post("/api/v1/internal/trading/run_daily_learning", {})

    if response["success"]
      processed = response.dig("data", "processed") || 0
      log_info("Daily learning extraction complete", strategies_processed: processed)
    else
      log_warn("Daily learning extraction failed", error: response["error"])
    end

    response
  rescue StandardError => e
    log_error("Daily learning extraction failed", e)
    nil
  end
end
