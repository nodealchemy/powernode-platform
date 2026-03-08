# frozen_string_literal: true

module Ai
  module Tools
    class TradingPortfolioTool < BaseTool
      include Concerns::TradingContextResolvable

      REQUIRED_PERMISSION = "trading.view"

      def self.definition
        {
          name: "trading_portfolio_management",
          description: "Manage trading portfolio: get details, summary, performance, allocations, wallets",
          parameters: {
            action: { type: "string", required: true, description: "Action to perform" },
            name: { type: "string", required: false, description: "Portfolio name (for create/update)" },
            total_capital_usd: { type: "number", required: false, description: "Total capital in USD" },
            config: { type: "object", required: false, description: "Portfolio configuration" },
            days: { type: "integer", required: false, description: "Lookback period in days (for performance)" }
          }
        }
      end

      def self.action_definitions
        {
          "trading_get_portfolio" => {
            description: "Get the trading portfolio details for the current account",
            parameters: {}
          },
          "trading_portfolio_summary" => {
            description: "Get portfolio summary: capital breakdown, PnL, utilization, strategy counts, wallet balances",
            parameters: {}
          },
          "trading_portfolio_performance" => {
            description: "Get portfolio daily PnL performance over N days",
            parameters: {
              days: { type: "integer", required: false, description: "Lookback period in days (default: 30)" }
            }
          },
          "trading_portfolio_allocations" => {
            description: "Get per-strategy capital allocation breakdown",
            parameters: {}
          },
          "trading_create_portfolio" => {
            description: "Create a trading portfolio for the current account",
            parameters: {
              name: { type: "string", required: true, description: "Portfolio name" },
              total_capital_usd: { type: "number", required: true, description: "Total capital in USD" }
            }
          },
          "trading_update_portfolio" => {
            description: "Update the trading portfolio name, capital, or config",
            parameters: {
              name: { type: "string", required: false, description: "New portfolio name" },
              total_capital_usd: { type: "number", required: false, description: "New total capital in USD" },
              config: { type: "object", required: false, description: "Portfolio configuration" }
            }
          },
          "trading_list_wallets" => {
            description: "List wallets with their balances",
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
        when "trading_get_portfolio" then get_portfolio
        when "trading_portfolio_summary" then portfolio_summary
        when "trading_portfolio_performance" then portfolio_performance(params)
        when "trading_portfolio_allocations" then portfolio_allocations
        when "trading_create_portfolio" then create_portfolio(params)
        when "trading_update_portfolio" then update_portfolio(params)
        when "trading_list_wallets" then list_wallets
        else error_result("Unknown action: #{params[:action]}")
        end
      rescue ActiveRecord::RecordNotFound => e
        error_result(e.message)
      rescue ActiveRecord::RecordInvalid => e
        error_result(e.message)
      end

      private

      def get_portfolio
        portfolio = resolve_portfolio
        success_result(serialize_portfolio(portfolio))
      end

      def portfolio_summary
        portfolio = resolve_portfolio
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
        portfolio = resolve_portfolio
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

      def portfolio_allocations
        portfolio = resolve_portfolio
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
        if account.trading_portfolio
          return error_result("Account already has a trading portfolio")
        end

        portfolio = Trading::Portfolio.create!(
          account: account,
          name: params[:name],
          total_capital_usd: params[:total_capital_usd],
          status: "active"
        )

        success_result(serialize_portfolio(portfolio))
      end

      def update_portfolio(params)
        portfolio = resolve_portfolio
        attrs = {}
        attrs[:name] = params[:name] if params[:name].present?
        attrs[:total_capital_usd] = params[:total_capital_usd] if params[:total_capital_usd]
        attrs[:config] = portfolio.config.merge(params[:config]) if params[:config].is_a?(Hash)

        portfolio.update!(attrs) if attrs.any?
        portfolio.recalculate_capital!

        success_result(serialize_portfolio(portfolio.reload))
      end

      def list_wallets
        portfolio = resolve_portfolio
        wallets = portfolio.wallets.includes(:balances, :chain).order(wallet_type: :asc)

        success_result({
          wallets: wallets.map { |w| serialize_wallet(w) },
          count: wallets.size
        })
      end

      def serialize_portfolio(portfolio)
        {
          id: portfolio.id,
          name: portfolio.name,
          status: portfolio.status,
          total_capital_usd: portfolio.total_capital_usd.to_f,
          allocated_capital_usd: portfolio.allocated_capital_usd.to_f,
          available_capital_usd: portfolio.available_capital_usd.to_f,
          total_pnl_usd: portfolio.total_pnl_usd.to_f,
          total_pnl_pct: portfolio.total_pnl_pct.to_f,
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
