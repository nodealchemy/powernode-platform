# frozen_string_literal: true

module Trading
  # Extracted strategy evaluation logic shared by both TradingStrategyRunnerJob
  # (independent per-strategy execution) and TradingTrainingSessionJob (legacy batch mode).
  #
  # Handles evaluator instantiation, caching, risk/regime checks, and signal generation.
  class StrategyEvaluator
    attr_reader :evaluator_cache

    def initialize(llm_client: nil, data_fetcher: nil)
      @llm_client = llm_client
      @data_fetcher = data_fetcher
      @evaluator_cache = {}
    end

    # Evaluate a strategy using a pre-fetched context.
    # Returns result hash with "_submission" key if results need to be sent to server.
    #
    # @param strategy_id [String] The strategy UUID
    # @param context [Hash] Pre-fetched evaluation context from StrategyContextBuilder
    # @param price_cache [TickPriceCache, nil] Optional shared price cache
    # @param graph_cache [Hash, nil] Optional shared graph cache
    # @return [Hash] Evaluation result
    def evaluate(strategy_id, context, price_cache: nil, graph_cache: nil)
      context ||= { "skipped" => true, "reason" => "no_context" }
      return context.merge("timeout" => false) if context["skipped"] || context["error"]

      strategy_type = context.dig("strategy", "strategy_type")
      evaluator_class = Trading::Evaluators::Base.for_type(strategy_type)

      unless evaluator_class
        return { "skipped" => true, "reason" => "unsupported_type", "timeout" => false }
      end

      risk = context["risk_check"] || {}
      unless risk["allowed"] == true || risk[:allowed] == true
        return { "skipped" => true, "reason" => risk["reason"], "timeout" => false }
      end

      regime = context["regime_check"] || {}
      unless regime["allowed"] == true || regime[:allowed] == true
        return { "skipped" => true, "reason" => regime["reason"], "timeout" => false }
      end

      # Cache evaluator instances so stateful trackers (adverse selection,
      # whipsaw) survive between evaluations instead of resetting every tick.
      cache_key = "#{strategy_id}_#{strategy_type}"
      evaluator = @evaluator_cache[cache_key]
      if evaluator
        evaluator.update_context(context)
      else
        evaluator = evaluator_class.new(
          context,
          llm_client: @llm_client,
          data_fetcher: @data_fetcher,
          price_cache: price_cache,
          graph_cache: graph_cache
        )
        @evaluator_cache[cache_key] = evaluator
      end
      evaluator.trading_context = context["trading_context"]
      signals = Array(evaluator.evaluate).compact
      tick_cost = evaluator.respond_to?(:tick_cost_usd) ? evaluator.tick_cost_usd : 0.0

      health = evaluator.respond_to?(:health_report) ? evaluator.health_report : nil

      submission = {
        strategy_id: strategy_id,
        signals: signals,
        tick_cost_usd: tick_cost,
        market_data: context["market_data"] || {},
        health_report: health
      }

      if evaluator.respond_to?(:external_data_sources) && evaluator.external_data_sources.any?
        submission[:external_data_sources] = evaluator.external_data_sources
      end

      {
        "timeout" => false,
        "signals_generated" => signals.size,
        "tick_cost_usd" => tick_cost,
        "_submission" => submission
      }
    rescue StandardError => e
      { "timeout" => e.message.include?("timeout"), "error" => e.message }
    end

    # Remove cached evaluator for a decommissioned strategy [Fix E].
    def evict(strategy_id)
      @evaluator_cache.delete_if { |key, _| key.start_with?("#{strategy_id}_") }
    end

    # Remove all cached evaluators not in the active set [Fix E].
    def prune_cache!(active_strategy_ids)
      active_set = active_strategy_ids.map(&:to_s).to_set
      @evaluator_cache.delete_if { |key, _| !active_set.include?(key.split("_").first) }
    end
  end
end
