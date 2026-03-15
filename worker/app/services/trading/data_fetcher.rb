# frozen_string_literal: true

module Trading
  # Wraps BackendApiClient for trading-specific data operations.
  # Provides typed methods for fetching strategy evaluation context
  # and recording results back to the server.
  class DataFetcher
    BASE = "/api/v1/internal/trading"

    # @param api_client [BackendApiClient] HTTP client for server API calls
    # @param ws_client [ActionCableClient, nil] optional WebSocket client for high-frequency calls
    def initialize(api_client, ws_client: nil)
      @api = api_client
      @ws = ws_client
    end

    # Whether the WebSocket transport is available.
    def ws_connected?
      @ws&.connected?
    end

    # Fetch everything needed to evaluate a strategy in one call.
    # Returns a Hash with: strategy, market_data, positions, risk_check,
    # regime_check, provider_config, agent_id, trading_context, market_question,
    # pair_registry, budget_before.
    def strategy_evaluation_context(strategy_id)
      response = @api.get("#{BASE}/strategy_evaluation_context", { strategy_id: strategy_id })
      extract_data(response)
    end

    # Fetch evaluation contexts for multiple strategies in one request.
    # Returns Hash { strategy_id => context_hash }.
    # Uses WebSocket when available (eliminates HTTP overhead on the heaviest call).
    def batch_strategy_evaluation_contexts(strategy_ids)
      if ws_connected?
        response = @ws.send_request("batch_strategy_contexts", { strategy_ids: strategy_ids })
        data = extract_ws_data(response)
        return data["contexts"] || {}
      end

      response = @api.post_with_circuit_breaker(
        "#{BASE}/batch_strategy_contexts",
        { strategy_ids: strategy_ids },
        circuit_breaker: :trading_training
      )
      data = extract_data(response)
      data["contexts"] || {}
    end

    # Post evaluation results (signals) back to the server.
    # The server creates signal records, processes orders, and updates P&L.
    def record_evaluation_result(strategy_id:, signals:, tick_cost_usd: 0.0, market_data: {})
      response = @api.post_with_circuit_breaker(
        "#{BASE}/record_evaluation_result",
        {
          strategy_id: strategy_id,
          signals: signals,
          tick_cost_usd: tick_cost_usd,
          market_data: market_data
        },
        circuit_breaker: :trading_training
      )
      extract_data(response)
    end

    # Post evaluation results for multiple strategies + optional tick progress in one request.
    # Returns Hash { "outcomes" => { strategy_id => result }, "tick_metrics" => metrics }.
    def batch_record_evaluation_results(results, session_id: nil, tick_num: nil)
      payload = { results: results }
      payload[:session_id] = session_id if session_id
      payload[:tick_num] = tick_num if tick_num

      if ws_connected?
        response = @ws.send_request("batch_record_results", payload)
        return extract_ws_data(response)
      end

      response = @api.post_with_circuit_breaker(
        "#{BASE}/batch_record_results",
        payload,
        circuit_breaker: :trading_training
      )
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

    # Batch fetch ticker prices for multiple pairs from a single venue.
    # Returns Hash { "pair" => { "last_price" => Float, "bid" => Float, "ask" => Float }, ... }
    # Pairs that fail return nil values (callers should handle gracefully).
    def batch_fetch_tickers(pairs:, venue_id:)
      return {} if pairs.empty?

      if ws_connected?
        response = @ws.send_request("batch_fetch_tickers", { venue_id: venue_id, pairs: pairs })
        data = extract_ws_data(response)
        return data["tickers"] || {}
      end

      response = @api.post_with_circuit_breaker(
        "#{BASE}/batch_fetch_tickers",
        { venue_id: venue_id, pairs: pairs },
        circuit_breaker: :trading_training
      )
      data = extract_data(response)
      data["tickers"] || {}
    rescue StandardError => e
      log_error("batch_fetch_tickers failed: #{e.message}, falling back to individual")
      results = {}
      pairs.each do |pair|
        results[pair] = fetch_ticker(pair: pair, venue_id: venue_id)
      rescue StandardError
        results[pair] = nil
      end
      results
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

    # =====================================================================
    # Decomposed training setup endpoints
    # =====================================================================

    # Discover tradeable markets from a venue.
    def discover_markets(session_id:, venue_slug:, market_count:, config: {})
      response = @api.post_with_circuit_breaker(
        "#{BASE}/discover_markets",
        { session_id: session_id, venue_slug: venue_slug,
          market_count: market_count, config: config },
        circuit_breaker: :trading_training
      )
      extract_data(response)
    end

    # Create portfolio and risk profile for a training session.
    def setup_training_portfolio(session_id:, initial_balance:)
      response = @api.post_with_circuit_breaker(
        "#{BASE}/setup_training_portfolio",
        { session_id: session_id, initial_balance: initial_balance },
        circuit_breaker: :trading_training
      )
      extract_data(response)
    end

    # Create strategies for a batch of pair/type assignments.
    def create_training_strategies(session_id:, venue_slug:, assignments:, per_strategy_capital:)
      response = @api.post_with_circuit_breaker(
        "#{BASE}/create_training_strategies",
        { session_id: session_id, venue_slug: venue_slug,
          assignments: assignments, per_strategy_capital: per_strategy_capital },
        circuit_breaker: :trading_training
      )
      extract_data(response)
    end

    # Prepare knowledge sources (news ingestion, market graph).
    def prepare_training_knowledge(session_id:, strategy_types:)
      response = @api.post_with_circuit_breaker(
        "#{BASE}/prepare_training_knowledge",
        { session_id: session_id, strategy_types: strategy_types },
        circuit_breaker: :trading_training
      )
      extract_data(response)
    end

    # Seed synthetic price history for specific pairs.
    def seed_training_prices(session_id:, pairs:)
      response = @api.post_with_circuit_breaker(
        "#{BASE}/seed_training_prices",
        { session_id: session_id, pairs: pairs },
        circuit_breaker: :trading_training
      )
      extract_data(response)
    end

    # Transition session to running and return strategy list + tick config.
    def start_training_session(session_id:)
      response = @api.post_with_circuit_breaker(
        "#{BASE}/start_training_session",
        { session_id: session_id },
        circuit_breaker: :trading_training
      )
      extract_data(response)
    end

    # Check training session status. Returns the status hash or nil on failure.
    # Used by the training job for session heartbeating and cancellation checks.
    # Returns { "success" => true, "data" => {...} } or { "session_gone" => true } on 404.
    def training_status(session_id)
      if ws_connected?
        begin
          response = @ws.send_request("training_status", { session_id: session_id })
          if response["success"]
            return { "success" => true, "data" => response["data"] || {} }
          elsif response["error"]&.include?("not found")
            return { "session_gone" => true, "error" => response["error"] }
          else
            return nil
          end
        rescue StandardError
          # WS failed — fall through to HTTP
        end
      end

      @api.post_with_circuit_breaker(
        "#{BASE}/training_status",
        { session_id: session_id },
        circuit_breaker: :trading_training
      )
    end

    # Record tick completion for a training session.
    def training_tick_complete(session_id:, tick_num:, tick_results:)
      if ws_connected?
        response = @ws.send_request("training_tick_complete", {
          session_id: session_id, tick_num: tick_num, tick_results: tick_results })
        return extract_ws_data(response)
      end

      @api.post_with_circuit_breaker(
        "#{BASE}/training_tick_complete",
        { session_id: session_id, tick_num: tick_num, tick_results: tick_results },
        circuit_breaker: :trading_training
      )
    end

    private

    # Extract data from a WebSocket response (already parsed, no HTTP wrapper).
    def extract_ws_data(response)
      return {} unless response.is_a?(Hash)

      if response["success"]
        response["data"] || {}
      elsif response["error"]
        raise StandardError, response["error"]
      else
        response
      end
    end

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
