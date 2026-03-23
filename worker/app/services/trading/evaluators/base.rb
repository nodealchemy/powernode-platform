# frozen_string_literal: true

module Trading
  module Evaluators
    # Worker-side strategy evaluator base class.
    #
    # Unlike server-side Trading::Strategies::Base which depends on ActiveRecord
    # models, evaluators operate on plain Hash data fetched from the Data API.
    # They produce signal Hashes that the server processes into orders.
    #
    # Subclasses implement #evaluate and return an Array of signal Hashes.
    class Base
      include Concerns::DepthAware
      include Concerns::SignalCalibration

      attr_reader :strategy_data, :market_data, :positions, :params,
                  :price_history, :allocated_capital, :parity_data, :spot_price_data, :last_entry_indicators,
                  :last_llm_cost, :external_data_sources, :order_book_data, :performance_context
      attr_accessor :trading_context

      # @param context [Hash] the full evaluation context from DataFetcher#strategy_evaluation_context
      # @param llm_client [LlmProxyClient] direct LLM client (calls providers, not server)
      # @param data_fetcher [Trading::DataFetcher] for additional data lookups
      def initialize(context, llm_client: nil, data_fetcher: nil, price_cache: nil, graph_cache: nil)
        @strategy_data = context["strategy"] || {}
        @market_data = context["market_data"] || {}
        @positions = context["positions"] || []
        @params = @strategy_data["parameters"] || {}
        @provider_config = context["provider_config"]
        @agent_id = context["agent_id"]
        @trading_context = context["trading_context"]
        @market_question = context["market_question"]
        @ensemble_role_prompts = context["ensemble_role_prompts"]
        @pair_registry = context["pair_registry"] || {}
        @price_history = context["price_history"] || []
        @allocated_capital = (context["allocated_capital"] || 0.0).to_f
        @market_expiry_raw = context["market_expiry"]
        @parity_data = context["parity_data"] || {}
        @spot_price_data = context["spot_price"] || {}
        @last_entry_indicators = context["last_entry_indicators"] || {}
        @order_book_data = context["order_book"] || {}
        @performance_context = context["performance_context"] || {}
        @is_training = context["is_training"] || false
        @llm_client = llm_client
        @data_fetcher = data_fetcher
        @price_cache = price_cache
        @graph_cache = graph_cache
        @external_data_sources = []
      end

      def training?
        @is_training
      end

      # Update context for a new tick without losing instance state (e.g., trackers).
      # Used by training jobs that cache evaluator instances across ticks.
      def update_context(context)
        @strategy_data = context["strategy"] || {}
        @market_data = context["market_data"] || {}
        @positions = context["positions"] || []
        @params = @strategy_data["parameters"] || {}
        @provider_config = context["provider_config"]
        @agent_id = context["agent_id"]
        @trading_context = context["trading_context"]
        @market_question = context["market_question"]
        @ensemble_role_prompts = context["ensemble_role_prompts"]
        @pair_registry = context["pair_registry"] || {}
        @price_history = context["price_history"] || []
        @allocated_capital = (context["allocated_capital"] || 0.0).to_f
        @market_expiry_raw = context["market_expiry"]
        @parity_data = context["parity_data"] || {}
        @spot_price_data = context["spot_price"] || {}
        @last_entry_indicators = context["last_entry_indicators"] || {}
        @order_book_data = context["order_book"] || {}
        @performance_context = context["performance_context"] || {}
        @is_training = context["is_training"] || false
        @external_data_sources = []
        # Clear memoized venue costs — params may change between ticks
        @_venue_fee_rate = nil
        @_venue_flat_fee = nil
      end

      # Subclasses override this to generate trading signals.
      # Returns Array of signal Hashes.
      def evaluate
        []
      end

      # Registry of evaluator classes by strategy type.
      # Returns nil for unregistered types (strategy is skipped).
      def self.for_type(strategy_type)
        registry[strategy_type]
      end

      def self.registry
        @registry ||= {}
      end

      def self.register(strategy_type)
        Base.registry[strategy_type] = self
      end

      # Default tick cost — subclasses accumulate in @total_cost via last_llm_cost.
      def tick_cost_usd
        @total_cost || 0.0
      end

      # Per-tick health report. Returns a Hash summarizing strategy health
      # so the server-side Overseer can read pre-computed metrics instead of
      # re-querying DB for win rate, PnL, prune eligibility, etc.
      def health_report
        closed = performance_closed_positions
        closed_count = closed.size
        winning = closed.count { |p| (p["realized_pnl_usd"] || p[:realized_pnl_usd]).to_f > 0 }
        pnl = (@strategy_data["current_pnl_usd"] || 0).to_f
        capital = @allocated_capital
        win_rate = closed_count > 0 ? (winning.to_f / closed_count).round(4) : nil
        session_ticks = (@strategy_data["session_ticks"] || 0).to_i

        {
          win_rate: win_rate,
          closed_positions: closed_count,
          open_positions: @positions.size,
          current_pnl_usd: pnl.round(4),
          drawdown_pct: capital > 0 && pnl < 0 ? ((pnl.abs / capital) * 100).round(2) : 0.0,
          tick_cost_usd: tick_cost_usd.round(6),
          prune_signal: prune_signal(closed_count, winning, pnl, @positions.size, session_ticks),
          param_suggestions: param_suggestions(closed_count, winning, pnl, capital),
          promotion_readiness: promotion_readiness(closed_count, winning, pnl, capital)
        }
      end

      private

      # Closed positions from strategy context for health reporting.
      # Prefers pre-loaded closed_positions array; falls back to performance_context.
      def performance_closed_positions
        cp = @strategy_data["closed_positions"]
        return cp if cp.is_a?(Array)

        pctx = @performance_context || {}
        pctx["closed_positions"] || pctx[:closed_positions] || []
      end

      # Prune signal: idle (0 positions after 20+ ticks) or unprofitable
      # (WR < 30%, PnL < 0, 3+ closed).
      def prune_signal(closed_count, winning, pnl, open_count, session_ticks)
        win_rate = closed_count > 0 ? (winning.to_f / closed_count) : 0.0

        idle = closed_count == 0 && open_count == 0 && session_ticks >= 20
        unprofitable = pnl < 0 && win_rate < 0.3 && closed_count >= 3

        {
          eligible: idle || unprofitable,
          reason: idle ? "idle_no_trades" : (unprofitable ? "live_underperformance" : nil),
          win_rate: win_rate.round(4),
          session_ticks: session_ticks
        }
      end

      # Suggest parameter modifications based on performance.
      def param_suggestions(closed_count, winning, pnl, capital)
        return { modifications: {} } if closed_count < 5

        win_rate = winning.to_f / closed_count
        mods = {}

        current_ct = param("confidence_threshold", 0.3).to_f

        if win_rate < 0.35 && pnl < 0
          new_ct = [current_ct + 0.1, 0.95].min.round(2)
          mods["confidence_threshold"] = { from: current_ct, to: new_ct } if new_ct != current_ct
        elsif win_rate > 0.65 && pnl > 0
          new_ct = [current_ct - 0.05, 0.05].max.round(2)
          mods["confidence_threshold"] = { from: current_ct, to: new_ct } if new_ct != current_ct
        end

        if capital > 0 && pnl < -(capital * 0.10)
          current_ps = param("position_size_pct", 8.0).to_f
          new_ps = [current_ps * 0.75, 1.0].max.round(1)
          mods["position_size_pct"] = { from: current_ps, to: new_ps } if new_ps != current_ps
        end

        { modifications: mods }
      end

      # Assess promotion readiness against PromotionCriteria thresholds.
      def promotion_readiness(closed_count, winning, pnl, capital)
        return { ready: false, reason: "insufficient_data" } if closed_count < 10

        win_rate = winning.to_f / closed_count
        pnl_pct = capital > 0 ? (pnl / capital * 100) : 0.0

        ready = win_rate >= 0.45 && pnl > 10.0 && closed_count >= 15
        pnl_override = closed_count >= 15 && pnl >= 50.0 && pnl_pct >= 5.0

        {
          ready: ready || pnl_override,
          win_rate: win_rate.round(4),
          pnl_usd: pnl.round(4),
          pnl_pct: pnl_pct.round(2),
          closed_positions: closed_count,
          path: pnl_override ? "pnl_override" : "standard"
        }
      end

      protected

      # Track an external data source consulted during evaluation.
      # Sources are persisted to strategy config for learning tag enrichment.
      def record_external_data(source_name)
        @external_data_sources << source_name unless @external_data_sources.include?(source_name)
      end

      def param(key, default = nil)
        @params.fetch(key.to_s, default)
      end

      # Venue-aware proportional fee rate (round-trip): PM=0%, Binance=0.2%, Kalshi=4%.
      # Derives venue from pair prefix (e.g., "PM_..." = Polymarket, "BN_..." = Binance).
      def venue_fee_rate
        @_venue_fee_rate ||= begin
          pair = strategy_pair || ""
          if pair.start_with?("PM")
            0.0
          elsif pair.start_with?("BN")
            param("fee_deduction_rate", 0.002).to_f  # Binance: 0.1% maker+taker = 0.2% RT
          else
            param("fee_deduction_rate", 0.04).to_f   # Kalshi: ~4% round-trip
          end
        end
      end

      # Venue-aware flat fee per contract side.
      # Polymarket: $0, Kalshi: $0.01/side, Binance: $0.
      # Memoized — called multiple times per tick in cost estimation hot path.
      def venue_flat_fee
        @_venue_flat_fee ||= begin
          pair = strategy_pair || ""
          if pair.start_with?("PM") || pair.start_with?("BN")
            0.0
          else
            0.01
          end
        end
      end

      def current_price
        (@market_data["last_price"] || @market_data[:last_price]).to_f
      end

      # Mid-price from live order book (bid/ask midpoint).
      # Preferred over last_price on venues where last trade can be stale.
      # Falls back to most recent price_history entry, then to last_price.
      def mid_price
        b = bid_price
        a = ask_price
        if b > 0 && a > 0 && (a - b).abs < 0.5
          return (b + a) / 2.0
        end

        # Fallback: most recent price_history snapshot (seeded from real CLOB data)
        if @price_history.is_a?(Array) && @price_history.any?
          last_snap = @price_history.last
          snap_price = (last_snap["price"] || last_snap[:price] || last_snap["last_price"] || last_snap[:last_price]).to_f
          return snap_price if snap_price > 0
        end

        current_price
      end

      def bid_price
        (@market_data["bid"] || @market_data[:bid]).to_f
      end

      def ask_price
        (@market_data["ask"] || @market_data[:ask]).to_f
      end

      def spread
        return nil unless bid_price > 0 && ask_price > 0
        ask_price - bid_price
      end

      def spread_pct
        return nil unless spread && bid_price > 0
        spread / bid_price
      end

      def has_open_position?
        @positions.any?
      end

      def current_position
        @positions.max_by { |p| p["opened_at"] || "" }
      end

      def strategy_pair
        @strategy_data["pair"]
      end

      def strategy_id
        @strategy_data["id"]
      end

      def account_id
        @strategy_data["account_id"]
      end

      def last_tick_at
        raw = @strategy_data["last_tick_at"]
        raw ? Time.parse(raw) : nil
      rescue ArgumentError
        nil
      end

      def market_expiry
        @market_expiry_raw ? Time.parse(@market_expiry_raw) : nil
      rescue ArgumentError
        nil
      end

      def strategy_config
        @strategy_data["config"] || {}
      end

      def agent_model
        param("llm_model", nil) || @provider_config&.dig("model") || "claude-haiku-4-5-20251001"
      end

      # Make an LLM call with structured output (JSON schema enforced).
      # Calls the AI provider directly from the worker — no server round-trip.
      # Cost is captured in @last_llm_cost before parsing strips it.
      def llm_complete_structured(messages:, schema:, model: nil, temperature: 0.3)
        @last_llm_cost = 0.0
        return nil unless @llm_client && @provider_config

        response = @llm_client.complete_structured(
          provider_config: @provider_config,
          messages: messages,
          schema: schema,
          model: model || agent_model,
          temperature: temperature
        )

        # Surface LLM errors (e.g., schema validation failures) instead of silently returning nil
        if response.is_a?(Hash) && response["finish_reason"] == "error"
          error_detail = response["error"] || response.dig("raw_response", "error") || "unknown"
          log("LLM structured call error: #{error_detail}", level: :warn)
        end

        @last_llm_cost = extract_cost(response)
        parse_structured_response(response)
      end

      # Make a standard LLM completion call.
      def llm_complete(messages:, model: nil, **opts)
        return nil unless @llm_client && @provider_config

        @llm_client.complete(
          provider_config: @provider_config,
          messages: messages,
          model: model || agent_model,
          **opts
        )
      end

      # Calculate LLM cost from a response for cost tracking.
      def extract_cost(response)
        return 0.0 unless response.is_a?(Hash)
        (response["cost"] || 0.0).to_f
      end

      def build_signal(type:, direction:, confidence:, strength: nil, reasoning: nil, indicators: {})
        edge = indicators[:edge]&.abs || indicators[:edge_pct]&.abs&./(100.0)
        is_limit = indicators[:limit_order] == true

        # Cost gate: reject entry signals where edge doesn't cover execution costs.
        # Limit orders only pay flat fees (no spread/slippage); market orders pay full round-trip.
        if type == "entry" && edge
          if indicators[:execution_cost_override]
            # Evaluator computed exact combined cost (e.g., cross-venue arb with asymmetric fees)
            effective_cost = indicators[:execution_cost_override]
          else
            effective_cost = is_limit ? min_limit_order_cost : estimate_signal_cost
            # When spread is synthetic (fabricated by StrategyContextBuilder), double the
            # cost threshold to be conservative about entering with unreliable data.
            # When spread is synthetic (fabricated by StrategyContextBuilder), double the
            # cost threshold — but only on fee-bearing venues. On zero-fee venues (PM),
            # limit orders cost nothing and the synthetic spread is irrelevant.
            effective_cost *= 2.0 if synthetic_spread? && venue_flat_fee > 0

            # Multi-leg trades (arbitrage) incur costs on each leg
            leg_count = indicators[:legs]&.size || (indicators[:multi_leg] ? 2 : 1)
            effective_cost *= leg_count if leg_count > 1
          end

          net_edge = edge - effective_cost
          return nil if net_edge <= 0
          # Venue-aware minimum net edge: fee-bearing venues (Kalshi) need meaningful
          # edge to overcome costs not fully captured by the model (settlement delay,
          # adverse selection). PM's zero fees allow any positive net edge.
          pair = strategy_pair || ""
          return nil if net_edge < 0.02 && !pair.start_with?("PM")
        else
          estimated_cost = estimate_signal_cost
          net_edge = edge ? edge - estimated_cost : nil
        end

        urgency = classify_urgency(net_edge)
        calibrated_conf = calibrate_confidence(confidence, type: type)

        {
          type: type,
          direction: direction,
          confidence: calibrated_conf,
          strength: strength&.clamp(0.0, 1.0),
          reasoning: reasoning,
          indicators: indicators.merge(net_edge: net_edge, execution_cost: effective_cost || estimated_cost, raw_confidence: confidence),
          urgency: urgency
        }
      end

      # Minimum execution cost for limit orders (flat fee only, no spread/slippage).
      # Returns cost as a fraction of contract price.
      def min_limit_order_cost
        price = [current_price, 0.01].max
        (venue_flat_fee * 2.0) / price
      end

      # Whether market data has a synthetic (fabricated) spread rather than real bid/ask.
      # When true, evaluators should be more conservative about edge estimates.
      def synthetic_spread?
        @market_data["synthetic_spread"] == true || @market_data[:synthetic_spread] == true
      end

      def classify_urgency(net_edge)
        return "medium" unless net_edge

        # Zero-fee venues profit from smaller edges — a 1% net edge on PM is
        # 100% profit (no fees to overcome). Fee-bearing venues need wider margins.
        low_threshold  = venue_flat_fee > 0 ? 0.02 : 0.005
        med_threshold  = venue_flat_fee > 0 ? 0.05 : 0.02
        high_threshold = venue_flat_fee > 0 ? 0.10 : 0.05

        if net_edge > high_threshold
          "high"
        elsif net_edge > med_threshold
          "medium"
        elsif net_edge > low_threshold
          "low"
        else
          "skip"
        end
      end

      # estimate_signal_cost is provided by Concerns::DepthAware (included above).
      # Fallback chain: order book walk → LMSR model → spread proxy.

      def parse_structured_response(response)
        return nil unless response

        content = response.is_a?(Hash) ? response["content"] : response
        return nil unless content

        if content.is_a?(Hash)
          content.deep_symbolize_keys
        elsif content.is_a?(String) && !content.empty?
          JSON.parse(content, symbolize_names: true)
        end
      rescue JSON::ParserError
        nil
      end

      def log(message, level: :info)
        PowernodeWorker.application.logger.send(level, "[Trading::Evaluators::#{self.class.name.split('::').last}] #{message}")
      end
    end
  end
end
