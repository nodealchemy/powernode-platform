# frozen_string_literal: true

# Async learning extraction for trading training sessions.
# Dispatched by TradingTrainingSessionJob after each tick to extract compound
# learnings, experience replays, and stigmergic signals from recently-closed
# positions. Runs on a separate queue to avoid blocking tick progression.
class TradingLearningExtractionJob < BaseJob
  sidekiq_options queue: 'trading_learning', retry: 2

  def execute(strategy_ids, cutoff)
    response = api_client.post(
      "/api/v1/internal/trading/extract_tick_learnings",
      { strategy_ids: strategy_ids, cutoff: cutoff }
    )

    if response["success"]
      data = response["data"] || {}
      log_info("Learning extraction complete",
        extracted: data["extracted"],
        strategies: strategy_ids.size
      )
    else
      log_warn("Learning extraction returned error", error: response["error"])
    end

    response
  end
end
