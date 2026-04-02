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

  # Signal submission removed — all tick results now use HTTP POST /api/v1/internal/trading/batch_record_results.
  # The HTTP path includes position pre-ticks, PnL settlement, price snapshots,
  # health reports, and learning injection that the WS path was missing.

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
      completion_requested: session.completion_requested?,
      completed_ticks: session.completed_ticks,
      total_ticks: session.total_ticks,
      config: session.config,
      strategy_types: session.strategy_types,
      market_count: session.market_count,
      tick_count: session.tick_count,
      tick_interval: session.tick_interval,
      include_classic: session.include_classic,
      portfolio_id: session.portfolio&.id,
      venue_id: session.strategies.first&.trading_venue_id,
      mode: session.session_mode,
      ends_at: session.ends_at&.iso8601,
      active_strategy_count: session.strategies.where(status: "active").count
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
