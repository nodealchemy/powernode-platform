# frozen_string_literal: true

module Ai
  module Tools
    class TradingMarketplaceTool < BaseTool
      include Concerns::TradingContextResolvable

      REQUIRED_PERMISSION = "trading.view"

      def self.definition
        {
          name: "trading_marketplace",
          description: "Strategy marketplace: publish strategies, subscribe to signals, manage follows, view forwarded signals and performance fees",
          parameters: {
            action: { type: "string", required: true, description: "Action to perform" },
            published_strategy_id: { type: "string", required: false, description: "Published strategy ID" },
            subscription_id: { type: "string", required: false, description: "Subscription ID" },
            strategy_id: { type: "string", required: false, description: "Strategy ID (for publishing)" },
            publisher_account_id: { type: "string", required: false, description: "Publisher account ID (for following)" },
            follow_id: { type: "string", required: false, description: "Publisher follow ID" },
            name: { type: "string", required: false, description: "Published strategy name" },
            description: { type: "string", required: false, description: "Published strategy description" },
            performance_fee_pct: { type: "number", required: false, description: "Performance fee percentage (0-50)" },
            allocated_capital_usd: { type: "number", required: false, description: "Capital to allocate for subscription" },
            default_capital_usd: { type: "number", required: false, description: "Default capital for auto-subscriptions" },
            auto_subscribe: { type: "boolean", required: false, description: "Auto-subscribe to new strategies from publisher" },
            config: { type: "object", required: false, description: "Additional configuration" }
          }
        }
      end

      def self.action_definitions
        {
          "trading_list_published_strategies" => {
            description: "Browse the strategy marketplace catalog with performance metrics",
            parameters: {
              strategy_type: { type: "string", required: false, description: "Filter by strategy type" },
              pair: { type: "string", required: false, description: "Filter by trading pair" }
            }
          },
          "trading_get_published_strategy" => {
            description: "Get published strategy details including performance snapshot and lifecycle data",
            parameters: {
              published_strategy_id: { type: "string", required: true, description: "Published strategy ID" }
            }
          },
          "trading_publish_strategy" => {
            description: "Publish a live strategy for subscription by other accounts (requires trading.publish)",
            parameters: {
              strategy_id: { type: "string", required: true, description: "Strategy ID to publish" },
              name: { type: "string", required: false, description: "Display name (defaults to strategy name)" },
              description: { type: "string", required: false, description: "Description for marketplace" },
              performance_fee_pct: { type: "number", required: false, description: "Performance fee % (0-50, default 0)" }
            }
          },
          "trading_unpublish_strategy" => {
            description: "Unpublish a strategy, stopping future signal forwarding",
            parameters: {
              published_strategy_id: { type: "string", required: true, description: "Published strategy ID" }
            }
          },
          "trading_list_subscriptions" => {
            description: "List current account's active strategy subscriptions",
            parameters: {}
          },
          "trading_subscribe" => {
            description: "Subscribe to a published strategy with capital allocation",
            parameters: {
              published_strategy_id: { type: "string", required: true, description: "Published strategy ID" },
              allocated_capital_usd: { type: "number", required: true, description: "Capital to allocate" },
              config: { type: "object", required: false, description: "risk_scaling_factor, max_position_pct" }
            }
          },
          "trading_unsubscribe" => {
            description: "Unsubscribe from a published strategy (pauses follower, keeps open positions)",
            parameters: {
              subscription_id: { type: "string", required: true, description: "Subscription ID" }
            }
          },
          "trading_pause_subscription" => {
            description: "Pause signal forwarding for a subscription",
            parameters: {
              subscription_id: { type: "string", required: true, description: "Subscription ID" }
            }
          },
          "trading_resume_subscription" => {
            description: "Resume signal forwarding for a subscription",
            parameters: {
              subscription_id: { type: "string", required: true, description: "Subscription ID" }
            }
          },
          "trading_list_forwarded_signals" => {
            description: "View forwarded signal audit trail for a subscription",
            parameters: {
              subscription_id: { type: "string", required: true, description: "Subscription ID" }
            }
          },
          "trading_subscription_performance" => {
            description: "Performance comparison between publisher and subscriber PnL",
            parameters: {
              subscription_id: { type: "string", required: true, description: "Subscription ID" }
            }
          },
          "trading_follow_publisher" => {
            description: "Follow a publisher account to auto-subscribe to all their strategies",
            parameters: {
              publisher_account_id: { type: "string", required: true, description: "Publisher account ID" },
              default_capital_usd: { type: "number", required: false, description: "Default capital per auto-subscription" },
              auto_subscribe: { type: "boolean", required: false, description: "Auto-subscribe to new strategies (default true)" }
            }
          },
          "trading_unfollow_publisher" => {
            description: "Unfollow a publisher account",
            parameters: {
              follow_id: { type: "string", required: true, description: "Publisher follow ID" }
            }
          },
          "trading_list_publisher_follows" => {
            description: "List account-level publisher follows",
            parameters: {}
          },
          "trading_list_performance_fees" => {
            description: "List performance fee events for a subscription",
            parameters: {
              subscription_id: { type: "string", required: true, description: "Subscription ID" }
            }
          },
          "trading_fee_summary" => {
            description: "Aggregate fees paid/received across all subscriptions",
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
        when "trading_list_published_strategies" then list_published(params)
        when "trading_get_published_strategy" then get_published(params)
        when "trading_publish_strategy" then publish_strategy(params)
        when "trading_unpublish_strategy" then unpublish_strategy(params)
        when "trading_list_subscriptions" then list_subscriptions
        when "trading_subscribe" then subscribe(params)
        when "trading_unsubscribe" then unsubscribe(params)
        when "trading_pause_subscription" then pause_subscription(params)
        when "trading_resume_subscription" then resume_subscription(params)
        when "trading_list_forwarded_signals" then list_forwarded_signals(params)
        when "trading_subscription_performance" then subscription_performance(params)
        when "trading_follow_publisher" then follow_publisher(params)
        when "trading_unfollow_publisher" then unfollow_publisher(params)
        when "trading_list_publisher_follows" then list_follows
        when "trading_list_performance_fees" then list_fees(params)
        when "trading_fee_summary" then fee_summary
        else error_result("Unknown action: #{params[:action]}")
        end
      rescue ActiveRecord::RecordNotFound => e
        error_result(e.message)
      rescue RuntimeError => e
        error_result(e.message)
      end

      private

      def list_published(params)
        scope = Trading::PublishedStrategy.active
        scope = scope.where(strategy_type: params[:strategy_type]) if params[:strategy_type].present?
        scope = scope.where(pair: params[:pair]) if params[:pair].present?

        success_result({
          published_strategies: scope.order(subscriber_count: :desc).map { |ps| serialize_published(ps) },
          count: scope.count
        })
      end

      def get_published(params)
        ps = Trading::PublishedStrategy.find(params[:published_strategy_id])
        strategy = ps.strategy

        success_result({
          published_strategy: serialize_published(ps),
          strategy_details: {
            lifecycle_phase: strategy.lifecycle_phase,
            status: strategy.status,
            allocated_capital_usd: strategy.allocated_capital_usd.to_f,
            current_pnl_usd: strategy.current_pnl_usd.to_f,
            parameters: strategy.parameters,
            open_positions: strategy.positions.where(status: "open").count,
            closed_positions: strategy.positions.where(status: "closed").count
          }
        })
      end

      def publish_strategy(params)
        strategy = account.trading_strategies.find(params[:strategy_id])
        published = Trading::StrategyPublishingService.publish!(
          strategy,
          name: params[:name] || strategy.name,
          description: params[:description],
          performance_fee_pct: (params[:performance_fee_pct] || 0).to_f
        )
        success_result({ message: "Published '#{published.name}'", published_strategy: serialize_published(published) })
      end

      def unpublish_strategy(params)
        ps = Trading::PublishedStrategy.find(params[:published_strategy_id])
        Trading::StrategyPublishingService.unpublish!(ps)
        success_result({ message: "Unpublished '#{ps.name}'" })
      end

      def list_subscriptions
        subs = account.trading_subscriptions.includes(:published_strategy, :follower_strategy)
        success_result({
          subscriptions: subs.map { |s| serialize_subscription(s) },
          count: subs.count
        })
      end

      def subscribe(params)
        ps = Trading::PublishedStrategy.active.find(params[:published_strategy_id])
        sub = Trading::SubscriptionService.subscribe!(
          account, ps,
          capital_usd: params[:allocated_capital_usd].to_f,
          config: params[:config] || {}
        )
        success_result({ message: "Subscribed to '#{ps.name}'", subscription: serialize_subscription(sub) })
      end

      def unsubscribe(params)
        sub = account.trading_subscriptions.find(params[:subscription_id])
        Trading::SubscriptionService.unsubscribe!(sub)
        success_result({ message: "Unsubscribed from '#{sub.published_strategy.name}'" })
      end

      def pause_subscription(params)
        sub = account.trading_subscriptions.find(params[:subscription_id])
        Trading::SubscriptionService.pause!(sub)
        success_result({ message: "Paused subscription" })
      end

      def resume_subscription(params)
        sub = account.trading_subscriptions.find(params[:subscription_id])
        Trading::SubscriptionService.resume!(sub)
        success_result({ message: "Resumed subscription" })
      end

      def list_forwarded_signals(params)
        sub = account.trading_subscriptions.find(params[:subscription_id])
        signals = sub.forwarded_signals.order(created_at: :desc).limit(50)
        success_result({
          forwarded_signals: signals.map { |fs|
            { id: fs.id, status: fs.status, signal_type: fs.signal_type, direction: fs.direction,
              pair: fs.pair, source_price: fs.source_price&.to_f, execution_price: fs.execution_price&.to_f,
              scaled_quantity: fs.scaled_quantity&.to_f, skip_reason: fs.skip_reason,
              latency_ms: fs.latency_ms, forwarded_at: fs.forwarded_at }
          },
          count: signals.count
        })
      end

      def subscription_performance(params)
        sub = account.trading_subscriptions.find(params[:subscription_id])
        ps = sub.published_strategy
        follower = sub.follower_strategy

        success_result({
          publisher: {
            strategy_name: ps.name,
            performance: ps.performance_snapshot,
            current_pnl_usd: ps.strategy.current_pnl_usd.to_f
          },
          subscriber: {
            follower_strategy_id: follower&.id,
            current_pnl_usd: follower&.current_pnl_usd.to_f,
            allocated_capital_usd: sub.allocated_capital_usd.to_f,
            total_fees_paid_usd: sub.total_fees_paid_usd.to_f,
            signals_received: sub.total_signals_received,
            signals_executed: sub.total_signals_executed,
            execution_rate: sub.signal_execution_rate
          }
        })
      end

      def follow_publisher(params)
        publisher = Account.find(params[:publisher_account_id])
        follow = Trading::PublisherFollow.create!(
          account: account,
          publisher_account: publisher,
          status: "active",
          auto_subscribe: params.fetch(:auto_subscribe, true),
          default_capital_usd: (params[:default_capital_usd] || 0).to_f
        )
        success_result({ message: "Following #{publisher.name}", follow_id: follow.id })
      end

      def unfollow_publisher(params)
        follow = account.trading_publisher_follows.find(params[:follow_id])
        follow.update!(status: "unfollowed", unfollowed_at: Time.current)
        success_result({ message: "Unfollowed" })
      end

      def list_follows
        follows = account.trading_publisher_follows.includes(:publisher_account)
        success_result({
          follows: follows.map { |f|
            { id: f.id, publisher_account_id: f.publisher_account_id, publisher_name: f.publisher_account.name,
              status: f.status, auto_subscribe: f.auto_subscribe, default_capital_usd: f.default_capital_usd.to_f,
              subscription_count: f.subscriptions.count }
          },
          count: follows.count
        })
      end

      def list_fees(params)
        sub = account.trading_subscriptions.find(params[:subscription_id])
        fees = sub.performance_fee_events.order(created_at: :desc).limit(50)
        success_result({
          fees: fees.map { |f|
            { id: f.id, realized_pnl_usd: f.realized_pnl_usd.to_f, fee_pct: f.fee_pct.to_f,
              fee_usd: f.fee_usd.to_f, status: f.status, created_at: f.created_at }
          },
          total_fees_paid: sub.total_fees_paid_usd.to_f
        })
      end

      def fee_summary
        subs = account.trading_subscriptions
        total_paid = subs.sum(:total_fees_paid_usd).to_f

        # Fees received as publisher
        published = account.trading_published_strategies
        total_received = Trading::PerformanceFeeEvent
          .joins(subscription: :published_strategy)
          .where(trading_published_strategies: { account_id: account.id })
          .where(status: "transferred")
          .sum(:fee_usd).to_f

        success_result({
          total_fees_paid_usd: total_paid,
          total_fees_received_usd: total_received,
          active_subscriptions: subs.active.count,
          published_strategies: published.active.count,
          total_subscribers: published.sum(:subscriber_count)
        })
      end

      def serialize_published(ps)
        {
          id: ps.id, name: ps.name, status: ps.status,
          strategy_type: ps.strategy_type, pair: ps.pair, venue_slug: ps.venue_slug,
          performance_fee_pct: ps.performance_fee_pct.to_f,
          subscriber_count: ps.subscriber_count,
          performance_snapshot: ps.performance_snapshot,
          published_at: ps.published_at
        }
      end

      def serialize_subscription(sub)
        {
          id: sub.id, status: sub.status,
          published_strategy_name: sub.published_strategy.name,
          strategy_type: sub.published_strategy.strategy_type,
          pair: sub.published_strategy.pair,
          allocated_capital_usd: sub.allocated_capital_usd.to_f,
          total_pnl_usd: sub.total_pnl_usd.to_f,
          total_fees_paid_usd: sub.total_fees_paid_usd.to_f,
          signals_received: sub.total_signals_received,
          signals_executed: sub.total_signals_executed,
          execution_rate: sub.signal_execution_rate
        }
      end
    end
  end
end
