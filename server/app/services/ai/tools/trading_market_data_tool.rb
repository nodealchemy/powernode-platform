# frozen_string_literal: true

module Ai
  module Tools
    class TradingMarketDataTool < BaseTool
      include Concerns::TradingContextResolvable

      REQUIRED_PERMISSION = "trading.view"

      def self.definition
        {
          name: "trading_market_data",
          description: "Query market data: venues, price feeds, market regime, signals",
          parameters: {
            action: { type: "string", required: true, description: "Action to perform" },
            venue_id: { type: "string", required: false, description: "Venue ID, slug, or name" },
            strategy_id: { type: "string", required: false, description: "Strategy ID or name" },
            limit: { type: "integer", required: false, description: "Max results to return" }
          }
        }
      end

      def self.action_definitions
        {
          "trading_list_venues" => {
            description: "List configured trading venues with status and type",
            parameters: {}
          },
          "trading_get_venue" => {
            description: "Get venue details including supported pairs and adapter info",
            parameters: {
              venue_id: { type: "string", required: true, description: "Venue ID, slug, or name" }
            }
          },
          "trading_test_venue_connection" => {
            description: "Test connectivity to a trading venue",
            parameters: {
              venue_id: { type: "string", required: true, description: "Venue ID, slug, or name" }
            }
          },
          "trading_list_price_feeds" => {
            description: "List active price feeds with current prices",
            parameters: {}
          },
          "trading_market_regime" => {
            description: "Get current market regime assessment (trending, ranging, volatile, etc.)",
            parameters: {}
          },
          "trading_list_signals" => {
            description: "List recent trading signals with optional strategy filter",
            parameters: {
              strategy_id: { type: "string", required: false, description: "Filter by strategy ID or name" },
              limit: { type: "integer", required: false, description: "Max results (default: 20)" }
            }
          }
        }
      end

      def self.permitted?(agent:)
        return false unless defined?(::Trading)
        super
      end

      protected

      def call(params)
        require_trading!

        case params[:action]
        when "trading_list_venues" then list_venues
        when "trading_get_venue" then get_venue(params)
        when "trading_test_venue_connection" then test_venue_connection(params)
        when "trading_list_price_feeds" then list_price_feeds
        when "trading_market_regime" then market_regime
        when "trading_list_signals" then list_signals(params)
        else error_result("Unknown action: #{params[:action]}")
        end
      rescue ActiveRecord::RecordNotFound => e
        error_result(e.message)
      end

      private

      def list_venues
        venues = Trading::Venue.order(name: :asc)

        success_result({
          venues: venues.map { |v| serialize_venue(v) },
          count: venues.size
        })
      end

      def get_venue(params)
        venue = resolve_venue(params[:venue_id])

        success_result({
          id: venue.id,
          name: venue.name,
          slug: venue.slug,
          venue_type: venue.venue_type,
          adapter_class: venue.adapter_class,
          is_active: venue.is_active,
          supported_pairs: venue.supported_pairs,
          config: venue.config,
          strategies_count: venue.strategies.count,
          credentials_count: venue.credentials.count,
          created_at: venue.created_at
        })
      end

      def test_venue_connection(params)
        venue = resolve_venue(params[:venue_id])

        adapter = venue.adapter_class.constantize.new(venue)
        adapter.fetch_balances

        success_result({
          venue_id: venue.id,
          name: venue.name,
          connection: "ok",
          message: "Successfully connected to #{venue.name}"
        })
      rescue StandardError => e
        success_result({
          venue_id: venue.id,
          name: venue.name,
          connection: "failed",
          message: "Connection failed: #{e.message}"
        })
      end

      def list_price_feeds
        feeds = Trading::PriceFeed.where(is_active: true).order(pair: :asc)

        success_result({
          feeds: feeds.map do |f|
            {
              id: f.id,
              name: f.name,
              source: f.source,
              pair: f.pair,
              interval: f.interval,
              is_active: f.is_active,
              last_price: f.last_price&.to_f,
              last_updated_at: f.last_updated_at,
              stale: f.stale?
            }
          end,
          count: feeds.size
        })
      end

      def market_regime
        unless defined?(Trading::MarketRegimeService)
          return error_result("Market regime service is not available")
        end

        service = Trading::MarketRegimeService.new(account)

        # Aggregate regime from recent training activity and active price feeds
        venue_regimes = {}
        Trading::Venue.where(is_active: true).each do |venue|
          pairs = Trading::Strategy.joins(:portfolio)
            .where(trading_portfolios: { account_id: account.id })
            .where(trading_venue_id: venue.id)
            .where("trading_strategies.updated_at > ?", 7.days.ago)
            .distinct.pluck(:pair).first(5)

          next if pairs.empty?

          pair_regimes = pairs.filter_map do |pair|
            regime = service.classify(pair)
            regime unless regime[:trend] == "sideways" && regime[:volatility] == "normal" # skip pure defaults
          rescue StandardError
            nil
          end

          venue_regimes[venue.slug] = pair_regimes.first || service.send(:default_regime) if pairs.any?
        end

        # Build strategy suitability from the dominant regime
        dominant = venue_regimes.values.first || service.send(:default_regime)
        suitability = Trading::MarketRegimeService::REGIME_SUITABILITY.map do |strategy_type, scores|
          trend_score = scores[dominant[:trend]&.to_sym] || 0.7
          vol_score = scores[dominant[:volatility]&.to_sym] || 0.7
          { strategy_type: strategy_type, suitability: ((trend_score + vol_score) / 2.0).round(3) }
        end.sort_by { |s| -s[:suitability] }

        success_result({
          dominant_regime: dominant,
          venue_regimes: venue_regimes,
          strategy_suitability: suitability,
          assessment_note: venue_regimes.empty? ? "No active venues with recent trading data — using default regime" : nil
        }.compact)
      rescue StandardError => e
        error_result("Market regime assessment failed: #{e.message}")
      end

      def list_signals(params)
        portfolio = resolve_portfolio
        scope = Trading::Signal.joins(:strategy)
          .where(trading_strategies: { trading_portfolio_id: portfolio.id })

        if params[:strategy_id].present?
          strategy = resolve_strategy(params[:strategy_id])
          scope = scope.where(trading_strategy_id: strategy.id)
        end

        limit = (params[:limit] || 20).to_i.clamp(1, 100)

        success_result({
          signals: scope.order(created_at: :desc).limit(limit).map { |s| serialize_signal(s) },
          count: scope.count
        })
      end

      def serialize_venue(venue)
        {
          id: venue.id,
          name: venue.name,
          slug: venue.slug,
          venue_type: venue.venue_type,
          is_active: venue.is_active,
          supported_pairs_count: venue.supported_pairs&.size || 0,
          strategies_count: venue.strategies.count,
          created_at: venue.created_at
        }
      end

      def serialize_signal(signal)
        {
          id: signal.id,
          signal_type: signal.signal_type,
          direction: signal.direction,
          pair: signal.pair,
          confidence: signal.confidence.to_f,
          strength: signal.strength&.to_f,
          price: signal.price&.to_f,
          reasoning: signal.reasoning,
          status: signal.status,
          strategy_id: signal.trading_strategy_id,
          strategy_name: signal.strategy&.name,
          indicators: signal.indicators,
          acted_on_at: signal.acted_on_at,
          created_at: signal.created_at,
          expires_at: signal.expires_at
        }
      end
    end
  end
end
