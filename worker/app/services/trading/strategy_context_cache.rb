# frozen_string_literal: true

module Trading
  # Per-strategy layered context cache. Reduces redundant API calls by caching
  # data at different staleness tiers:
  #
  #   Static  — session-lifetime: provider config, pair_registry, allocated_capital
  #   Slow    — 5-15 min: price_history, performance_context, trading learnings
  #   Fast    — per-eval: market_data (price, bid, ask) from WS Redis cache
  #
  # Each strategy runner instantiates one of these and refreshes layers as needed.
  class StrategyContextCache
    SLOW_REFRESH_INTERVAL = 300 # 5 minutes

    def initialize(strategy_id:, data_fetcher:)
      @strategy_id = strategy_id
      @data_fetcher = data_fetcher
      @static_context = nil
      @slow_context = nil
      @slow_refreshed_at = nil
    end

    # Fetch full context, using cached layers where possible.
    # Returns the same structure as StrategyContextBuilder.build
    def fetch_context
      refresh_static! unless @static_context
      refresh_slow! if slow_stale?

      # Always fetch fresh — merges are done by the caller
      fresh = @data_fetcher.strategy_evaluation_context(@strategy_id)

      # Cache the slow-changing parts for next time
      cache_layers!(fresh)

      fresh
    rescue StandardError => e
      # If fresh fetch fails but we have cached data, return a merged version
      if @static_context && @slow_context
        @static_context.merge(@slow_context).merge("cache_fallback" => true)
      else
        { "error" => e.message, "skipped" => true }
      end
    end

    # Force-refresh the static layer (e.g., after parameter mutation)
    def invalidate_static!
      @static_context = nil
    end

    # Force-refresh the slow layer
    def invalidate_slow!
      @slow_context = nil
      @slow_refreshed_at = nil
    end

    private

    def refresh_static!
      ctx = @data_fetcher.strategy_evaluation_context(@strategy_id)
      @static_context = extract_static(ctx)
      cache_layers!(ctx)
      ctx
    rescue StandardError => e
      Rails.logger.warn("[StrategyContextCache] static refresh failed: #{e.message}")
      nil
    end

    def refresh_slow!
      @slow_refreshed_at = Time.now
    end

    def slow_stale?
      @slow_refreshed_at.nil? || (Time.now - @slow_refreshed_at) > SLOW_REFRESH_INTERVAL
    end

    def cache_layers!(context)
      return unless context.is_a?(Hash) && !context["skipped"]

      @static_context = extract_static(context)
      @slow_context = extract_slow(context)
      @slow_refreshed_at = Time.now
    end

    def extract_static(ctx)
      {
        "strategy" => ctx["strategy"]&.slice(
          "id", "strategy_type", "pair", "venue_id", "account_id",
          "allocated_capital_usd", "portfolio_id"
        ),
        "provider_config" => ctx["provider_config"],
        "pair_registry" => ctx["pair_registry"],
        "agent_id" => ctx["agent_id"]
      }
    end

    def extract_slow(ctx)
      {
        "price_history" => ctx["price_history"],
        "performance_context" => ctx["performance_context"],
        "trading_context" => ctx["trading_context"]
      }
    end
  end
end
