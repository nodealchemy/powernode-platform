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

    fetcher = Trading::DataFetcher.new(api_client)
    context = fetcher.strategy_evaluation_context(strategy_id)

    if context["skipped"]
      log_info("Strategy tick skipped", strategy_id: strategy_id, reason: context["reason"])
      return { "success" => true, "data" => { "skipped" => true, "reason" => context["reason"] } }
    end

    strategy_type = context.dig("strategy", "strategy_type")
    evaluator_class = Trading::Evaluators::Base.for_type(strategy_type)

    unless evaluator_class
      log_warn("No evaluator for strategy type '#{strategy_type}', skipping", strategy_id: strategy_id)
      return { "success" => true, "data" => { "skipped" => true, "reason" => "unsupported_type" } }
    end

    # Check risk/regime gates (evaluated server-side in context)
    risk = context["risk_check"] || {}
    unless risk["allowed"] == true || risk[:allowed] == true
      log_info("Strategy tick skipped (risk)", strategy_id: strategy_id, reason: risk["reason"] || risk[:reason])
      return { "success" => true, "data" => { "skipped" => true, "reason" => risk["reason"] || risk[:reason] } }
    end

    regime = context["regime_check"] || {}
    unless regime["allowed"] == true || regime[:allowed] == true
      log_info("Strategy tick skipped (regime)", strategy_id: strategy_id, reason: regime["reason"] || regime[:reason])
      return { "success" => true, "data" => { "skipped" => true, "reason" => regime["reason"] || regime[:reason] } }
    end

    # Build LLM client and evaluator
    llm = build_llm_client
    evaluator = evaluator_class.new(context, llm_client: llm, data_fetcher: fetcher)
    evaluator.trading_context = context["trading_context"]

    # Evaluate locally — LLM calls go directly to providers, no Puma thread held
    signals = evaluator.evaluate
    tick_cost = evaluator.respond_to?(:tick_cost_usd) ? evaluator.tick_cost_usd : 0.0

    # Post results back to server (creates signals, processes orders, updates P&L)
    market_data = context["market_data"] || {}
    result = fetcher.record_evaluation_result(
      strategy_id: strategy_id,
      signals: signals,
      tick_cost_usd: tick_cost,
      market_data: market_data
    )

    log_info("Strategy tick complete", strategy_id: strategy_id,
      strategy_type: strategy_type,
      signals: signals.size,
      orders: result&.dig("orders_submitted") || 0,
      cost: tick_cost.round(4))

    { "success" => true, "data" => result }
  rescue StandardError => e
    log_error("Strategy execution failed", e, strategy_id: strategy_id)
    nil
  end

  def build_llm_client
    LlmProxyClient.new(
      api_client.method(:post),
      api_client.method(:get)
    )
  end
end
