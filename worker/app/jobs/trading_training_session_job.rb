# frozen_string_literal: true

class TradingTrainingSessionJob < BaseJob
  # No auto-retry: the cron runner handles crash recovery, and users can explicitly retry.
  # Sidekiq retries cause duplicate executions because the retried job gets a new JID
  # and competes with fresh dispatches for the session lock.
  sidekiq_options queue: 'trading', retry: 0

  # Tick-scoped price cache. Pre-warmed with batch fetch at tick start,
  # used by evaluators to avoid individual venue_fetch_ticker calls.
  # Lives for one tick only — prices are stale after tick completes.
  class TickPriceCache
    attr_reader :hit_count, :miss_count

    def initialize
      @prices = {}
      @hit_count = 0
      @miss_count = 0
    end

    def warm!(fetcher, pairs, venue_id, ws_cache: nil)
      return if pairs.empty?

      # Phase 1: Direct Redis reads (populated by WS, <1ms)
      if ws_cache
        cached = ws_cache.get_multi(pairs)
        cached.each { |pair, data| @prices[pair] = data if data }
      end

      # Phase 2: HTTP fallback for misses only
      uncached = pairs.reject { |p| @prices.key?(p) }
      if uncached.any?
        batch = fetcher.batch_fetch_tickers(pairs: uncached, venue_id: venue_id)
        batch.each { |pair, data| @prices[pair] = data if data }
      end
    end

    def get(pair)
      if @prices.key?(pair)
        @hit_count += 1
        @prices[pair]
      else
        @miss_count += 1
        nil
      end
    end

    def set(pair, data)
      @prices[pair] = data
    end

    def size
      @prices.size
    end
  end

  LOCK_TTL = 900 # 15 min — auto-expires stale locks from killed workers

  # Atomic CAS: replace lock value only if it still holds expected_value.
  # Prevents TOCTOU races where two jobs both see the same lock state and overwrite.
  LOCK_CAS_SCRIPT = <<~LUA
    if redis.call('get', KEYS[1]) == ARGV[1] then
      redis.call('set', KEYS[1], ARGV[2], 'EX', ARGV[3])
      return 1
    else
      return 0
    end
  LUA
  LOCK_RENEW_INTERVAL = 120 # Renew lock every 2 minutes during active execution
  INTER_STRATEGY_DELAY = 2 # seconds between AI strategy ticks
  MAX_CONSECUTIVE_TIMEOUTS = 5

  # Adaptive tick interval bounds (seconds)
  ADAPTIVE_MIN_INTERVAL = 5   # Never tick faster than 5s (API rate limit safety)
  ADAPTIVE_MAX_INTERVAL = 120 # Never tick slower than 2 min
  ADAPTIVE_SPEEDUP = 0.5      # Reduce interval to 50% when market is active
  ADAPTIVE_SLOWDOWN = 1.5     # Increase interval to 150% when market is quiet

  CLASSIC_TYPES = %w[prediction_market momentum mean_reversion arbitrage tail_end_yield].freeze
  STRATEGY_BATCH_SIZE = 25

  def execute(session_id)
    lock_key = "training_session_lock:#{session_id}"

    # Atomic lock acquisition: SET NX prevents two jobs from both passing
    # the guard when they start simultaneously (e.g., immediate dispatch
    # from session creation + cron runner dispatch).
    acquired = Sidekiq.redis { |conn| conn.set(lock_key, jid, nx: true, ex: LOCK_TTL) }

    unless acquired
      current = Sidekiq.redis { |conn| conn.get(lock_key) }

      if current == "dispatching"
        # Atomic CAS: overwrite ONLY if still "dispatching" (prevents two jobs both winning)
        won = Sidekiq.redis { |conn|
          conn.call("EVAL", LOCK_CAS_SCRIPT, 1, lock_key, "dispatching", jid, LOCK_TTL.to_s)
        }
        unless won == 1
          log_info("Lost dispatching race, another job took over", session_id: session_id)
          return { skipped: true, reason: "dispatching_race_lost" }
        end
      elsif current == jid
        # Re-entrant: we already own the lock, just refresh TTL
        Sidekiq.redis { |conn| conn.expire(lock_key, LOCK_TTL) }
      elsif jid_active?(current)
        log_info("Training session already running (JID: #{current}), skipping duplicate", session_id: session_id)
        return { skipped: true, reason: "already_running" }
      else
        # Dead JID — only take over if lock is old enough (prevents startup race)
        lock_ttl = Sidekiq.redis { |conn| conn.ttl(lock_key) }
        lock_age = LOCK_TTL - [lock_ttl, 0].max
        if lock_age < 30
          log_info("Lock too fresh (#{lock_age}s), assuming holder is starting up", session_id: session_id)
          return { skipped: true, reason: "lock_too_fresh" }
        end
        # Atomic CAS: overwrite only if still held by the dead JID
        won = Sidekiq.redis { |conn|
          conn.call("EVAL", LOCK_CAS_SCRIPT, 1, lock_key, current, jid, LOCK_TTL.to_s)
        }
        unless won == 1
          log_info("Stale lock already taken over by another job", session_id: session_id)
          return { skipped: true, reason: "stale_lock_race_lost" }
        end
        log_info("Took over stale lock from dead JID #{current} (age: #{lock_age}s)", session_id: session_id)
      end
    end

    @lock_key = lock_key
    @last_lock_renew = Time.now
    @session_id = session_id

    # Establish WebSocket connection for high-frequency data calls
    @data_ws_client = connect_data_ws
    @data_fetcher = trading_data_fetcher

    @training_completed = false

    begin
      run_training_loop!(session_id)
      @training_completed = true
    ensure
      # Only release if we still own the lock (guard against stale-lock cleanup races)
      Sidekiq.redis do |conn|
        conn.del(lock_key) if conn.get(lock_key) == jid
      end

      # Clean up WebSocket connection
      disconnect_data_ws

      # If the job was killed (SIGTERM from worker restart, OOM, etc.) without
      # completing or explicitly failing, mark the session as failed so it doesn't
      # sit in "running" state with no worker processing it.
      unless @training_completed
        fail_session!(session_id, "Worker job terminated unexpectedly (worker restart or signal)")
        log_info("Marked session as failed after unexpected termination", session_id: session_id)
      end
    end
  end

  private

  def run_training_loop!(session_id)
    # Phase 1: Setup (or resume)
    log_info("Setting up training session", session_id: session_id)

    data = run_setup!(session_id)

    unless data
      log_error_msg("Training setup failed", session_id: session_id)
      return
    end

    strategies = data["strategies"] || []
    start_tick = data["start_tick"].to_i
    tick_count = data["tick_count"].to_i
    tick_interval = data["tick_interval"].to_i
    classic_types = data["classic_types"] || CLASSIC_TYPES

    # Post-setup cancellation check: setup takes minutes — the session may have
    # been cancelled while strategies were being created.
    post_setup_status = check_status(session_id)
    if post_setup_status&.dig("data", "cancelled")
      log_info("Training cancelled during setup — closing positions", session_id: session_id)
      close_session_positions!(session_id)
      return { cancelled: true, session_id: session_id }
    end

    remaining = tick_count - start_tick
    consecutive_timeouts = 0
    consecutive_status_failures = 0

    # Acquire WebSocket connection for Kalshi venues
    ws_active = false
    ws_acquired = false
    ws_pairs = strategies.filter_map { |s| s["pair"] }.uniq
    session_status = check_status(session_id)
    session_config = session_status&.dig("data", "config") || {}
    venue_slug = session_config["venue_slug"]
    dry_run = session_config["mode"] == "dry_run"
    backtest = session_config["mode"] == "backtest"

    if ws_pairs.any? && !backtest
      venue_id = session_status&.dig("data", "venue_id")
      portfolio_id = session_status&.dig("data", "portfolio_id")
      ws_config = fetch_venue_ws_config(venue_id, portfolio_id)
      if ws_config && ws_config["ws_enabled"]
        ws_acquired = true
        ws_active = acquire_venue_ws(venue_slug, ws_config, ws_pairs)
        log_info("#{venue_slug} WS #{ws_active ? 'connected' : 'unavailable (REST fallback)'}", session_id: session_id)
      end
    end

    # Local tick interval tracking: avoids fetching contexts for non-due strategies.
    # On tick 1, all strategies are due (no local timestamps). After each tick, we
    # record when each strategy was evaluated and its interval, enabling pre-filtering
    # before the expensive batch context fetch on subsequent ticks.
    @strategy_intervals = {}   # strategy_id => tick_interval_seconds
    @last_evaluated_at = {}    # strategy_id => Time

    log_info("Training loop starting",
      session_id: session_id,
      strategies: strategies.size,
      ticks: "#{start_tick + 1}..#{tick_count}",
      interval: tick_interval
    )

    # Phase 2: Tick loop
    remaining.times do |i|
      tick_num = start_tick + i + 1

      # Check session status: existence, cancellation, failure
      status = check_status(session_id)

      # Ghost job prevention: abort immediately if session was deleted
      if status&.dig("session_gone")
        log_warn("Session #{session_id} no longer exists — aborting ghost job", session_id: session_id)
        break
      end

      # Track consecutive status failures as secondary ghost detection
      # (covers cases where 404 is masked by network/circuit-breaker errors)
      if status.nil?
        consecutive_status_failures += 1
        if consecutive_status_failures >= 3
          log_warn("#{consecutive_status_failures} consecutive status check failures — aborting",
            session_id: session_id)
          break
        end
      else
        consecutive_status_failures = 0
      end

      # Abort if session was cancelled or failed externally
      if status&.dig("data", "cancelled") || status&.dig("data", "status").in?(%w[cancelled failed])
        log_info("Training #{status.dig('data', 'status') || 'cancelled'} — closing positions",
          session_id: session_id, tick: tick_num)
        close_session_positions!(session_id)
        break
      end

      # Circuit breaker
      if consecutive_timeouts >= MAX_CONSECUTIVE_TIMEOUTS
        msg = "Circuit breaker: #{consecutive_timeouts} consecutive strategy tick timeouts"
        log_warn(msg, session_id: session_id)
        fail_session!(session_id, msg)
        break
      end

      tick_started_at = Time.now
      log_info("Training tick #{tick_num}/#{tick_count}", session_id: session_id)

      all_strategy_ids = strategies.map { |s| s["id"] }

      tick_results = []

      # Pre-filter: determine which strategies are due BEFORE the expensive context fetch.
      # On tick 1, @strategy_intervals is empty so all strategies are due.
      # On tick 2+, we use locally-tracked intervals and timestamps.
      now = Time.now
      if @strategy_intervals.empty?
        due_strategy_ids = all_strategy_ids
      else
        due_strategy_ids = all_strategy_ids.select do |sid|
          interval = @strategy_intervals[sid] || tick_interval
          last_eval = @last_evaluated_at[sid]
          last_eval.nil? || (now - last_eval) >= interval
        end

        skipped = all_strategy_ids.size - due_strategy_ids.size
        if skipped > 0
          log_info("Tick #{tick_num}: #{due_strategy_ids.size}/#{all_strategy_ids.size} strategies due (#{skipped} skipped)",
            session_id: session_id)
        end
      end

      # Partition due strategies: classic (no LLM) first, then AI
      classic_ids = strategies.select { |s| classic_types.include?(s["type"]) && due_strategy_ids.include?(s["id"]) }.map { |s| s["id"] }
      ai_ids = strategies.reject { |s| classic_types.include?(s["type"]) || !due_strategy_ids.include?(s["id"]) }.map { |s| s["id"] }

      # Phase A: Batch-fetch contexts only for due strategies (not all)
      contexts_by_id = fetch_batch_contexts(due_strategy_ids)

      # Learn tick_interval_seconds from contexts (populates on tick 1, updates thereafter)
      contexts_by_id.each do |sid, ctx|
        next unless ctx.is_a?(Hash) && !ctx["skipped"]
        interval = ctx.dig("strategy", "tick_interval_seconds")
        @strategy_intervals[sid.to_s] = interval.to_i if interval
      end

      # Mid-tick heartbeat: batch context fetch can take 70s+ for large Polymarket
      # sessions. Without this, orphan recovery may consider the session stale.
      check_status(session_id)
      renew_lock_if_needed!

      # Phase B: Evaluate all strategies locally using pre-fetched contexts
      pending_results = []

      # Pre-warm tick price cache with all pair_registry pairs (ALL pairs, not just due).
      # Skipped strategies need cached prices for when they become due.
      @tick_price_cache = TickPriceCache.new
      @graph_cache = {}
      sample_context = contexts_by_id.values.find { |c| c.is_a?(Hash) && !c["skipped"] }
      if sample_context
        all_pairs = (sample_context["pair_registry"] || {}).keys
        venue_id = sample_context.dig("strategy", "venue_id")
        if all_pairs.any? && venue_id && !backtest
          ws_cache = ws_active ? venue_ws_price_cache(venue_slug) : nil
          @tick_price_cache.warm!(trading_data_fetcher, all_pairs, venue_id, ws_cache: ws_cache)
          log_info("Price cache warmed: #{@tick_price_cache.size} pairs", session_id: session_id)
        end

        # Pre-warm graph cache only for DUE strategies' pairs (not all).
        # Graph warming is the most expensive per-ticker operation (~1s each).
        account_id = sample_context.dig("strategy", "account_id")
        first_agent_id = sample_context["agent_id"]
        similarity_threshold = 0.55 # default; evaluators may override per-strategy

        # Graph pre-warm: skip in dry_run/backtest mode to save 50+ API calls/tick
        unless dry_run || backtest
          due_pairs = contexts_by_id.values
            .select { |c| c.is_a?(Hash) && !c["skipped"] }
            .filter_map { |c| c.dig("strategy", "pair") }
          base_tickers = due_pairs.map { |p| p.sub(%r{/(YES|NO)\z}, "") }.uniq

          base_tickers.each do |bt|
            pair_key = "#{bt}/YES"
            @graph_cache[bt] ||= trading_data_fetcher.market_graph_related(
              pair: pair_key,
              account_id: account_id,
              agent_id: first_agent_id,
              similarity_threshold: similarity_threshold
            )
          rescue StandardError => e
            log_warn("Graph pre-warm failed for #{bt}", error: e.message)
          end
          log_info("Graph cache warmed: #{@graph_cache.size} base tickers", session_id: session_id)

          # Batch-fetch prices for all related pairs discovered via graph.
          # This eliminates ~100+ individual venue_fetch_ticker calls per tick.
          all_related_pairs = @graph_cache.values.flatten.filter_map { |r| r["pair"] || r[:pair] }.uniq
          uncached = all_related_pairs.reject { |p| @tick_price_cache.get(p) }
          if uncached.any? && venue_id
            trading_data_fetcher.batch_fetch_tickers(pairs: uncached.first(100), venue_id: venue_id)
              &.each { |pair, data| @tick_price_cache.set(pair, data) if data }
            log_info("Related price cache warmed: #{uncached.size} pairs fetched", session_id: session_id)
          end
        end
      end

      # Classic strategies — fast, no delay needed
      classic_ids.each do |sid|
        context = contexts_by_id[sid] || contexts_by_id[sid.to_s]
        result = evaluate_strategy(sid, context)
        tick_results << result
        pending_results << result if result["_submission"]
        @last_evaluated_at[sid.to_s] = tick_started_at
      end

      # AI strategies — need inter-strategy delay
      ai_ids.each_with_index do |sid, idx|
        context = contexts_by_id[sid] || contexts_by_id[sid.to_s]
        result = evaluate_strategy(sid, context)
        tick_results << result
        pending_results << result if result["_submission"]
        @last_evaluated_at[sid.to_s] = tick_started_at

        if result["timeout"]
          consecutive_timeouts += 1
        else
          consecutive_timeouts = 0
        end

        sleep(dry_run ? 0.5 : INTER_STRATEGY_DELAY) if idx < ai_ids.size - 1
      end

      # Log cache stats for observability
      if @tick_price_cache && @tick_price_cache.size > 0
        log_info("Price cache stats: #{@tick_price_cache.hit_count} hits, #{@tick_price_cache.miss_count} misses",
          session_id: session_id)
      end

      # Phase C: Batch-submit all results + tick progress in one request
      submit_batch_results(session_id, tick_num, pending_results, tick_results)

      # Phase D: Dispatch async learning extraction for positions closed this tick
      dispatch_learning_extraction!(all_strategy_ids, since: tick_started_at)

      # Renew lock periodically so it doesn't expire during long sessions
      renew_lock_if_needed!

      # Wait for next tick (adaptive interval)
      if i < remaining - 1
        effective_sleep = adaptive_tick_sleep(
          base_interval: tick_interval,
          tick_started_at: tick_started_at,
          tick_results: tick_results,
          tick_num: tick_num,
          tick_count: tick_count
        )
        log_info("Tick sleep #{effective_sleep.round(1)}s (base #{tick_interval}s, elapsed #{(Time.now - tick_started_at).round(1)}s)", session_id: session_id)
        sleep(effective_sleep) if effective_sleep > 0
      end
    end

    # Phase 3: Finalize
    log_info("Finalizing training session", session_id: session_id)

    finalize = api_client.post_with_circuit_breaker("/api/v1/internal/trading/training_finalize", {
      session_id: session_id
    }, circuit_breaker: :trading_training)

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
  ensure
    release_venue_ws(venue_slug, ws_pairs) if ws_acquired
  end

  # Worker-orchestrated multi-phase setup.
  # Each phase is a short-lived backend request (~5-60s), instead of one
  # monolithic 300s+ request that blocks a Puma thread.
  def run_setup!(session_id)
    # Fetch session config (includes strategy_types, venue_slug, etc.)
    status = check_status(session_id)
    unless status&.dig("data")
      fail_session!(session_id, "Could not fetch session config")
      return nil
    end

    config = status["data"]

    # Resume path: if strategies already exist, skip setup and go to tick loop
    if config["completed_ticks"].to_i > 0 || config["status"] == "running"
      log_info("Resuming session at tick #{config['completed_ticks']}", session_id: session_id)
      return resume_from_existing!(session_id, config)
    end

    session_config = config["config"] || {}
    venue_slug = session_config["venue_slug"]
    strategy_types = config["strategy_types"] || []
    include_classic = config["include_classic"]
    initial_balance = (session_config["initial_balance"] || 100_000).to_f

    if include_classic
      strategy_types = (strategy_types + CLASSIC_TYPES).uniq
    end

    # Force-renew lock before each expensive phase so the runner sees a fresh TTL
    # and doesn't mistake a long-running setup for a dead job.
    force_renew_lock!

    # Phase 1: Discover markets
    update_timeline(session_id, "Discovering markets from #{venue_slug}...")
    discovery = @data_fetcher.discover_markets(
      session_id: session_id,
      venue_slug: venue_slug,
      market_count: config["market_count"] || 5,
      config: session_config
    )
    markets = discovery["markets"] || []
    learning_context = discovery["learning_context"]

    # Post-discovery cap: venue APIs return more contracts than market_count
    # (e.g., 2 event groups → 6 contracts). max_markets trims to exact count.
    max_markets = session_config["max_markets"]&.to_i
    if max_markets && markets.size > max_markets
      markets = markets.first(max_markets)
      log_info("Capped markets to #{max_markets} (from #{discovery['markets'].size})", session_id: session_id)
    end

    log_info("Discovered #{markets.size} markets (learning_context: #{learning_context ? 'present' : 'absent'})", session_id: session_id)

    if markets.empty?
      fail_session!(session_id, "No tradeable markets discovered")
      return nil
    end

    # Check cancellation between phases
    return nil if cancelled?(session_id)

    # Phase 2: Apply affinity filtering (local — no API call)
    update_timeline(session_id, "Filtering markets by strategy affinity...")
    symbolized_markets = markets.map { |m| m.transform_keys(&:to_sym) }

    # Symbolize learning_context keys for consistent access in MarketAffinity
    symbolized_learning = if learning_context.is_a?(Hash)
                            lc = learning_context.transform_keys(&:to_sym)
                            lc[:strategy_type_blacklist] = (lc[:strategy_type_blacklist] || []).map do |b|
                              b.is_a?(Hash) ? b.transform_keys(&:to_sym) : b
                            end
                            lc
                          end

    affinity_result = Trading::MarketAffinity.filter_assignments(
      markets: symbolized_markets,
      strategy_types: strategy_types,
      learning_context: symbolized_learning
    )
    assignments = affinity_result[:assignments]
    affinity_result[:stats].each do |type, s|
      if s[:learning_fallback]
        log_info("Affinity: #{type} → learning excluded all, restored fallback", session_id: session_id)
      elsif s[:learning_excluded].to_i > 0
        log_info("Affinity: #{type} → #{s[:matched]}/#{s[:total]} markets, #{s[:learning_excluded]} learning-excluded", session_id: session_id)
      elsif s[:fallback]
        log_info("Affinity: #{type} → 0/#{s[:total]} matched, using all markets (fallback)", session_id: session_id)
      elsif s[:matched] < s[:total]
        log_info("Affinity: #{type} → #{s[:matched]}/#{s[:total]} markets", session_id: session_id)
      end
    end

    if assignments.empty?
      fail_session!(session_id, "No strategy-market assignments after affinity filtering")
      return nil
    end

    # Phase 3: Setup portfolio
    return nil if cancelled?(session_id)
    force_renew_lock!
    update_timeline(session_id, "Setting up portfolio...")
    @data_fetcher.setup_training_portfolio(
      session_id: session_id,
      initial_balance: initial_balance
    )

    # Phase 4: Create strategies in batches
    per_strategy_capital = (initial_balance / assignments.size).round(2)
    strategies = []
    total_batches = (assignments.size.to_f / STRATEGY_BATCH_SIZE).ceil

    assignments.each_slice(STRATEGY_BATCH_SIZE).with_index do |batch, i|
      return nil if cancelled?(session_id)
      force_renew_lock! # Each batch takes 30-60s; keep lock fresh for runner
      update_timeline(session_id, "Creating strategies batch #{i + 1}/#{total_batches}...")
      result = @data_fetcher.create_training_strategies(
        session_id: session_id,
        venue_slug: venue_slug,
        assignments: batch,
        per_strategy_capital: per_strategy_capital
      )
      strategies.concat(result["strategies"] || [])
    end
    log_info("Created #{strategies.size} strategies ($#{per_strategy_capital}/strategy)", session_id: session_id)

    # Phase 5: Prepare knowledge sources
    needs_knowledge = (strategy_types & %w[news_reactive sentiment_analysis combinatorial_arbitrage]).any?
    if needs_knowledge
      return nil if cancelled?(session_id)
      update_timeline(session_id, "Preparing knowledge sources...")
      @data_fetcher.prepare_training_knowledge(
        session_id: session_id,
        strategy_types: strategy_types
      )
    end

    # Phase 6: Seed price history
    unique_pairs = strategies.map { |s| s["pair"] }.compact.uniq
    if unique_pairs.any?
      return nil if cancelled?(session_id)
      update_timeline(session_id, "Seeding price history for #{unique_pairs.size} pairs...")
      @data_fetcher.seed_training_prices(session_id: session_id, pairs: unique_pairs)
    end

    # Phase 7: Start session (transition to running)
    return nil if cancelled?(session_id)
    update_timeline(session_id, "Starting training session...")
    start_result = @data_fetcher.start_training_session(session_id: session_id)

    # Return setup metadata for tick loop
    {
      "strategies" => strategies,
      "tick_count" => start_result["tick_count"] || config["tick_count"],
      "tick_interval" => start_result["tick_interval"] || config["tick_interval"],
      "start_tick" => 0,
      "classic_types" => start_result["classic_types"] || CLASSIC_TYPES
    }
  rescue StandardError => e
    log_error("Training setup orchestration failed", e, session_id: session_id)
    fail_session!(session_id, "Setup failed: #{e.message}")
    nil
  end

  # Resume a session that already has strategies (crash recovery or manual retry).
  # Calls start_training_session which re-activates venue and returns strategy list.
  def resume_from_existing!(session_id, config)
    start_data = @data_fetcher.start_training_session(session_id: session_id)

    {
      "strategies" => start_data["strategies"] || [],
      "start_tick" => start_data["start_tick"].to_i,
      "tick_count" => start_data["tick_count"] || config["tick_count"],
      "tick_interval" => start_data["tick_interval"] || config["tick_interval"],
      "classic_types" => start_data["classic_types"] || CLASSIC_TYPES
    }
  rescue StandardError => e
    log_error("Resume failed", e, session_id: session_id)
    fail_session!(session_id, "Resume failed: #{e.message}")
    nil
  end

  def cancelled?(session_id)
    status = check_status(session_id)
    if status&.dig("session_gone")
      log_warn("Session #{session_id} deleted during setup — aborting", session_id: session_id)
      true
    elsif status&.dig("data", "cancelled") || status&.dig("data", "status").in?(%w[cancelled failed])
      log_info("Training cancelled during setup", session_id: session_id)
      true
    else
      false
    end
  end

  def update_timeline(session_id, message)
    log_info(message, session_id: session_id)
  end

  # Batch-fetch contexts for all strategies in one HTTP request.
  # Falls back to individual fetches if batch endpoint fails.
  def fetch_batch_contexts(strategy_ids)
    fetcher = trading_data_fetcher
    fetcher.batch_strategy_evaluation_contexts(strategy_ids)
  rescue StandardError => e
    log_warn("Batch context fetch failed, falling back to individual", error: e.message)
    result = {}
    strategy_ids.each do |sid|
      result[sid.to_s] = fetcher.strategy_evaluation_context(sid)
    rescue StandardError => inner
      result[sid.to_s] = { "error" => inner.message, "skipped" => true }
    end
    result
  end

  # Evaluate a strategy locally using a pre-fetched context.
  # Returns result hash with "_submission" key if results need to be sent to server.
  def evaluate_strategy(strategy_id, context)
    context ||= { "skipped" => true, "reason" => "no_context" }
    return context.merge("timeout" => false) if context["skipped"] || context["error"]

    strategy_type = context.dig("strategy", "strategy_type")
    evaluator_class = Trading::Evaluators::Base.for_type(strategy_type)

    unless evaluator_class
      log_warn("No evaluator for strategy type '#{strategy_type}', skipping", strategy_id: strategy_id)
      return { "skipped" => true, "reason" => "unsupported_type", "timeout" => false }
    end

    risk = context["risk_check"] || {}
    return { "skipped" => true, "reason" => risk["reason"], "timeout" => false } unless risk["allowed"] == true || risk[:allowed] == true

    regime = context["regime_check"] || {}
    return { "skipped" => true, "reason" => regime["reason"], "timeout" => false } unless regime["allowed"] == true || regime[:allowed] == true

    evaluator = evaluator_class.new(context, llm_client: training_llm_client, data_fetcher: trading_data_fetcher, price_cache: @tick_price_cache, graph_cache: @graph_cache)
    evaluator.trading_context = context["trading_context"]
    signals = evaluator.evaluate
    tick_cost = evaluator.respond_to?(:tick_cost_usd) ? evaluator.tick_cost_usd : 0.0

    submission = {
      strategy_id: strategy_id,
      signals: signals,
      tick_cost_usd: tick_cost,
      market_data: context["market_data"] || {}
    }

    # Pass external data sources for learning tag enrichment
    if evaluator.respond_to?(:external_data_sources) && evaluator.external_data_sources.any?
      submission[:external_data_sources] = evaluator.external_data_sources
    end

    {
      "timeout" => false,
      "signals_generated" => signals.size,
      "tick_cost_usd" => tick_cost,
      "_submission" => submission
    }
  rescue StandardError => e
    log_warn("Strategy tick failed", strategy_id: strategy_id, error: e.message)
    { "timeout" => e.message.include?("timeout"), "error" => e.message }
  end

  # Batch-submit all evaluation results + tick progress in one HTTP request.
  # Falls back to individual submissions if batch endpoint fails.
  def submit_batch_results(session_id, tick_num, pending_results, tick_results)
    return record_tick(session_id, tick_num, tick_results) if pending_results.empty?

    fetcher = trading_data_fetcher
    submissions = pending_results.map { |r| r["_submission"] }
    fetcher.batch_record_evaluation_results(submissions, session_id: session_id, tick_num: tick_num)
    # batch endpoint calls record_tick! inline when session_id/tick_num are provided
  rescue StandardError => e
    log_warn("Batch result submission failed, falling back to individual", error: e.message)
    pending_results.each do |result|
      sub = result["_submission"]
      next unless sub
      fetcher.record_evaluation_result(**sub)
    rescue StandardError => inner
      log_warn("Individual result submission failed", strategy_id: sub[:strategy_id], error: inner.message)
    end
    record_tick(session_id, tick_num, tick_results)
  end

  def dispatch_learning_extraction!(strategy_ids, since: nil)
    cutoff = (since || 90.seconds.ago).iso8601
    TradingLearningExtractionJob.perform_async(strategy_ids, cutoff)
  rescue StandardError => e
    log_warn("Failed to dispatch learning extraction", error: e.message)
  end

  # Establish a WebSocket connection to the server's WorkerDataChannel
  # for high-frequency training data calls (contexts, tickers, results, status).
  # Returns an ActionCableClient or nil on failure.
  def connect_data_ws
    base_url = ENV.fetch('BACKEND_API_URL', 'http://localhost:3000')
    ws_url = base_url.sub(/^http/, 'ws') + '/cable'
    token = WorkerJwt.token

    client = ::ActionCableClient.new(ws_url, token, channel: "WorkerDataChannel")
    client.connect
    log_info("Data WS connected to #{ws_url}")
    client
  rescue StandardError => e
    log_info("Data WS unavailable, using HTTP fallback: #{e.message}")
    nil
  end

  # Clean up WebSocket connection.
  def disconnect_data_ws
    @data_ws_client&.disconnect
  rescue StandardError => e
    log_warn("Data WS disconnect error (non-fatal): #{e.message}")
  ensure
    @data_ws_client = nil
    # Reset the memoized data fetcher so a new one can be created without the stale WS ref
    @trading_data_fetcher = nil
  end

  # Venue-generic WS acquisition — dispatches to the appropriate manager singleton.
  def acquire_venue_ws(slug, ws_config, pairs)
    case slug
    when "kalshi"
      Trading::KalshiWsManager.instance.acquire(
        config: ws_config,
        pairs: pairs,
        credentials: ws_config.slice("api_key", "api_secret", "passphrase")
      )
    when "polymarket"
      Trading::PolymarketWsManager.instance.acquire(
        config: ws_config,
        pairs: pairs,
        pair_registry: ws_config["pair_registry"] || {}
      )
    else
      log_warn("No WS manager for venue #{slug}")
      false
    end
  end

  # Release WS connection for the appropriate venue.
  def release_venue_ws(slug, pairs)
    case slug
    when "kalshi"
      Trading::KalshiWsManager.instance.release(pairs: pairs)
    when "polymarket"
      Trading::PolymarketWsManager.instance.release(pairs: pairs)
    end
  rescue StandardError => e
    log_warn("WS release failed for #{slug}: #{e.message}")
  end

  # Return the active price cache for the venue's WS manager.
  def venue_ws_price_cache(slug)
    case slug
    when "kalshi"
      Trading::KalshiWsManager.instance.price_cache
    when "polymarket"
      Trading::PolymarketWsManager.instance.price_cache
    end
  end

  def fetch_venue_ws_config(venue_id, portfolio_id)
    return nil unless venue_id && portfolio_id

    response = api_client.post(
      "/api/v1/internal/trading/decrypt_venue_credentials",
      { venue_id: venue_id, portfolio_id: portfolio_id }
    )
    data = response.dig("data") || {}
    (data["venue_config"] || {}).merge(data.slice("api_key", "api_secret", "passphrase"))
  rescue StandardError => e
    log_warn("Venue WS config fetch failed: #{e.message}")
    nil
  end

  def trading_data_fetcher
    @trading_data_fetcher ||= Trading::DataFetcher.new(api_client, ws_client: @data_ws_client)
  end

  def training_llm_client
    @training_llm_client ||= LlmProxyClient.new(
      api_client.method(:post),
      api_client.method(:get)
    )
  end

  def record_tick(session_id, tick_num, tick_results)
    trading_data_fetcher.training_tick_complete(
      session_id: session_id, tick_num: tick_num, tick_results: tick_results
    )
  rescue StandardError => e
    log_warn("Failed to record tick progress", session_id: session_id, tick: tick_num, error: e.message)
  end

  def check_status(session_id)
    trading_data_fetcher.training_status(session_id)
  rescue BackendApiClient::ApiError => e
    # 404 = session was deleted — return sentinel so callers can detect and abort
    return { "session_gone" => true, "error" => e.message } if e.status == 404
    nil
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

  # Unconditionally refresh the lock TTL. Used during setup phases that take
  # 30-60s each so the cron runner sees a fresh TTL and doesn't replace the lock.
  def force_renew_lock!
    return unless @lock_key

    Sidekiq.redis { |conn| conn.expire(@lock_key, LOCK_TTL) }
    @last_lock_renew = Time.now
  rescue StandardError => e
    log_warn("Force lock renewal failed: #{e.message}")
  end

  def close_session_positions!(session_id)
    api_client.post_with_circuit_breaker(
      "/api/v1/internal/trading/training_finalize",
      { session_id: session_id },
      circuit_breaker: :trading_training
    )
  rescue StandardError => e
    log_warn("Position closure failed", session_id: session_id, error: e.message)
  end

  def fail_session!(session_id, message)
    api_client.post("/api/v1/internal/trading/fail_training_session", {
      session_id: session_id,
      error_message: message
    })
  rescue StandardError => e
    log_error("Failed to mark session as failed", e, session_id: session_id)
  end

  # Compute adaptive sleep duration based on tick activity and processing time.
  #
  # Three factors:
  # 1. Processing time compensation: subtract elapsed tick time from base interval
  #    so total cycle ≈ base_interval (not base_interval + processing_time)
  # 2. Activity multiplier: speed up when signals/orders are being generated,
  #    slow down when market is quiet (saves API calls)
  # 3. End-of-session acceleration: last 25% of ticks run faster to capture
  #    final price movements before position closeout
  def adaptive_tick_sleep(base_interval:, tick_started_at:, tick_results:, tick_num:, tick_count:)
    elapsed = Time.now - tick_started_at

    # Count signals generated this tick
    signals_count = tick_results.sum { |r| r["signals_generated"].to_i }
    has_activity = signals_count > 0

    # Activity multiplier
    multiplier = if signals_count >= 5
                   ADAPTIVE_SPEEDUP      # High activity: tick faster
                 elsif has_activity
                   0.75                   # Some activity: moderately faster
                 else
                   ADAPTIVE_SLOWDOWN      # No signals: slow down
                 end

    # End-of-session acceleration: last 25% of ticks run at 60% interval
    progress = tick_num.to_f / tick_count
    multiplier *= 0.6 if progress >= 0.75

    # Target interval = base * multiplier, then subtract processing time
    target = base_interval * multiplier
    effective = target - elapsed

    # Clamp to safety bounds
    effective.clamp(ADAPTIVE_MIN_INTERVAL, ADAPTIVE_MAX_INTERVAL)
  end

  def jid_active?(check_jid)
    Sidekiq::Workers.new.each do |_, _, work|
      next unless work.is_a?(Hash)

      jid = work.dig("payload", "jid") || work["jid"]
      return true if jid == check_jid
    end
    false
  rescue StandardError
    true # Assume active if we can't check
  end

  def log_error_msg(msg, **context)
    PowernodeWorker.application.logger.error("[TradingTraining] #{msg} #{context}")
  end
end
