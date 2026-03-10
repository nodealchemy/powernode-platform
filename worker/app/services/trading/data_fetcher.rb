# frozen_string_literal: true

module Trading
  # Wraps BackendApiClient for trading-specific data operations.
  # Provides typed methods for fetching strategy evaluation context
  # and recording results back to the server.
  class DataFetcher
    BASE = "/api/v1/internal/trading"

    def initialize(api_client)
      @api = api_client
    end

    # Fetch everything needed to evaluate a strategy in one call.
    # Returns a Hash with: strategy, market_data, positions, risk_check,
    # regime_check, provider_config, agent_id, trading_context, market_question,
    # pair_registry, budget_before.
    def strategy_evaluation_context(strategy_id)
      response = @api.get("#{BASE}/strategy_evaluation_context", { strategy_id: strategy_id })
      extract_data(response)
    end

    # Post evaluation results (signals) back to the server.
    # The server creates signal records, processes orders, and updates P&L.
    def record_evaluation_result(strategy_id:, signals:, tick_cost_usd: 0.0, market_data: {})
      response = @api.post("#{BASE}/record_evaluation_result", {
        strategy_id: strategy_id,
        signals: signals,
        tick_cost_usd: tick_cost_usd,
        market_data: market_data
      })
      extract_data(response)
    end

    # Fetch related markets for combinatorial arbitrage.
    # Returns array of { pair, question, similarity, source }.
    def market_graph_related(pair:, account_id:, agent_id: nil, similarity_threshold: 0.55)
      response = @api.get("#{BASE}/market_graph_related", {
        pair: pair,
        account_id: account_id,
        agent_id: agent_id,
        similarity_threshold: similarity_threshold
      })
      data = extract_data(response)
      data["related"] || []
    end

    # Fetch ticker price for a specific pair (for related market price lookups).
    def fetch_ticker(pair:, venue_id:)
      # Use the existing price feed; this is a lightweight venue adapter call
      # routed through the server (keeps venue credentials server-side).
      response = @api.get("#{BASE}/venue_fetch_ticker", { pair: pair, venue_id: venue_id })
      extract_data(response)
    rescue StandardError
      nil
    end

    # Query RAG knowledge base for document chunks.
    def rag_query(account_id:, query:, kb_name: nil, top_k: 10)
      response = @api.get("#{BASE}/rag_query", {
        account_id: account_id,
        query: query,
        kb_name: kb_name,
        top_k: top_k
      })
      data = extract_data(response)
      data["chunks"] || []
    rescue StandardError
      []
    end

    # Update strategy config (merge additional keys).
    def update_strategy_config(strategy_id:, config_updates:)
      @api.post("#{BASE}/update_strategy_config", {
        strategy_id: strategy_id,
        config_updates: config_updates
      })
    rescue StandardError
      nil
    end

    # Fetch external data relevant to a market question.
    # Returns a Hash keyed by data source (e.g. :weather).
    # Evaluators call this to enrich their LLM context with real-world data.
    def fetch_external_data(market_question, metadata = {})
      return {} if market_question.nil? || market_question.empty?

      result = {}

      # Try NOAA weather data
      noaa = Trading::ExternalData::NoaaGfsClient.new
      if noaa.applicable?(market_question)
        weather_data = noaa.fetch_for_market(market_question, metadata)
        result[:weather] = weather_data if weather_data
      end

      result
    rescue => e
      log_error("External data fetch failed: #{e.message}")
      {}
    end

    private

    def log_error(message)
      logger = if defined?(PowernodeWorker) && PowernodeWorker.application.respond_to?(:logger)
                 PowernodeWorker.application.logger
               else
                 Logger.new($stdout)
               end
      logger.error("[Trading::DataFetcher] #{message}")
    end

    def extract_data(response)
      if response.is_a?(Hash) && response["success"]
        response["data"] || {}
      elsif response.is_a?(Hash) && response["data"]
        response["data"]
      else
        response || {}
      end
    end
  end
end
