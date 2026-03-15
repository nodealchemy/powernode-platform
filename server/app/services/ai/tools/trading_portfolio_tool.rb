# frozen_string_literal: true

module Ai
  module Tools
    class TradingPortfolioTool < BaseTool
      include Concerns::TradingContextResolvable

      REQUIRED_PERMISSION = "trading.view"

      def self.definition
        {
          name: "trading_portfolio_management",
          description: "Manage trading portfolios: list, get details, create, update, performance, allocations, wallets, compounding",
          parameters: {
            action: { type: "string", required: true, description: "Action to perform" },
            portfolio_id: { type: "string", required: false, description: "Target portfolio ID (defaults to primary live portfolio)" },
            name: { type: "string", required: false, description: "Portfolio name (for create/update)" },
            portfolio_type: { type: "string", required: false, description: "Portfolio type: training or live (for create)" },
            trading_mode: { type: "string", required: false, description: "Trading mode: simulation, hybrid, or live" },
            status: { type: "string", required: false, description: "Portfolio status: active, paused, or closed" },
            total_capital_usd: { type: "number", required: false, description: "Total capital in USD" },
            config: { type: "object", required: false, description: "Portfolio configuration" },
            days: { type: "integer", required: false, description: "Lookback period in days (for performance)" }
          }
        }
      end

      def self.action_definitions
        {
          "trading_list_portfolios" => {
            description: "List all trading portfolios for the current account",
            parameters: {}
          },
          "trading_get_portfolio" => {
            description: "Get the trading portfolio details for the current account",
            parameters: {
              portfolio_id: { type: "string", required: false, description: "Portfolio ID (defaults to primary live portfolio)" }
            }
          },
          "trading_portfolio_summary" => {
            description: "Get portfolio summary: capital breakdown, PnL, utilization, strategy counts, wallet balances",
            parameters: {
              portfolio_id: { type: "string", required: false, description: "Portfolio ID (defaults to primary live portfolio)" }
            }
          },
          "trading_portfolio_performance" => {
            description: "Get portfolio daily PnL performance over N days",
            parameters: {
              portfolio_id: { type: "string", required: false, description: "Portfolio ID (defaults to primary live portfolio)" },
              days: { type: "integer", required: false, description: "Lookback period in days (default: 30)" }
            }
          },
          "trading_portfolio_allocations" => {
            description: "Get per-strategy capital allocation breakdown",
            parameters: {
              portfolio_id: { type: "string", required: false, description: "Portfolio ID (defaults to primary live portfolio)" }
            }
          },
          "trading_create_portfolio" => {
            description: "Create a trading portfolio for the current account",
            parameters: {
              name: { type: "string", required: true, description: "Portfolio name" },
              total_capital_usd: { type: "number", required: true, description: "Total capital in USD" },
              portfolio_type: { type: "string", required: false, description: "Portfolio type: training or live (default: live)" },
              trading_mode: { type: "string", required: false, description: "Trading mode: simulation, hybrid, or live (default: simulation)" },
              config: { type: "object", required: false, description: "Additional portfolio configuration" }
            }
          },
          "trading_update_portfolio" => {
            description: "Update the trading portfolio name, capital, mode, status, or config",
            parameters: {
              portfolio_id: { type: "string", required: false, description: "Portfolio ID (defaults to primary live portfolio)" },
              name: { type: "string", required: false, description: "New portfolio name" },
              total_capital_usd: { type: "number", required: false, description: "New total capital in USD" },
              trading_mode: { type: "string", required: false, description: "Trading mode: simulation, hybrid, or live" },
              status: { type: "string", required: false, description: "Portfolio status: active, paused, or closed" },
              config: { type: "object", required: false, description: "Portfolio configuration (merged with existing)" }
            }
          },
          "trading_list_wallets" => {
            description: "List wallets with their balances",
            parameters: {
              portfolio_id: { type: "string", required: false, description: "Portfolio ID (defaults to primary live portfolio)" }
            }
          },
          "trading_compounding_summary" => {
            description: "Per-strategy compounding state: earnings pool, total compounded, configuration",
            parameters: {
              portfolio_id: { type: "string", required: false, description: "Portfolio ID (defaults to primary live portfolio)" }
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
        when "trading_list_portfolios" then list_portfolios
        when "trading_get_portfolio" then get_portfolio(params)
        when "trading_portfolio_summary" then portfolio_summary(params)
        when "trading_portfolio_performance" then portfolio_performance(params)
        when "trading_portfolio_allocations" then portfolio_allocations(params)
        when "trading_create_portfolio" then create_portfolio(params)
        when "trading_update_portfolio" then update_portfolio(params)
        when "trading_list_wallets" then list_wallets(params)
        when "trading_compounding_summary" then compounding_summary(params)
        else error_result("Unknown action: #{params[:action]}")
        end
      rescue ActiveRecord::RecordNotFound => e
        error_result(e.message)
      rescue ActiveRecord::RecordInvalid => e
        error_result(e.message)
      end

      private

      def list_portfolios
        portfolios = account.trading_portfolios.order(portfolio_type: :asc, created_at: :asc)

        success_result({
          portfolios: portfolios.map { |p| serialize_portfolio(p) },
          count: portfolios.size
        })
      end

      def get_portfolio(params)
        portfolio = resolve_portfolio(params[:portfolio_id])
        success_result(serialize_portfolio(portfolio))
      end

      def portfolio_summary(params)
        portfolio = resolve_portfolio(params[:portfolio_id])
        portfolio.recalculate_capital!

        strategies = portfolio.strategies
        wallets = portfolio.wallets.includes(:balances)

        success_result({
          portfolio: serialize_portfolio(portfolio),
          capital: {
            total_usd: portfolio.total_capital_usd.to_f,
            allocated_usd: portfolio.allocated_capital_usd.to_f,
            available_usd: portfolio.available_capital_usd.to_f,
            utilization_pct: portfolio.total_capital_usd.to_f > 0 ?
              (portfolio.allocated_capital_usd.to_f / portfolio.total_capital_usd.to_f * 100).round(2) : 0
          },
          pnl: {
            total_pnl_usd: portfolio.total_pnl_usd.to_f,
            total_pnl_pct: portfolio.total_pnl_pct.to_f
          },
          strategies: {
            total: strategies.count,
            active: strategies.where(status: "active").count,
            draft: strategies.where(status: "draft").count,
            paused: strategies.where(status: "paused").count
          },
          wallets: {
            total: wallets.count,
            hot: wallets.where(wallet_type: "hot").count,
            cold: wallets.where(wallet_type: "cold").count
          }
        })
      end

      def portfolio_performance(params)
        portfolio = resolve_portfolio(params[:portfolio_id])
        days = (params[:days] || 30).to_i.clamp(1, 365)

        metrics = Trading::PerformanceMetric
          .joins(:strategy)
          .where(trading_strategies: { trading_portfolio_id: portfolio.id })
          .where(period_type: "daily")
          .where("period_date >= ?", days.days.ago.to_date)
          .order(period_date: :asc)

        daily_pnl = metrics.group(:period_date).sum(:pnl_usd)

        success_result({
          days: days,
          daily_pnl: daily_pnl.transform_values(&:to_f),
          total_pnl_usd: daily_pnl.values.sum.to_f,
          data_points: daily_pnl.size
        })
      end

      def portfolio_allocations(params)
        portfolio = resolve_portfolio(params[:portfolio_id])
        strategies = portfolio.strategies.where.not(status: "decommissioned")

        allocations = strategies.map do |s|
          {
            strategy_id: s.id,
            name: s.name,
            strategy_type: s.strategy_type,
            status: s.status,
            allocated_capital_usd: s.allocated_capital_usd.to_f,
            current_pnl_usd: s.current_pnl_usd.to_f,
            share_pct: portfolio.allocated_capital_usd.to_f > 0 ?
              (s.allocated_capital_usd.to_f / portfolio.allocated_capital_usd.to_f * 100).round(2) : 0
          }
        end

        success_result({
          total_allocated_usd: portfolio.allocated_capital_usd.to_f,
          allocations: allocations
        })
      end

      def create_portfolio(params)
        portfolio_type = params[:portfolio_type] || "live"
        trading_mode = params[:trading_mode] || "simulation"

        unless Trading::Portfolio::PORTFOLIO_TYPES.include?(portfolio_type)
          return error_result("Invalid portfolio_type: #{portfolio_type}. Must be one of: #{Trading::Portfolio::PORTFOLIO_TYPES.join(", ")}")
        end

        unless Trading::Portfolio::TRADING_MODES.include?(trading_mode)
          return error_result("Invalid trading_mode: #{trading_mode}. Must be one of: #{Trading::Portfolio::TRADING_MODES.join(", ")}")
        end

        config = (params[:config] || {}).merge("trading_mode" => trading_mode)

        portfolio = Trading::Portfolio.create!(
          account: account,
          name: params[:name],
          total_capital_usd: params[:total_capital_usd],
          portfolio_type: portfolio_type,
          config: config,
          status: "active"
        )

        success_result(serialize_portfolio(portfolio))
      end

      def update_portfolio(params)
        portfolio = resolve_portfolio(params[:portfolio_id])
        attrs = {}
        config_updates = {}

        attrs[:name] = params[:name] if params[:name].present?
        attrs[:total_capital_usd] = params[:total_capital_usd] if params[:total_capital_usd]

        if params[:status].present?
          unless Trading::Portfolio::STATUSES.include?(params[:status])
            return error_result("Invalid status: #{params[:status]}. Must be one of: #{Trading::Portfolio::STATUSES.join(", ")}")
          end
          attrs[:status] = params[:status]
        end

        if params[:trading_mode].present?
          unless Trading::Portfolio::TRADING_MODES.include?(params[:trading_mode])
            return error_result("Invalid trading_mode: #{params[:trading_mode]}. Must be one of: #{Trading::Portfolio::TRADING_MODES.join(", ")}")
          end
          config_updates["trading_mode"] = params[:trading_mode]
        end

        config_updates.merge!(params[:config]) if params[:config].is_a?(Hash)
        attrs[:config] = portfolio.config.merge(config_updates) if config_updates.any?

        portfolio.update!(attrs) if attrs.any?
        portfolio.recalculate_capital!

        success_result(serialize_portfolio(portfolio.reload))
      end

      def list_wallets(params)
        portfolio = resolve_portfolio(params[:portfolio_id])
        wallets = portfolio.wallets.includes(:balances, :chain).order(wallet_type: :asc)

        success_result({
          wallets: wallets.map { |w| serialize_wallet(w) },
          count: wallets.size
        })
      end

      def compounding_summary(params)
        portfolio = resolve_portfolio(params[:portfolio_id])
        strategies = portfolio.strategies.where.not(status: "decommissioned")

        summary = strategies.map do |s|
          config = s.compounding_config
          {
            strategy_id: s.id,
            name: s.name,
            status: s.status,
            compounding_enabled: s.compounding_enabled?,
            allocated_capital_usd: s.allocated_capital_usd.to_f,
            unreinvested_earnings_usd: s.unreinvested_earnings_usd.to_f,
            total_compounded_usd: s.total_compounded_usd.to_f,
            high_water_mark_usd: s.high_water_mark_usd.to_f,
            last_compounding_at: s.last_compounding_at,
            config: {
              threshold_pct: config["compounding_threshold_pct"],
              reinvest_pct: config["compounding_reinvest_pct"],
              transfer_pct: config["earnings_transfer_pct"],
              retain_pct: config["earnings_retain_pct"]
            }
          }
        end

        success_result({
          strategies: summary,
          totals: {
            total_unreinvested_usd: strategies.sum(:unreinvested_earnings_usd).to_f,
            total_compounded_usd: strategies.sum(:total_compounded_usd).to_f,
            strategies_with_compounding: strategies.count { |s| s.compounding_enabled? }
          }
        })
      end

      def serialize_portfolio(portfolio)
        {
          id: portfolio.id,
          name: portfolio.name,
          status: portfolio.status,
          portfolio_type: portfolio.portfolio_type,
          trading_mode: portfolio.trading_mode,
          total_capital_usd: portfolio.total_capital_usd.to_f,
          allocated_capital_usd: portfolio.allocated_capital_usd.to_f,
          available_capital_usd: portfolio.available_capital_usd.to_f,
          total_pnl_usd: portfolio.total_pnl_usd.to_f,
          total_pnl_pct: portfolio.total_pnl_pct.to_f,
          config: portfolio.config,
          created_at: portfolio.created_at,
          updated_at: portfolio.updated_at
        }
      end

      def serialize_wallet(wallet)
        {
          id: wallet.id,
          wallet_type: wallet.wallet_type,
          label: wallet.label,
          chain: wallet.chain&.name,
          provider: wallet.provider,
          balances: wallet.balances.map do |b|
            {
              token: b.chain_token&.symbol,
              balance: b.balance.to_f,
              available: b.available_balance.to_f
            }
          end
        }
      end
    end
  end
end
