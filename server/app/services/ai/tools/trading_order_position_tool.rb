# frozen_string_literal: true

module Ai
  module Tools
    class TradingOrderPositionTool < BaseTool
      include Concerns::TradingContextResolvable

      REQUIRED_PERMISSION = "trading.view"

      def self.definition
        {
          name: "trading_order_position_management",
          description: "Query and manage trading positions, orders, and trades",
          parameters: {
            action: { type: "string", required: true, description: "Action to perform" },
            position_id: { type: "string", required: false, description: "Position ID" },
            order_id: { type: "string", required: false, description: "Order ID" },
            strategy_id: { type: "string", required: false, description: "Filter by strategy ID or name" },
            status: { type: "string", required: false, description: "Filter by status" },
            days: { type: "integer", required: false, description: "Lookback period in days" },
            limit: { type: "integer", required: false, description: "Max results to return" }
          }
        }
      end

      def self.action_definitions
        {
          "trading_list_positions" => {
            description: "List positions with optional status and strategy filters",
            parameters: {
              status: { type: "string", required: false, description: "Filter by status: open, closed, liquidated" },
              strategy_id: { type: "string", required: false, description: "Filter by strategy ID or name" }
            }
          },
          "trading_get_position" => {
            description: "Get detailed position information",
            parameters: {
              position_id: { type: "string", required: true, description: "Position ID" }
            }
          },
          "trading_open_positions" => {
            description: "Get summary of all open positions with unrealized PnL",
            parameters: {}
          },
          "trading_closed_positions" => {
            description: "Get recently closed positions with realized PnL",
            parameters: {
              days: { type: "integer", required: false, description: "Lookback period in days (default: 7)" }
            }
          },
          "trading_close_position" => {
            description: "Close an open position at current market price",
            parameters: {
              position_id: { type: "string", required: true, description: "Position ID" }
            }
          },
          "trading_list_orders" => {
            description: "List orders with optional status and strategy filters",
            parameters: {
              status: { type: "string", required: false, description: "Filter by status: pending, submitted, filled, cancelled" },
              strategy_id: { type: "string", required: false, description: "Filter by strategy ID or name" }
            }
          },
          "trading_cancel_order" => {
            description: "Cancel a pending order",
            parameters: {
              order_id: { type: "string", required: true, description: "Order ID" }
            }
          },
          "trading_list_trades" => {
            description: "List executed trades with optional strategy filter",
            parameters: {
              strategy_id: { type: "string", required: false, description: "Filter by strategy ID or name" },
              limit: { type: "integer", required: false, description: "Max results (default: 50)" }
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
        when "trading_list_positions" then list_positions(params)
        when "trading_get_position" then get_position(params)
        when "trading_open_positions" then open_positions
        when "trading_closed_positions" then closed_positions(params)
        when "trading_close_position" then close_position(params)
        when "trading_list_orders" then list_orders(params)
        when "trading_cancel_order" then cancel_order(params)
        when "trading_list_trades" then list_trades(params)
        else error_result("Unknown action: #{params[:action]}")
        end
      rescue ActiveRecord::RecordNotFound => e
        error_result(e.message)
      end

      private

      def list_positions(params)
        scope = portfolio_positions
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = filter_by_strategy(scope, params[:strategy_id])

        success_result({
          positions: scope.order(opened_at: :desc).limit(50).map { |p| serialize_position(p) },
          count: scope.count
        })
      end

      def get_position(params)
        position = resolve_position(params[:position_id])
        success_result(serialize_position(position, detailed: true))
      end

      def open_positions
        positions = portfolio_positions.where(status: "open").order(opened_at: :desc)

        total_unrealized = positions.sum(:unrealized_pnl_usd).to_f

        success_result({
          positions: positions.map { |p| serialize_position(p) },
          count: positions.size,
          total_unrealized_pnl_usd: total_unrealized
        })
      end

      def closed_positions(params)
        days = (params[:days] || 7).to_i.clamp(1, 365)
        positions = portfolio_positions
          .where(status: "closed")
          .where("closed_at >= ?", days.days.ago)
          .order(closed_at: :desc)

        total_realized = positions.sum(:realized_pnl_usd).to_f

        success_result({
          positions: positions.limit(50).map { |p| serialize_position(p) },
          count: positions.count,
          days: days,
          total_realized_pnl_usd: total_realized
        })
      end

      def close_position(params)
        position = resolve_position(params[:position_id])

        unless position.status == "open"
          return error_result("Position is not open (status: #{position.status})")
        end

        position.close!(exit_price: position.current_price || position.entry_price)

        success_result({
          position_id: position.id,
          status: "closed",
          realized_pnl_usd: position.realized_pnl_usd.to_f,
          close_reason: "manual_close"
        })
      end

      def list_orders(params)
        scope = portfolio_orders
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = filter_by_strategy(scope, params[:strategy_id])

        success_result({
          orders: scope.order(created_at: :desc).limit(50).map { |o| serialize_order(o) },
          count: scope.count
        })
      end

      def cancel_order(params)
        order = resolve_order(params[:order_id])

        unless %w[pending submitted].include?(order.status)
          return error_result("Order cannot be cancelled (status: #{order.status})")
        end

        order.cancel!(reason: "cancelled_via_mcp")

        success_result({
          order_id: order.id,
          status: "cancelled",
          cancel_reason: "cancelled_via_mcp"
        })
      end

      def list_trades(params)
        portfolio = resolve_portfolio
        scope = Trading::Trade.joins(order: :strategy)
          .where(trading_strategies: { trading_portfolio_id: portfolio.id })

        if params[:strategy_id].present?
          strategy = resolve_strategy(params[:strategy_id])
          scope = scope.where(trading_orders: { trading_strategy_id: strategy.id })
        end

        limit = (params[:limit] || 50).to_i.clamp(1, 200)

        success_result({
          trades: scope.order(executed_at: :desc).limit(limit).map { |t| serialize_trade(t) },
          count: scope.count
        })
      end

      # Helpers

      def portfolio_positions
        portfolio = resolve_portfolio
        Trading::Position.joins(:strategy)
          .where(trading_strategies: { trading_portfolio_id: portfolio.id })
      end

      def portfolio_orders
        portfolio = resolve_portfolio
        Trading::Order.joins(:strategy)
          .where(trading_strategies: { trading_portfolio_id: portfolio.id })
      end

      def filter_by_strategy(scope, strategy_id)
        return scope unless strategy_id.present?

        strategy = resolve_strategy(strategy_id)
        scope.where(trading_strategy_id: strategy.id)
      end

      def serialize_position(position, detailed: false)
        pnl_usd = position.status == "closed" ? position.realized_pnl_usd : position.unrealized_pnl_usd
        entry_value = position.entry_price.to_f * position.quantity.to_f.abs
        pnl_pct = entry_value > 0 ? (pnl_usd.to_f / entry_value * 100).round(2) : 0

        data = {
          id: position.id,
          pair: position.pair,
          side: position.side,
          status: position.status,
          entry_price: position.entry_price.to_f,
          exit_price: position.exit_price&.to_f,
          quantity: position.quantity.to_f,
          current_price: position.current_price&.to_f,
          unrealized_pnl_usd: position.unrealized_pnl_usd.to_f,
          realized_pnl_usd: position.realized_pnl_usd.to_f,
          pnl_usd: pnl_usd.to_f,
          pnl_pct: pnl_pct,
          strategy_name: position.strategy&.name,
          opened_at: position.opened_at,
          closed_at: position.closed_at
        }

        if detailed
          data[:stop_loss_price] = position.stop_loss_price&.to_f
          data[:take_profit_price] = position.take_profit_price&.to_f
          data[:fees_usd] = position.fees_usd.to_f
          data[:close_reason] = position.close_reason
          data[:trades_count] = position.trades.count
        end

        data
      end

      def serialize_order(order)
        {
          id: order.id,
          pair: order.pair,
          side: order.side,
          order_type: order.order_type,
          status: order.status,
          quantity: order.quantity.to_f,
          price: order.price&.to_f,
          average_fill_price: order.average_fill_price&.to_f,
          filled_quantity: order.filled_quantity.to_f,
          fees_usd: order.fees_usd.to_f,
          venue_order_id: order.venue_order_id,
          strategy_name: order.strategy&.name,
          submitted_at: order.submitted_at,
          filled_at: order.filled_at,
          created_at: order.created_at
        }
      end

      def serialize_trade(trade)
        {
          id: trade.id,
          pair: trade.pair,
          side: trade.side,
          quantity: trade.quantity.to_f,
          price: trade.price.to_f,
          fee_usd: trade.fee_usd.to_f,
          total_usd: trade.total_usd.to_f,
          venue_trade_id: trade.venue_trade_id,
          executed_at: trade.executed_at
        }
      end
    end
  end
end
