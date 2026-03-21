# frozen_string_literal: true

# Independent per-strategy execution job. Each instance owns ONE strategy,
# evaluates it on its own tick_interval, and self-schedules the next tick.
#
# Replaces the monolithic tick loop in TradingTrainingSessionJob for
# continuous-mode sessions. Fixed-tick and backtest modes still use the
# legacy batch loop.
#
# Key design:
#   - Per-strategy Redis lock (not per-session) so multiple workers can
#     run strategies concurrently across the Sidekiq cluster
#   - Interruptible sleep: wakes early on significant price events
#   - Self-scheduling: enqueues the next tick via perform_in
#   - Rolling performance window in Redis for mid-session optimization
class TradingStrategyRunnerJob < BaseJob
  sidekiq_options queue: 'trading_critical', retry: 0

  LOCK_TTL = 120 # seconds — short since each tick is independent
  PERF_WINDOW_SIZE = 100 # rolling window entries
  PERF_KEY_PREFIX = "trading:perf"

  def execute(strategy_id, session_id, options = {})
    @strategy_id = strategy_id
    @session_id = session_id
    @options = options || {}

    lock_key = "strategy_runner_lock:#{strategy_id}"

    # Per-strategy lock — prevents duplicate runners for the same strategy
    acquired = Sidekiq.redis { |conn| conn.set(lock_key, jid, nx: true, ex: LOCK_TTL) }
    unless acquired
      current = Sidekiq.redis { |conn| conn.get(lock_key) }
      if current != jid && jid_active?(current)
        log_info("Strategy #{strategy_id} already running (JID: #{current}), skipping")
        return { skipped: true, reason: "already_running" }
      end
      # Dead JID — take over
      Sidekiq.redis { |conn| conn.set(lock_key, jid, ex: LOCK_TTL) }
    end

    begin
      run_tick!
    ensure
      Sidekiq.redis { |conn| conn.del(lock_key) if conn.get(lock_key) == jid }
    end
  end

  private

  def run_tick!
    # Check session is still running
    status = check_session_status
    unless status
      log_info("Session #{@session_id} gone — stopping strategy runner", strategy_id: @strategy_id)
      return { stopped: true, reason: "session_gone" }
    end

    session_status = status.dig("data", "status")
    if session_status.in?(%w[cancelled failed completed])
      log_info("Session #{session_status} — stopping strategy runner", strategy_id: @strategy_id)
      return { stopped: true, reason: "session_#{session_status}" }
    end

    # Check completion requested
    if status.dig("data", "completion_requested") || status.dig("data", "config", "completion_requested")
      log_info("Completion requested — stopping strategy runner", strategy_id: @strategy_id)
      return { stopped: true, reason: "completion_requested" }
    end

    # Check strategy time bounds
    strategy_data = status.dig("data") || {}
    begins_at = context_begins_at(strategy_data)
    ends_at = context_ends_at(strategy_data)

    if begins_at && Time.current < Time.parse(begins_at)
      delay = [(Time.parse(begins_at) - Time.current).ceil, 300].min
      log_info("Strategy not yet in time window, rescheduling in #{delay}s", strategy_id: @strategy_id)
      TradingStrategyRunnerJob.perform_in(delay, @strategy_id, @session_id, @options)
      return { skipped: true, reason: "time_pending" }
    end

    if ends_at && Time.current > Time.parse(ends_at)
      log_info("Strategy time window expired", strategy_id: @strategy_id)
      return { stopped: true, reason: "time_expired" }
    end

    # Fetch context for this single strategy
    context = fetch_context
    return schedule_next!(context) if context["skipped"] || context["error"]

    # Store market data in shared cache for concurrent runners [H2, M3]
    pair = context.dig("strategy", "pair")
    venue_id = context.dig("strategy", "trading_venue_id")
    if pair && venue_id && context.dig("market_data")
      Trading::SharedPriceCache.store(venue_id, pair, context["market_data"])
    end

    # Extract tick interval for scheduling
    tick_interval = context.dig("strategy", "tick_interval_seconds")&.to_i || 30

    # Evaluate
    evaluator = build_evaluator
    result = evaluator.evaluate(@strategy_id, context)

    signals_count = result["signals_generated"] || 0
    log_info("Evaluated: #{signals_count} signals, cost=$#{result['tick_cost_usd'] || 0}",
             strategy_id: @strategy_id, pair: context.dig("strategy", "pair"))

    # Submit result to server (signals + market data for order processing)
    if result["_submission"]
      submit_result!(result["_submission"])
    end

    # Stop immediately if circuit breaker was tripped by reactive risk check
    if @circuit_breaker_halt
      log_info("Halting runner — circuit breaker tripped after result submission", strategy_id: @strategy_id)
      return { stopped: true, reason: "circuit_breaker" }
    end

    # Record to rolling performance window
    record_performance_window!(result, context)

    # Schedule next tick (interruptible — may wake early on price events)
    schedule_next!(context, tick_interval: tick_interval)

    result
  rescue Faraday::ConnectionFailed, Errno::ECONNREFUSED => e
    log_info("Backend unavailable, retrying in 30s", strategy_id: @strategy_id)
    schedule_next!(nil, tick_interval: 30)
    { error: e.message, backend_down: true }
  rescue BackendApiClient::ApiError => e
    if e.message.include?("Circuit breaker")
      log_info("Circuit breaker open, retrying in 30s", strategy_id: @strategy_id)
      schedule_next!(nil, tick_interval: 30)
      { error: e.message, circuit_breaker: true }
    else
      log_error("Strategy runner tick failed", e, strategy_id: @strategy_id)
      schedule_next!(nil, tick_interval: @options["tick_interval"]&.to_i || 30)
      { error: e.message }
    end
  rescue StandardError => e
    log_error("Strategy runner tick failed", e, strategy_id: @strategy_id)
    # Still schedule next tick on error — don't let a single failure kill the runner
    schedule_next!(nil, tick_interval: @options["tick_interval"]&.to_i || 30)
    { error: e.message }
  end

  def check_session_status
    trading_data_fetcher.training_status(@session_id)
  rescue Faraday::ConnectionFailed, Errno::ECONNREFUSED
    raise # Let backend-down errors propagate to run_tick! for backoff handling
  rescue StandardError => e
    log_warn("Session status check failed: #{e.message}", strategy_id: @strategy_id)
    nil
  end

  def fetch_context
    trading_data_fetcher.strategy_evaluation_context(@strategy_id)
  rescue Faraday::ConnectionFailed, Errno::ECONNREFUSED
    raise # Let backend-down errors propagate to run_tick! for backoff handling
  rescue StandardError => e
    log_warn("Context fetch failed: #{e.message}", strategy_id: @strategy_id)
    { "error" => e.message, "skipped" => true }
  end

  def build_evaluator
    @evaluator ||= Trading::StrategyEvaluator.new(
      llm_client: training_llm_client,
      data_fetcher: trading_data_fetcher
    )
  end

  def submit_result!(submission)
    result = trading_data_fetcher.record_evaluation_result(**submission)
    if result&.dig("circuit_breaker_tripped")
      log_warn("Circuit breaker tripped — stopping runner", strategy_id: @strategy_id)
      @circuit_breaker_halt = true
    end
  rescue StandardError => e
    log_warn("Result submission failed: #{e.message}", strategy_id: @strategy_id)
  end

  # Session-level metrics aggregation is handled by the orchestrator's
  # periodic supervision loop, not by individual strategy runners.
  # Each runner's submit_result! already updates strategy-level P&L.

  # Record evaluation outcome to a Redis rolling window for mid-session analysis.
  def record_performance_window!(result, context)
    key = "#{PERF_KEY_PREFIX}:#{@strategy_id}"
    entry = {
      at: Time.now.to_f,
      pnl_delta: 0, # Updated on next tick when we see position changes
      signals: result["signals_generated"] || 0,
      cost: result["tick_cost_usd"] || 0,
      regime: context.dig("regime_check", "regime"),
      pair: context.dig("strategy", "pair")
    }.to_json

    Sidekiq.redis do |conn|
      conn.rpush(key, entry)
      conn.ltrim(key, -PERF_WINDOW_SIZE, -1)
      conn.expire(key, 86400) # 24h TTL
    end
  rescue StandardError
    # Non-critical
  end

  # Schedule the next tick. Checks for pending price events to wake early.
  def schedule_next!(context, tick_interval: nil)
    tick_interval ||= context&.dig("strategy", "tick_interval_seconds")&.to_i || 30
    pair = context&.dig("strategy", "pair")
    strategy_type = context&.dig("strategy", "strategy_type")

    # Check for reactive wakeup — if a price event is pending, use a shorter interval
    if pair && strategy_type
      tier = Trading::PriceChangeDetector.tier_for(strategy_type)
      if Trading::PriceChangeDetector.wake_pending?(pair, tier)
        tier_config = Trading::PriceChangeDetector::REACTIVITY_TIERS[tier]
        tick_interval = [tier_config[:max_frequency], tick_interval].min
        log_info("Reactive wakeup: next tick in #{tick_interval}s (price event for #{pair})",
                 strategy_id: @strategy_id)
      end
    end

    # Clamp to reasonable bounds
    tick_interval = tick_interval.clamp(2, 300)

    TradingStrategyRunnerJob.perform_in(
      tick_interval,
      @strategy_id,
      @session_id,
      @options.merge("tick_interval" => tick_interval)
    )
  end

  # Extract strategy begins_at from context or options
  def context_begins_at(data)
    @options["begins_at"] || data.dig("strategy_begins_at")
  end

  def context_ends_at(data)
    @options["ends_at"] || data.dig("strategy_ends_at")
  end

  # Trading-specific helpers (same as TradingTrainingSessionJob)
  def trading_data_fetcher
    @trading_data_fetcher ||= Trading::DataFetcher.new(api_client)
  end

  def training_llm_client
    @training_llm_client ||= LlmProxyClient.new(
      api_client.method(:post),
      api_client.method(:get)
    )
  end

  def jid_active?(check_jid)
    return false unless check_jid
    Sidekiq::Workers.new.any? { |_, _, work| work["payload"]["jid"] == check_jid }
  rescue StandardError
    false
  end
end
