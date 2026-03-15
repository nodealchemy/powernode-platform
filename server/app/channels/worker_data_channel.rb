# frozen_string_literal: true

# WebSocket channel for high-frequency training data operations.
# Handles the same actions as the internal trading controller's hot-path
# endpoints, eliminating HTTP overhead for per-tick calls.
#
# Protocol:
#   1. Worker connects with a worker JWT token
#   2. Worker subscribes to this channel
#   3. Worker sends action messages with request_id for correlation
#   4. Channel transmits responses with matching request_id
#
# Actions:
#   - batch_strategy_contexts: Fetch evaluation contexts for multiple strategies
#   - batch_fetch_tickers: Batch fetch prices from a venue
#   - batch_record_results: Submit evaluation results for multiple strategies
#   - training_tick_complete: Record tick progress
#   - training_status: Check session status (+ heartbeat)
#   - ping: Connection health check
class WorkerDataChannel < ApplicationCable::Channel
  def subscribed
    unless connection.current_worker&.active?
      Rails.logger.warn "[WorkerData] Rejected: no active worker on connection"
      reject
      return
    end

    stream_from "worker_data:#{connection.current_worker.id}"
    Rails.logger.info "[WorkerData] Worker #{connection.current_worker.name} subscribed"
  end

  def unsubscribed
    Rails.logger.info "[WorkerData] Worker #{connection.current_worker&.name} unsubscribed"
  end

  # Fetch evaluation contexts for multiple strategies in one call.
  # data: { request_id:, strategy_ids: [] }
  def batch_strategy_contexts(data)
    strategy_ids = data["strategy_ids"] || []
    if strategy_ids.empty?
      return transmit_error(data["request_id"], "strategy_ids required")
    end

    strategies = ::Trading::Strategy.includes(:venue, :portfolio, :agent_team)
                                     .where(id: strategy_ids)
    contexts = {}

    strategies.each do |strategy|
      contexts[strategy.id] = ::Trading::StrategyContextBuilder.build(strategy)
    rescue StandardError => e
      Rails.logger.warn("[WorkerData] batch context failed for #{strategy.id}: #{e.message}")
      contexts[strategy.id] = { "error" => e.message, "skipped" => true }
    end

    transmit_success(data["request_id"], { contexts: contexts })
  rescue StandardError => e
    Rails.logger.error "[WorkerData] batch_strategy_contexts error: #{e.message}"
    transmit_error(data["request_id"], e.message)
  end

  # Batch fetch ticker prices from a venue.
  # data: { request_id:, venue_id:, pairs: [] }
  def batch_fetch_tickers(data)
    venue = ::Trading::Venue.find(data["venue_id"])
    pairs = Array(data["pairs"]).uniq.first(100)

    if pairs.empty?
      return transmit_error(data["request_id"], "pairs required")
    end

    adapter = venue.adapter_class.constantize.new(venue)

    raw = if adapter.respond_to?(:batch_fetch_tickers)
            adapter.batch_fetch_tickers(pairs)
          else
            pairs.each_with_object({}) do |pair, result|
              result[pair] = adapter.fetch_ticker(pair)
            rescue StandardError
              result[pair] = nil
            end
          end

    tickers = raw.transform_values do |ticker|
      next nil if ticker.nil?
      { last_price: ticker[:last_price].to_f, bid: ticker[:bid].to_f, ask: ticker[:ask].to_f }
    end

    transmit_success(data["request_id"], { tickers: tickers })
  rescue ActiveRecord::RecordNotFound
    transmit_error(data["request_id"], "Venue not found")
  rescue StandardError => e
    Rails.logger.error "[WorkerData] batch_fetch_tickers error: #{e.class}: #{e.message}"
    transmit_error(data["request_id"], "Batch fetch failed: #{e.message}")
  end

  # Record evaluation results for multiple strategies + optional tick progress.
  # data: { request_id:, results: [...], session_id: (opt), tick_num: (opt) }
  def batch_record_results(data)
    results_params = data["results"] || []
    if results_params.empty?
      return transmit_error(data["request_id"], "results required")
    end

    outcomes = {}

    results_params.each do |result_param|
      sid = result_param["strategy_id"]
      begin
        strategy = ::Trading::Strategy.includes(:venue, :portfolio).find(sid)
        signals = result_param["signals"] || []
        tick_cost_usd = result_param["tick_cost_usd"].to_f
        market_price = result_param.dig("market_data", "price") || result_param.dig("market_data", "last_price")

        market_data = {
          last_price: market_price.to_f,
          bid: result_param.dig("market_data", "bid").to_f,
          ask: result_param.dig("market_data", "ask").to_f,
          volume_24h: result_param.dig("market_data", "volume_24h").to_f,
          timestamp: Time.current
        }

        symbolized_signals = signals.map { |s| (s.is_a?(Hash) ? s : s.to_h).deep_symbolize_keys }
        engine = ::Trading::StrategyEngine.new(strategy)
        orders = engine.send(:process_signals, symbolized_signals, market_data)

        if tick_cost_usd > 0 && strategy.agent_budget
          budget = strategy.agent_budget
          cost_cents = (tick_cost_usd * 100).round
          budget.increment!(:spent_cents, cost_cents)

          config = strategy.config
          total = (config["total_llm_cost_usd"] || 0.0) + tick_cost_usd
          tick_count = (config["llm_tick_count"] || 0) + 1
          strategy.update_column(:config, config.merge(
            "total_llm_cost_usd" => total.round(4),
            "llm_tick_count" => tick_count,
            "avg_tick_cost_usd" => (total / tick_count).round(6),
            "last_tick_cost_usd" => tick_cost_usd.round(4)
          ))
        end

        strategy.update!(last_tick_at: Time.current)
        strategy.recalculate_pnl!

        if strategy.compounding_enabled?
          recent_realized = strategy.positions.where(status: "closed")
            .where("closed_at > ?", 30.seconds.ago)
            .sum(:realized_pnl_usd).to_f
          if recent_realized > 0
            ::Trading::CompoundingService.new(strategy).accumulate_earnings!(recent_realized)
            ::Trading::CompoundingService.new(strategy).check_and_compound!
          end
        end

        if strategy.dynamic_stop_loss_config["dynamic_stop_loss_enabled"]
          ::Trading::DynamicStopLossService.new(strategy).check!
        end

        if orders.any?
          broadcast_service = ::Trading::TradingBroadcastService.new(strategy.portfolio.account) rescue nil
          broadcast_service&.broadcast_tick_outcome!(strategy, {
            signals_generated: symbolized_signals.size,
            orders_submitted: orders.size
          })
        end

        outcomes[sid] = {
          success: true,
          signals_generated: symbolized_signals.size,
          orders_submitted: orders.size,
          open_positions: strategy.open_positions.count,
          current_pnl_usd: strategy.reload.current_pnl_usd,
          tick_cost_usd: tick_cost_usd
        }
      rescue StandardError => e
        Rails.logger.warn("[WorkerData] batch result failed for #{sid}: #{e.message}")
        outcomes[sid] = { success: false, error: e.message }
      end
    end

    # Optionally record tick progress
    tick_metrics = nil
    if data["session_id"].present? && data["tick_num"].present?
      begin
        session = ::Trading::TrainingSession.find(data["session_id"])
        unless session.terminal?
          runner = ::Trading::LiveTrainingRunner.new(session.account)
          tick_metrics = runner.record_tick!(
            training_session: session,
            tick_num: data["tick_num"].to_i,
            tick_results: results_params.map { |r| outcomes[r["strategy_id"]] || {} }
          )
        end
      rescue StandardError => e
        Rails.logger.warn("[WorkerData] batch tick_complete failed: #{e.message}")
      end
    end

    transmit_success(data["request_id"], { outcomes: outcomes, tick_metrics: tick_metrics })
  rescue StandardError => e
    Rails.logger.error "[WorkerData] batch_record_results error: #{e.message}"
    transmit_error(data["request_id"], e.message)
  end

  # Record tick progress for a training session.
  # data: { request_id:, session_id:, tick_num:, tick_results: [] }
  def training_tick_complete(data)
    session = ::Trading::TrainingSession.find(data["session_id"])

    if session.terminal?
      return transmit_success(data["request_id"], { cancelled: session.cancelled?, status: session.status })
    end

    runner = ::Trading::LiveTrainingRunner.new(session.account)
    metrics = runner.record_tick!(
      training_session: session,
      tick_num: data["tick_num"].to_i,
      tick_results: data["tick_results"] || []
    )

    session.advance_backtest_cursor! if session.backtest_mode?

    transmit_success(data["request_id"], metrics)
  rescue ActiveRecord::RecordNotFound
    transmit_error(data["request_id"], "Training session not found")
  rescue StandardError => e
    transmit_error(data["request_id"], e.message)
  end

  # Check training session status (also serves as heartbeat).
  # data: { request_id:, session_id: }
  def training_status(data)
    session = ::Trading::TrainingSession.find(data["session_id"])

    # Heartbeat: touch updated_at so orphan recovery doesn't reset active sessions
    session.touch if session.status.in?(%w[running pending])

    transmit_success(data["request_id"], {
      id: session.id,
      status: session.status,
      cancelled: session.status == "cancelled",
      completed_ticks: session.completed_ticks,
      total_ticks: session.total_ticks,
      config: session.config,
      strategy_types: session.strategy_types,
      market_count: session.market_count,
      tick_count: session.tick_count,
      tick_interval: session.tick_interval,
      include_classic: session.include_classic,
      portfolio_id: session.portfolio&.id,
      venue_id: session.strategies.first&.trading_venue_id
    })
  rescue ActiveRecord::RecordNotFound
    transmit_error(data["request_id"], "Training session not found")
  end

  # Connection health check.
  # data: { request_id: }
  def ping(data)
    transmit_success(data["request_id"], { pong: true })
  end

  private

  def transmit_success(request_id, data)
    transmit({ request_id: request_id, success: true, data: data })
  end

  def transmit_error(request_id, message)
    transmit({ request_id: request_id, success: false, error: message })
  end
end
