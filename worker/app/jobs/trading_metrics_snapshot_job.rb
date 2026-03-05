# frozen_string_literal: true

class TradingMetricsSnapshotJob < BaseJob
  sidekiq_options queue: 'trading', retry: 2

  def execute(strategy_id = nil, date = nil)
    date ||= Date.current.to_s

    if strategy_id
      calculate_for_strategy(strategy_id, date)
    else
      calculate_for_all_strategies
    end
  end

  private

  def calculate_for_all_strategies
    response = api_client.get("/api/v1/internal/trading/strategies_needing_tick")
    strategies = response.dig("data", "items") || []

    log_info("Calculating metrics for #{strategies.size} strategies")

    strategies.each do |strategy|
      calculate_for_strategy(strategy["id"], Date.current.to_s)
    end

    { strategies_processed: strategies.size }
  end

  def calculate_for_strategy(strategy_id, date)
    log_info("Calculating metrics", strategy_id: strategy_id, date: date)

    response = api_client.post("/api/v1/internal/trading/calculate_metrics", {
      strategy_id: strategy_id,
      date: date
    })

    if response["success"]
      log_info("Metrics calculated", strategy_id: strategy_id)
    else
      log_warn("Metrics calculation failed", strategy_id: strategy_id, error: response["error"])
    end
  rescue StandardError => e
    log_error("Metrics calculation failed", e, strategy_id: strategy_id)
  end
end
