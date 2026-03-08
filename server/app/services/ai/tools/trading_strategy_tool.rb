# frozen_string_literal: true

module Ai
  module Tools
    class TradingStrategyTool < BaseTool
      include Concerns::TradingContextResolvable

      REQUIRED_PERMISSION = "trading.view"

      def self.definition
        {
          name: "trading_strategy_management",
          description: "Manage trading strategies: list, inspect, create, update, lifecycle actions, performance",
          parameters: {
            action: { type: "string", required: true, description: "Action to perform" },
            strategy_id: { type: "string", required: false, description: "Strategy ID or name" },
            name: { type: "string", required: false, description: "Strategy name" },
            strategy_type: { type: "string", required: false, description: "Strategy type" },
            venue_id: { type: "string", required: false, description: "Venue ID or name" },
            pair: { type: "string", required: false, description: "Trading pair" },
            status: { type: "string", required: false, description: "Filter by status" },
            type: { type: "string", required: false, description: "Filter by strategy type" },
            parameters: { type: "object", required: false, description: "Strategy parameters" },
            config: { type: "object", required: false, description: "Strategy configuration" },
            days: { type: "integer", required: false, description: "Lookback period in days" },
            approved: { type: "boolean", required: false, description: "Approval flag for phase advancement" },
            risk_tier: { type: "string", required: false, description: "Risk tier: low, medium, high, extreme" },
            allocated_capital_usd: { type: "number", required: false, description: "Allocated capital in USD" }
          }
        }
      end

      def self.action_definitions
        {
          "trading_list_strategies" => {
            description: "List trading strategies with optional status and type filters",
            parameters: {
              status: { type: "string", required: false, description: "Filter by status: draft, active, paused, declining, decommissioned" },
              type: { type: "string", required: false, description: "Filter by strategy type" }
            }
          },
          "trading_get_strategy" => {
            description: "Get detailed strategy info including parameters, positions, trades, and win rate",
            parameters: {
              strategy_id: { type: "string", required: true, description: "Strategy ID or name" }
            }
          },
          "trading_create_strategy" => {
            description: "Create a new trading strategy",
            parameters: {
              name: { type: "string", required: true, description: "Strategy name" },
              strategy_type: { type: "string", required: true, description: "Strategy type (e.g. llm_probability, agent_ensemble)" },
              venue_id: { type: "string", required: true, description: "Venue ID or name" },
              pair: { type: "string", required: true, description: "Trading pair" },
              risk_tier: { type: "string", required: false, description: "Risk tier (default: medium)" },
              parameters: { type: "object", required: false, description: "Strategy parameters" },
              allocated_capital_usd: { type: "number", required: false, description: "Allocated capital in USD" }
            }
          },
          "trading_update_strategy" => {
            description: "Update strategy parameters or configuration",
            parameters: {
              strategy_id: { type: "string", required: true, description: "Strategy ID or name" },
              parameters: { type: "object", required: false, description: "Strategy parameters to merge" },
              config: { type: "object", required: false, description: "Strategy config to merge" },
              name: { type: "string", required: false, description: "New strategy name" }
            }
          },
          "trading_activate_strategy" => {
            description: "Activate a draft or paused strategy",
            parameters: {
              strategy_id: { type: "string", required: true, description: "Strategy ID or name" }
            }
          },
          "trading_pause_strategy" => {
            description: "Pause an active strategy",
            parameters: {
              strategy_id: { type: "string", required: true, description: "Strategy ID or name" }
            }
          },
          "trading_decommission_strategy" => {
            description: "Decommission a strategy (permanent)",
            parameters: {
              strategy_id: { type: "string", required: true, description: "Strategy ID or name" }
            }
          },
          "trading_advance_phase" => {
            description: "Advance strategy lifecycle phase (some phases require approval)",
            parameters: {
              strategy_id: { type: "string", required: true, description: "Strategy ID or name" },
              approved: { type: "boolean", required: false, description: "Approval flag for gates (live_small, live_full)" }
            }
          },
          "trading_strategy_performance" => {
            description: "Calculate strategy performance metrics (PnL, Sharpe, win rate, etc.)",
            parameters: {
              strategy_id: { type: "string", required: true, description: "Strategy ID or name" },
              days: { type: "integer", required: false, description: "Lookback period in days (default: 30)" }
            }
          },
          "trading_strategy_versions" => {
            description: "List strategy parameter versions",
            parameters: {
              strategy_id: { type: "string", required: true, description: "Strategy ID or name" }
            }
          },
          "trading_lifecycle_summary" => {
            description: "Get lifecycle phase distribution summary across all strategies",
            parameters: {}
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
        when "trading_list_strategies" then list_strategies(params)
        when "trading_get_strategy" then get_strategy(params)
        when "trading_create_strategy" then create_strategy(params)
        when "trading_update_strategy" then update_strategy(params)
        when "trading_activate_strategy" then activate_strategy(params)
        when "trading_pause_strategy" then pause_strategy(params)
        when "trading_decommission_strategy" then decommission_strategy(params)
        when "trading_advance_phase" then advance_phase(params)
        when "trading_strategy_performance" then strategy_performance(params)
        when "trading_strategy_versions" then strategy_versions(params)
        when "trading_lifecycle_summary" then lifecycle_summary
        else error_result("Unknown action: #{params[:action]}")
        end
      rescue ActiveRecord::RecordNotFound => e
        error_result(e.message)
      rescue ActiveRecord::RecordInvalid => e
        error_result(e.message)
      end

      private

      def list_strategies(params)
        portfolio = resolve_portfolio
        scope = portfolio.strategies.order(created_at: :desc)
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = scope.where(strategy_type: params[:type]) if params[:type].present?

        success_result({
          strategies: scope.limit(50).map { |s| serialize_strategy(s) },
          count: scope.count
        })
      end

      def get_strategy(params)
        strategy = resolve_strategy(params[:strategy_id])
        success_result(serialize_strategy(strategy, detailed: true))
      end

      def create_strategy(params)
        portfolio = resolve_portfolio
        venue = resolve_venue(params[:venue_id])

        factory = Trading::StrategyFactoryService.new(portfolio)
        strategy = factory.create!(
          name: params[:name],
          strategy_type: params[:strategy_type],
          venue: venue,
          pair: params[:pair],
          risk_tier: params[:risk_tier] || "medium",
          parameters: params[:parameters] || {},
          allocated_capital_usd: params[:allocated_capital_usd] || 0
        )

        success_result(serialize_strategy(strategy, detailed: true))
      end

      def update_strategy(params)
        strategy = resolve_strategy(params[:strategy_id])
        attrs = {}
        attrs[:name] = params[:name] if params[:name].present?

        if params[:parameters].is_a?(Hash)
          attrs[:parameters] = strategy.parameters.merge(params[:parameters])
        end
        if params[:config].is_a?(Hash)
          attrs[:config] = strategy.config.merge(params[:config])
        end

        if attrs.any?
          strategy.update!(attrs)
          strategy.create_version!(reason: "mcp_update", source: "manual") if attrs[:parameters]
        end

        success_result(serialize_strategy(strategy.reload, detailed: true))
      end

      def activate_strategy(params)
        strategy = resolve_strategy(params[:strategy_id])
        strategy.update!(status: "active")
        success_result({ strategy_id: strategy.id, name: strategy.name, status: "active" })
      end

      def pause_strategy(params)
        strategy = resolve_strategy(params[:strategy_id])
        strategy.update!(status: "paused")
        success_result({ strategy_id: strategy.id, name: strategy.name, status: "paused" })
      end

      def decommission_strategy(params)
        strategy = resolve_strategy(params[:strategy_id])
        strategy.update!(status: "decommissioned", lifecycle_phase: "decommissioned")
        success_result({ strategy_id: strategy.id, name: strategy.name, status: "decommissioned" })
      end

      def advance_phase(params)
        strategy = resolve_strategy(params[:strategy_id])
        phases = %w[conception backtest paper_trade live_small live_full matured declining decommissioned]
        current_idx = phases.index(strategy.lifecycle_phase) || 0
        next_phase = phases[current_idx + 1]

        unless next_phase
          return error_result("Strategy is already at terminal phase: #{strategy.lifecycle_phase}")
        end

        if %w[live_small live_full].include?(next_phase) && params[:approved] != true
          return error_result("Phase '#{next_phase}' requires explicit approval (set approved: true)")
        end

        strategy.update!(lifecycle_phase: next_phase)
        success_result({
          strategy_id: strategy.id,
          name: strategy.name,
          previous_phase: phases[current_idx],
          current_phase: next_phase
        })
      end

      def strategy_performance(params)
        strategy = resolve_strategy(params[:strategy_id])
        days = (params[:days] || 30).to_i.clamp(1, 365)

        calculator = Trading::PerformanceCalculatorService.new(strategy)
        metrics = calculator.calculate_all_metrics!(lookback_days: days)

        success_result(metrics)
      end

      def strategy_versions(params)
        strategy = resolve_strategy(params[:strategy_id])
        versions = strategy.versions.order(version_number: :desc).limit(20)

        success_result({
          strategy_id: strategy.id,
          versions: versions.map do |v|
            {
              id: v.id,
              version_number: v.version_number,
              change_reason: v.change_reason,
              source: v.source,
              parameters: v.parameters,
              created_at: v.created_at
            }
          end
        })
      end

      def lifecycle_summary
        portfolio = resolve_portfolio
        strategies = portfolio.strategies

        phases = strategies.group(:lifecycle_phase).count
        statuses = strategies.group(:status).count
        types = strategies.group(:strategy_type).count

        success_result({
          total_strategies: strategies.count,
          by_phase: phases,
          by_status: statuses,
          by_type: types
        })
      end

      def serialize_strategy(strategy, detailed: false)
        data = {
          id: strategy.id,
          name: strategy.name,
          strategy_type: strategy.strategy_type,
          status: strategy.status,
          lifecycle_phase: strategy.lifecycle_phase,
          risk_tier: strategy.risk_tier,
          pair: strategy.pair,
          venue_name: strategy.venue&.name,
          allocated_capital_usd: strategy.allocated_capital_usd.to_f,
          current_pnl_usd: strategy.current_pnl_usd.to_f,
          current_pnl_pct: strategy.current_pnl_pct.to_f,
          tick_interval_seconds: strategy.tick_interval_seconds,
          last_tick_at: strategy.last_tick_at,
          created_at: strategy.created_at
        }

        if detailed
          data[:parameters] = strategy.parameters
          data[:config] = strategy.config
          data[:open_positions] = strategy.positions.where(status: "open").count
          data[:pending_orders] = strategy.orders.where(status: %w[pending submitted]).count
          data[:total_trades] = strategy.trades.count
          data[:total_signals] = strategy.signals.count
          data[:current_version] = strategy.versions.maximum(:version_number)

          closed = strategy.positions.where(status: "closed")
          winning = closed.where("realized_pnl_usd > 0")
          data[:winning_trades] = winning.count
          data[:win_rate] = closed.count > 0 ? (winning.count.to_f / closed.count * 100).round(2) : 0
        end

        data
      end
    end
  end
end
