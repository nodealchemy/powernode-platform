# frozen_string_literal: true

class TradingStrategyExecutionJob < BaseJob
  sidekiq_options queue: 'trading', retry: 2

  def execute(strategy_id = nil)
    if strategy_id
      execute_single_strategy(strategy_id)
    else
      execute_all_due_strategies
    end
  end

  private

  def execute_all_due_strategies
    response = api_client.get("/api/v1/internal/trading/strategies_needing_tick")
    strategies = response.dig("data", "items") || []

    log_info("Found #{strategies.size} strategies needing tick")

    strategies.each do |strategy|
      execute_single_strategy(strategy["id"])
    end

    { strategies_processed: strategies.size }
  end

  def execute_single_strategy(strategy_id)
    log_info("Executing strategy tick", strategy_id: strategy_id)

    response = api_client.post("/api/v1/internal/trading/execute_strategy_tick", {
      strategy_id: strategy_id
    })

    if response["success"]
      log_info("Strategy tick complete", strategy_id: strategy_id,
        signals: response.dig("data", "signals_generated"),
        orders: response.dig("data", "orders_submitted"))
    else
      log_warn("Strategy tick skipped or failed", strategy_id: strategy_id,
        reason: response.dig("data", "reason") || response["error"])
    end

    response
  rescue StandardError => e
    log_error("Strategy execution failed", e, strategy_id: strategy_id)
    nil
  end
end
