# frozen_string_literal: true

class TradingTrainingSessionJob < BaseJob
  # No auto-retry: the cron runner handles crash recovery, and users can explicitly retry.
  # Sidekiq retries cause duplicate executions because the retried job gets a new JID
  # and competes with fresh dispatches for the session lock.
  sidekiq_options queue: 'trading', retry: 0

  LOCK_TTL = 3600 # 1 hour — auto-expires stale locks from killed workers
  LOCK_RENEW_INTERVAL = 300 # Renew lock every 5 minutes during active execution
  INTER_STRATEGY_DELAY = 2 # seconds between AI strategy ticks
  MAX_CONSECUTIVE_TIMEOUTS = 5

  CLASSIC_TYPES = %w[prediction_market momentum mean_reversion arbitrage tail_end_yield].freeze

  def execute(session_id)
    lock_key = "training_session_lock:#{session_id}"

    # Atomic lock acquisition: SET NX prevents two jobs from both passing
    # the guard when they start simultaneously (e.g., immediate dispatch
    # from session creation + cron runner dispatch).
    acquired = Sidekiq.redis { |conn| conn.set(lock_key, jid, nx: true, ex: LOCK_TTL) }

    unless acquired
      current = Sidekiq.redis { |conn| conn.get(lock_key) }

      if current == "dispatching"
        # The cron runner set a short-lived dispatch sentinel — overwrite with our JID
        Sidekiq.redis { |conn| conn.set(lock_key, jid, ex: LOCK_TTL) }
      elsif current == jid
        # Re-entrant: we already own the lock, just refresh TTL
        Sidekiq.redis { |conn| conn.expire(lock_key, LOCK_TTL) }
      elsif jid_active?(current)
        log_info("Training session already running (JID: #{current}), skipping duplicate", session_id: session_id)
        return { skipped: true, reason: "already_running" }
      else
        # Old JID is dead (worker restart, crash, etc.) — take over the lock
        log_info("Taking over stale lock from dead JID #{current}", session_id: session_id)
        Sidekiq.redis { |conn| conn.set(lock_key, jid, ex: LOCK_TTL) }
      end
    end

    @lock_key = lock_key
    @last_lock_renew = Time.now

    begin
      run_training_loop!(session_id)
    ensure
      # Only release if we still own the lock (guard against stale-lock cleanup races)
      Sidekiq.redis do |conn|
        conn.del(lock_key) if conn.get(lock_key) == jid
      end
    end
  end

  private

  def run_training_loop!(session_id)
    # Phase 1: Setup (or resume)
    log_info("Setting up training session", session_id: session_id)

    setup = api_client.post("/api/v1/internal/trading/training_setup", {
      session_id: session_id
    })

    unless setup["success"]
      log_error_msg("Training setup failed", session_id: session_id, error: setup["error"])
      fail_session!(session_id, setup["error"] || "Setup failed")
      return
    end

    data = setup["data"]
    strategies = data["strategies"] || []
    start_tick = data["start_tick"].to_i
    tick_count = data["tick_count"].to_i
    tick_interval = data["tick_interval"].to_i
    classic_types = data["classic_types"] || CLASSIC_TYPES

    remaining = tick_count - start_tick
    consecutive_timeouts = 0

    log_info("Training loop starting",
      session_id: session_id,
      strategies: strategies.size,
      ticks: "#{start_tick + 1}..#{tick_count}",
      interval: tick_interval
    )

    # Phase 2: Tick loop
    remaining.times do |i|
      tick_num = start_tick + i + 1

      # Check for cancellation
      status = check_status(session_id)
      if status&.dig("data", "cancelled")
        log_info("Training cancelled by user", session_id: session_id, tick: tick_num)
        break
      end

      # Circuit breaker
      if consecutive_timeouts >= MAX_CONSECUTIVE_TIMEOUTS
        msg = "Circuit breaker: #{consecutive_timeouts} consecutive strategy tick timeouts"
        log_warn(msg, session_id: session_id)
        fail_session!(session_id, msg)
        break
      end

      log_info("Training tick #{tick_num}/#{tick_count}", session_id: session_id)

      # Partition strategies: classic (no LLM) first, then AI
      classic_ids = strategies.select { |s| classic_types.include?(s["type"]) }.map { |s| s["id"] }
      ai_ids = strategies.reject { |s| classic_types.include?(s["type"]) }.map { |s| s["id"] }

      tick_results = []

      # Classic strategies — fast, no delay needed
      classic_ids.each do |sid|
        result = tick_strategy(sid)
        tick_results << result
      end

      # AI strategies — need inter-strategy delay
      ai_ids.each_with_index do |sid, idx|
        result = tick_strategy(sid)
        tick_results << result

        if result["timeout"]
          consecutive_timeouts += 1
        else
          consecutive_timeouts = 0
        end

        sleep(INTER_STRATEGY_DELAY) if idx < ai_ids.size - 1
      end

      # Record tick progress on the backend
      record_tick(session_id, tick_num, tick_results)

      # Renew lock periodically so it doesn't expire during long sessions
      renew_lock_if_needed!

      # Wait for next tick
      sleep(tick_interval) if i < remaining - 1
    end

    # Phase 3: Finalize
    log_info("Finalizing training session", session_id: session_id)

    finalize = api_client.post("/api/v1/internal/trading/training_finalize", {
      session_id: session_id
    })

    if finalize["success"]
      log_info("Training session completed", session_id: session_id)
    else
      log_warn("Finalize returned error (session may still be complete)", error: finalize["error"])
    end

    { completed: true, session_id: session_id }
  rescue StandardError => e
    log_error("Training session failed", e, session_id: session_id)
    fail_session!(session_id, e.message)
    raise
  end

  def tick_strategy(strategy_id)
    fetcher = trading_data_fetcher
    context = fetcher.strategy_evaluation_context(strategy_id)

    return context.merge("timeout" => false) if context["skipped"]

    strategy_type = context.dig("strategy", "strategy_type")
    evaluator_class = Trading::Evaluators::Base.for_type(strategy_type)

    unless evaluator_class
      log_warn("No evaluator for strategy type '#{strategy_type}', skipping", strategy_id: strategy_id)
      return { "skipped" => true, "reason" => "unsupported_type", "timeout" => false }
    end

    # Check risk/regime gates from context
    risk = context["risk_check"] || {}
    return { "skipped" => true, "reason" => risk["reason"], "timeout" => false } unless risk["allowed"] == true || risk[:allowed] == true

    regime = context["regime_check"] || {}
    return { "skipped" => true, "reason" => regime["reason"], "timeout" => false } unless regime["allowed"] == true || regime[:allowed] == true

    evaluator = evaluator_class.new(context, llm_client: training_llm_client, data_fetcher: fetcher)
    evaluator.trading_context = context["trading_context"]
    signals = evaluator.evaluate
    tick_cost = evaluator.respond_to?(:tick_cost_usd) ? evaluator.tick_cost_usd : 0.0

    result = fetcher.record_evaluation_result(
      strategy_id: strategy_id,
      signals: signals,
      tick_cost_usd: tick_cost,
      market_data: context["market_data"] || {}
    )

    (result || {}).merge("timeout" => false)
  rescue StandardError => e
    log_warn("Strategy tick failed", strategy_id: strategy_id, error: e.message)
    { "timeout" => e.message.include?("timeout"), "error" => e.message }
  end

  def trading_data_fetcher
    @trading_data_fetcher ||= Trading::DataFetcher.new(api_client)
  end

  def training_llm_client
    @training_llm_client ||= LlmProxyClient.new(
      api_client.method(:post),
      api_client.method(:get)
    )
  end

  def record_tick(session_id, tick_num, tick_results)
    api_client.post("/api/v1/internal/trading/training_tick_complete", {
      session_id: session_id,
      tick_num: tick_num,
      tick_results: tick_results
    })
  rescue StandardError => e
    log_warn("Failed to record tick progress", session_id: session_id, tick: tick_num, error: e.message)
  end

  def check_status(session_id)
    api_client.get("/api/v1/internal/trading/training_status", { session_id: session_id })
  rescue StandardError
    nil
  end

  def renew_lock_if_needed!
    return unless @lock_key && @last_lock_renew

    if Time.now - @last_lock_renew > LOCK_RENEW_INTERVAL
      Sidekiq.redis { |conn| conn.expire(@lock_key, LOCK_TTL) }
      @last_lock_renew = Time.now
    end
  rescue StandardError => e
    log_warn("Lock renewal failed: #{e.message}")
  end

  def fail_session!(session_id, message)
    api_client.post("/api/v1/internal/trading/fail_training_session", {
      session_id: session_id,
      error_message: message
    })
  rescue StandardError => e
    log_error("Failed to mark session as failed", e, session_id: session_id)
  end

  def jid_active?(check_jid)
    busy_jids = Sidekiq::Workers.new.map { |_, _, work| work["payload"]["jid"] rescue nil }.compact
    busy_jids.include?(check_jid)
  rescue StandardError
    true # Assume active if we can't check
  end

  def log_error_msg(msg, **context)
    PowernodeWorker.application.logger.error("[TradingTraining] #{msg} #{context}")
  end
end
