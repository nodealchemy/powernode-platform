# frozen_string_literal: true

module Ai
  module Tools
    class TradingRiskTool < BaseTool
      include Concerns::TradingContextResolvable

      REQUIRED_PERMISSION = "trading.view"

      def self.definition
        {
          name: "trading_risk_management",
          description: "Query and manage trading risk: risk profile, circuit breaker, sweep rules, sweep proposals",
          parameters: {
            action: { type: "string", required: true, description: "Action to perform" },
            max_drawdown_pct: { type: "number", required: false, description: "Max portfolio drawdown percentage" },
            max_position_size_usd: { type: "number", required: false, description: "Max position size in USD" },
            max_daily_loss_usd: { type: "number", required: false, description: "Max daily loss in USD" },
            status: { type: "string", required: false, description: "Filter by status" },
            limit: { type: "integer", required: false, description: "Max results to return" }
          }
        }
      end

      def self.action_definitions
        {
          "trading_get_risk_profile" => {
            description: "Get the risk profile including circuit breaker status and risk parameters",
            parameters: {}
          },
          "trading_update_risk_profile" => {
            description: "Update risk parameters (drawdown limits, position size limits, daily loss limits)",
            parameters: {
              max_drawdown_pct: { type: "number", required: false, description: "Max portfolio drawdown percentage" },
              max_position_size_usd: { type: "number", required: false, description: "Max position size in USD" },
              max_daily_loss_usd: { type: "number", required: false, description: "Max daily loss in USD" }
            }
          },
          "trading_risk_events" => {
            description: "List risk events and circuit breaker trips",
            parameters: {
              limit: { type: "integer", required: false, description: "Max results (default: 20)" }
            }
          },
          "trading_reset_circuit_breaker" => {
            description: "Reset a tripped circuit breaker to resume trading",
            parameters: {}
          },
          "trading_list_sweep_rules" => {
            description: "List wallet sweep rules for automated fund movement",
            parameters: {}
          },
          "trading_list_sweep_proposals" => {
            description: "List pending or recent sweep proposals",
            parameters: {
              status: { type: "string", required: false, description: "Filter by status: pending, approved, rejected, executed" }
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
        when "trading_get_risk_profile" then get_risk_profile
        when "trading_update_risk_profile" then update_risk_profile(params)
        when "trading_risk_events" then risk_events(params)
        when "trading_reset_circuit_breaker" then reset_circuit_breaker
        when "trading_list_sweep_rules" then list_sweep_rules
        when "trading_list_sweep_proposals" then list_sweep_proposals(params)
        else error_result("Unknown action: #{params[:action]}")
        end
      rescue ActiveRecord::RecordNotFound => e
        error_result(e.message)
      end

      private

      def get_risk_profile
        profile = account.trading_risk_profile
        unless profile
          return error_result("No risk profile configured")
        end

        success_result({
          id: profile.id,
          risk_tier: profile.risk_tier,
          max_portfolio_drawdown_pct: profile.max_portfolio_drawdown_pct.to_f,
          max_strategy_drawdown_pct: profile.max_strategy_drawdown_pct.to_f,
          max_position_size_pct: profile.max_position_size_pct.to_f,
          max_daily_loss_usd: profile.max_daily_loss_usd.to_f,
          max_open_positions: profile.max_open_positions,
          max_strategies: profile.max_strategies,
          circuit_breaker: {
            enabled: profile.circuit_breaker_enabled,
            active: profile.circuit_breaker_active?,
            tripped_at: profile.circuit_breaker_tripped_at
          },
          active_risk_events: profile.risk_events.where(status: "active").count
        })
      end

      def update_risk_profile(params)
        profile = account.trading_risk_profile
        unless profile
          return error_result("No risk profile configured")
        end

        attrs = {}
        attrs[:max_portfolio_drawdown_pct] = params[:max_drawdown_pct] if params[:max_drawdown_pct]
        attrs[:max_position_size_pct] = params[:max_position_size_usd] if params[:max_position_size_usd]
        attrs[:max_daily_loss_usd] = params[:max_daily_loss_usd] if params[:max_daily_loss_usd]

        if attrs.empty?
          return error_result("No risk parameters provided to update")
        end

        profile.update!(attrs)
        success_result({
          message: "Risk profile updated",
          updated_fields: attrs.keys.map(&:to_s)
        })
      end

      def risk_events(params)
        profile = account.trading_risk_profile
        unless profile
          return error_result("No risk profile configured")
        end

        limit = (params[:limit] || 20).to_i.clamp(1, 100)
        events = profile.risk_events.order(created_at: :desc).limit(limit)

        success_result({
          events: events.map do |e|
            {
              id: e.id,
              event_type: e.event_type,
              severity: e.severity,
              status: e.status,
              description: e.description,
              trigger_value: e.trigger_value&.to_f,
              threshold_value: e.threshold_value&.to_f,
              strategy_id: e.respond_to?(:trading_strategy_id) ? e.trading_strategy_id : nil,
              created_at: e.created_at,
              resolved_at: e.resolved_at
            }
          end,
          count: events.size,
          active_count: profile.risk_events.where(status: "active").count
        })
      end

      def reset_circuit_breaker
        profile = account.trading_risk_profile
        unless profile
          return error_result("No risk profile configured")
        end

        unless profile.circuit_breaker_active?
          return error_result("Circuit breaker is not currently tripped")
        end

        profile.reset_circuit_breaker!

        success_result({
          message: "Circuit breaker reset successfully",
          circuit_breaker_active: false
        })
      end

      def list_sweep_rules
        portfolio = resolve_portfolio
        rules = Trading::SweepRule.joins(:wallet)
          .where(trading_wallets: { trading_portfolio_id: portfolio.id })
          .includes(:wallet, :cold_wallet, :chain_token)
          .order(created_at: :desc)

        success_result({
          rules: rules.map do |r|
            {
              id: r.id,
              wallet: r.wallet&.label,
              cold_wallet: r.cold_wallet&.label,
              token: r.chain_token&.symbol,
              threshold_amount: r.threshold_amount.to_f,
              sweep_amount: r.sweep_amount.to_f,
              min_retain_amount: r.min_retain_amount.to_f,
              is_active: r.is_active,
              auto_execute: r.auto_execute
            }
          end,
          count: rules.size
        })
      end

      def list_sweep_proposals(params)
        portfolio = resolve_portfolio
        scope = portfolio.sweep_proposals.includes(:wallet, :cold_wallet).order(created_at: :desc)
        scope = scope.where(status: params[:status]) if params[:status].present?

        success_result({
          proposals: scope.limit(20).map do |p|
            {
              id: p.id,
              amount_usd: p.amount_usd.to_f,
              status: p.status,
              reasoning: p.reasoning,
              confidence: p.confidence&.to_f,
              wallet: p.wallet&.label,
              cold_wallet: p.cold_wallet&.label,
              created_at: p.created_at,
              decided_at: p.decided_at
            }
          end,
          count: scope.count
        })
      end
    end
  end
end
