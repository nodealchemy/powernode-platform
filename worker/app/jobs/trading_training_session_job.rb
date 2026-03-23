# frozen_string_literal: true

class TradingTrainingSessionJob < BaseJob
  # No auto-retry: the cron runner handles crash recovery, and users can explicitly retry.
  # Sidekiq retries cause duplicate executions because the retried job gets a new JID
  # and competes with fresh dispatches for the session lock.
  sidekiq_options queue: 'trading_critical', retry: 0

  # Class-level shutdown flag — set by Sidekiq's :quiet callback (fires on SIGTERM).
  # Checked by the tick loop so training sessions exit gracefully within seconds,
  # instead of waiting for Sidekiq's 300s timeout to expire.
  @shutdown_flag = false
  class << self
    def shutdown_requested!
      @shutdown_flag = true
    end

    def shutdown_requested?
      @shutdown_flag
    end

    def reset_shutdown_flag!
      @shutdown_flag = false
    end
  end

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

  # Redis pub/sub listener for real-time lifecycle events from the server.
  # Runs in a background thread. The tick loop checks flags between strategy
  # evaluations so events take effect within seconds, not at the next tick boundary.
  #
  # Supported events:
  #   cancelled       — immediate abort of the tick loop
  #   paused          — graceful pause at next checkpoint
  #   failed          — session failed externally, abort
  #   emergency_halt  — kill switch activated, immediate abort
  #   config_updated  — session config changed (e.g. tick interval, strategies)
  #
  # The channel carries events for ALL sessions; the listener filters by session_id.
  class SessionEventListener
    CHANNEL = "training_session_events"
    TERMINAL_EVENTS = %w[cancelled failed emergency_halt].freeze

    def initialize(session_id)
      @session_id = session_id
      @cancelled = false
      @paused = false
      @completion_requested = false
      @config_changed = false
      @config_changes = {}
      @events = []
      @mutex = Mutex.new
      @thread = nil
    end

    def start!
      @thread = Thread.new do
        redis = ::Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1"))
        redis.subscribe(CHANNEL) do |on|
          on.message do |_channel, message|
            data = JSON.parse(message)
            next unless data["session_id"] == @session_id

            @mutex.synchronize do
              @events << data
              case data["event"]
              when "cancelled", "emergency_halt", "failed"
                @cancelled = true
              when "completion_requested"
                @completion_requested = true
              when "paused"
                @paused = true
              when "config_updated"
                @config_changed = true
                @config_changes = data["changes"] || {}
              end
            end

            # Unsubscribe on terminal events — no further messages expected
            redis.unsubscribe if TERMINAL_EVENTS.include?(data["event"])
          end
        end
      rescue StandardError
        # Subscription failed — fall back to HTTP polling (existing behavior)
      ensure
        redis&.close rescue nil
      end
    end

    def cancelled?
      @mutex.synchronize { @cancelled }
    end

    def completion_requested?
      @mutex.synchronize { @completion_requested }
    end

    def paused?
      @mutex.synchronize { @paused }
    end

    def config_changed?
      @mutex.synchronize { @config_changed }
    end

    def take_config_changes!
      @mutex.synchronize do
        changes = @config_changes
        @config_changed = false
        @config_changes = {}
        changes
      end
    end

    def stop!
      @thread&.kill rescue nil
      @thread = nil
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
  MAX_CONCURRENT_AI_STRATEGIES = 3  # Concurrent AI evaluations per batch [C3]
  MAX_CONSECUTIVE_TIMEOUTS = 5

  # Adaptive tick interval bounds (seconds)
  ADAPTIVE_MIN_INTERVAL = 5   # Never tick faster than 5s (API rate limit safety)
  ADAPTIVE_MAX_INTERVAL = 120 # Never tick slower than 2 min
  ADAPTIVE_SPEEDUP = 0.5      # Reduce interval to 50% when market is active
  ADAPTIVE_SLOWDOWN = 1.5     # Increase interval to 150% when market is quiet

  CLASSIC_TYPES = %w[prediction_market momentum mean_reversion arbitrage tail_end_yield].freeze
  STRATEGY_BATCH_SIZE = 25
  MIN_STRATEGY_CAPITAL = 25.0
  MAX_DISCOVERY_ATTEMPTS = 3
  DISCOVERY_RETRY_DELAY = 2 # seconds between venue API retries

  # C1: Incremental context fetch — cold data (graph, RAG, regime, strategy config)
  # refreshes every Nth tick. Hot data (prices, positions) refreshes every tick
  # via the existing TickPriceCache. This eliminates 70s+ batch context fetch
  # on most ticks for large sessions.
  COLD_CONTEXT_REFRESH_TICKS = 5

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
    @shutdown_requested = false
    @profit_hunter = nil
    @discovered_markets = []

    # Start Redis pub/sub listener for immediate cancellation signals.
    # Falls back to HTTP polling if subscription fails.
    @session_event_listener = SessionEventListener.new(session_id)
    @session_event_listener.start!

    begin
      run_training_loop!(session_id)
      @training_completed = !self.class.shutdown_requested?
    ensure
      @session_event_listener&.stop!
      # Clean shutdown: close positions and pause session so it can resume.
      # This runs on SIGTERM (worker restart), SIGKILL won't reach here but
      # the orphan recovery mechanism handles that case.
      unless @training_completed
        begin
          if self.class.shutdown_requested?
            # Clean shutdown (SIGTERM → :quiet): pause immediately WITHOUT closing
            # positions. The session will resume in seconds on the new worker with
            # positions intact. Calling training_finalize here would mark it "completed".
            log_info("Graceful shutdown: pausing session for fast recovery", session_id: session_id)
            pause_session!(session_id, "Worker shutting down — session paused for recovery")
          else
            # Crash/error path: close positions first, then pause.
            # Recovery is uncertain so we want positions safely closed.
            log_info("Unexpected exit: closing positions and pausing session", session_id: session_id)
            close_session_positions!(session_id)
            pause_session!(session_id, "Worker terminated — positions closed, session paused for recovery")
          end
          log_info("Session paused for recovery after shutdown", session_id: session_id)
        rescue StandardError => e
          # If pause fails (e.g., backend unreachable during restart), fall back to fail
          log_warn("Graceful pause failed, marking as failed: #{e.message}", session_id: session_id)
          fail_session!(session_id, "Worker terminated: #{e.message}")
        end
      end

      # Release lock and WebSocket
      Sidekiq.redis do |conn|
        conn.del(lock_key) if conn.get(lock_key) == jid
      end
      disconnect_data_ws
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

    # Route to continuous orchestrator or legacy batch tick loop
    session_mode = post_setup_status&.dig("data", "mode") || "fixed_ticks"
    log_info("Session mode: #{session_mode}", session_id: session_id)
    if session_mode == "continuous"
      return run_continuous_orchestrator!(session_id, strategies, tick_interval, start_tick: start_tick)
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

    # Initialize profit hunter for resume path (setup path already sets it)
    if @profit_hunter.nil?
      ph_config = extract_profit_hunter_config(session_config)
      @profit_hunter = Trading::ProfitHunter.new(ph_config) if ph_config
    end

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

    # C1: Cold context cache — full strategy contexts cached across ticks.
    # Cold data (strategy config, graph, RAG, regime) changes slowly; only
    # refresh every COLD_CONTEXT_REFRESH_TICKS ticks. Prices are separately
    # warmed via TickPriceCache every tick.
    @cold_context_cache = {}

    # Rolling extraction window: tracks the last time learning extraction was dispatched
    # so positions closed during inter-tick sleep periods aren't missed.
    @last_extraction_at = nil
    @session_started_at = Time.now

    log_info("Training loop starting",
      session_id: session_id,
      strategies: strategies.size,
      ticks: "#{start_tick + 1}..#{tick_count}",
      interval: tick_interval
    )

    # Phase 2: Tick loop
    remaining.times do |i|
      tick_num = start_tick + i + 1

      # Fast exit on Sidekiq shutdown (SIGTERM) — don't start a new tick,
      # let the ensure block close positions and pause the session.
      if self.class.shutdown_requested?
        log_info("Sidekiq shutting down, exiting tick loop after tick #{tick_num - 1}", session_id: session_id)
        break
      end

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

      # Early completion: break cleanly to finalize (positions closed by finalize, report generated)
      # Check top-level field (new backend), config field (existing backend), and pub/sub listener
      if status&.dig("data", "completion_requested") || status&.dig("data", "config", "completion_requested") || completion_requested?(session_id)
        log_info("Early completion requested — proceeding to finalize",
          session_id: session_id, tick: tick_num)
        break
      end

      # Circuit breaker
      if consecutive_timeouts >= MAX_CONSECUTIVE_TIMEOUTS
        msg = "Circuit breaker: #{consecutive_timeouts} consecutive strategy tick timeouts"
        log_warn(msg, session_id: session_id)
        fail_session!(session_id, msg)
        break
      end

      # Max duration enforcement (safety valve for sessions without ends_at)
      max_dur = session_config["max_duration_minutes"]
      if max_dur && @session_started_at && (Time.now - @session_started_at) > max_dur.to_i * 60
        log_info("Max duration #{max_dur}m reached — completing session", session_id: session_id)
        break
      end

      tick_started_at = Time.now
      tick_timings = {} # L2: Per-phase timing metrics
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

      # Phase A: Batch-fetch contexts — C1 incremental: full fetch on tick 1 and
      # every Nth tick, use cached cold context on intermediate ticks.
      # Cold data (strategy config, parameters, graph, RAG) changes slowly;
      # prices are separately warmed via TickPriceCache every tick.
      phase_a_start = Time.now
      # Backtest mode: every tick must be cold — the server advances the backtest cursor
      # each tick, so cached context has stale historical prices from the previous cursor position.
      is_cold_tick = backtest || @cold_context_cache.empty? || (tick_num % COLD_CONTEXT_REFRESH_TICKS == 1)

      if is_cold_tick
        # Full context fetch — updates cold cache
        contexts_by_id = fetch_batch_contexts(due_strategy_ids)
        contexts_by_id.each do |sid, ctx|
          @cold_context_cache[sid.to_s] = ctx if ctx.is_a?(Hash) && !ctx["skipped"]
        end
        log_info("Cold context refresh: #{contexts_by_id.size} strategies fetched", session_id: session_id)
      else
        # Hot tick — use cached cold context, skip expensive server fetch
        contexts_by_id = @cold_context_cache.slice(*due_strategy_ids.map(&:to_s))
        # Include any strategies not in cache (new strategies added mid-session)
        uncached_ids = due_strategy_ids.reject { |sid| @cold_context_cache.key?(sid.to_s) }
        if uncached_ids.any?
          fresh = fetch_batch_contexts(uncached_ids)
          fresh.each { |sid, ctx| @cold_context_cache[sid.to_s] = ctx if ctx.is_a?(Hash) && !ctx["skipped"] }
          contexts_by_id.merge!(fresh)
        end
        log_info("Hot tick: #{contexts_by_id.size} strategies from cache (#{uncached_ids.size} uncached fetched)", session_id: session_id)
      end
      tick_timings[:context_fetch_ms] = ((Time.now - phase_a_start) * 1000).round

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

      # Pre-warm tick price cache for strategy pairs only (not entire pair_registry).
      # pair_registry can have 400+ entries from event enrichment — warming all of them
      # causes 8+ minute CLOB API round-trips on cold cache. Strategy pairs + their
      # complementary pairs (~8-16 total) is sufficient; graph cache handles the rest.
      phase_b_start = Time.now
      @tick_price_cache = TickPriceCache.new
      @graph_cache ||= {} # M1: Persist graph cache across ticks (slow-changing data)
      sample_context = contexts_by_id.values.find { |c| c.is_a?(Hash) && !c["skipped"] }
      if sample_context
        pair_registry = sample_context["pair_registry"] || {}
        strategy_pairs = contexts_by_id.values
          .select { |c| c.is_a?(Hash) && !c["skipped"] }
          .filter_map { |c| c.dig("strategy", "pair") }
        complementary = strategy_pairs.filter_map { |p| pair_registry.dig(p, "complementary_pair") }
        all_pairs = (strategy_pairs + complementary).uniq
        venue_id = sample_context.dig("strategy", "venue_id")
        if all_pairs.any? && venue_id && !backtest
          ws_cache = ws_active ? venue_ws_price_cache(venue_slug) : nil
          @tick_price_cache.warm!(trading_data_fetcher, all_pairs, venue_id, ws_cache: ws_cache)
          log_info("Price cache warmed: #{@tick_price_cache.size} pairs", session_id: session_id)
        end
        tick_timings[:price_cache_ms] = ((Time.now - phase_b_start) * 1000).round

        # Pre-warm graph cache only for DUE strategies' pairs (not all).
        # M1: Graph data is slow-changing — cache results across ticks with a 5-minute
        # TTL. Only re-fetch base tickers not already in @graph_cache or expired.
        graph_start = Time.now
        account_id = sample_context.dig("strategy", "account_id")
        first_agent_id = sample_context["agent_id"]
        similarity_threshold = 0.55

        has_graph_strategies = ai_ids.any?
        unless dry_run || backtest || !has_graph_strategies
          due_pairs = contexts_by_id.values
            .select { |c| c.is_a?(Hash) && !c["skipped"] }
            .filter_map { |c| c.dig("strategy", "pair") }
          base_tickers = due_pairs.map { |p| p.sub(%r{/(YES|NO)\z}, "") }.uniq

          # M1: Only fetch graph data for tickers not already cached.
          # Graph relationships change much slower than prices (~minutes vs ~seconds).
          @graph_cache_timestamps ||= {}
          graph_ttl = 300 # 5 minutes
          uncached_tickers = base_tickers.reject do |bt|
            cached_at = @graph_cache_timestamps[bt]
            @graph_cache.key?(bt) && cached_at && (Time.now - cached_at) < graph_ttl
          end

          if uncached_tickers.any?
            uncached_tickers.each do |bt|
              pair_key = "#{bt}/YES"
              @graph_cache[bt] = trading_data_fetcher.market_graph_related(
                pair: pair_key,
                account_id: account_id,
                agent_id: first_agent_id,
                similarity_threshold: similarity_threshold
              )
              @graph_cache_timestamps[bt] = Time.now
            rescue StandardError => e
              log_warn("Graph pre-warm failed for #{bt}", error: e.message)
            end
            log_info("Graph cache warmed: #{uncached_tickers.size} new tickers (#{@graph_cache.size} total cached)", session_id: session_id)
          else
            log_info("Graph cache hit: all #{base_tickers.size} tickers cached", session_id: session_id)
          end

          # Batch-fetch prices for all related pairs discovered via graph.
          all_related_pairs = @graph_cache.values.flatten.compact.filter_map { |r|
            next unless r.is_a?(Hash)
            r["pair"] || r[:pair]
          }.uniq
          uncached = all_related_pairs.reject { |p| @tick_price_cache.get(p) }
          if uncached.any? && venue_id
            trading_data_fetcher.batch_fetch_tickers(pairs: uncached.first(50), venue_id: venue_id)
              &.each { |pair, data| @tick_price_cache.set(pair, data) if data }
            log_info("Related price cache warmed: #{uncached.size} pairs fetched", session_id: session_id)
          end
        end
        tick_timings[:graph_warm_ms] = ((Time.now - graph_start) * 1000).round
      end

      # Phase B2: Strategy evaluation
      eval_start = Time.now

      # Classic strategies — fast, no delay needed
      classic_ids.each do |sid|
        break if cancel_requested?(session_id)
        context = contexts_by_id[sid] || contexts_by_id[sid.to_s]
        result = evaluate_strategy(sid, context)
        tick_results << result
        pending_results << result if result["_submission"]
        @last_evaluated_at[sid.to_s] = tick_started_at
      end

      # AI strategies — concurrent evaluation in batches of MAX_CONCURRENT_AI_STRATEGIES [C3]
      ai_ids.each_slice(MAX_CONCURRENT_AI_STRATEGIES) do |batch_ids|
        break if cancel_requested?(session_id)

        mutex = Mutex.new
        threads = batch_ids.map do |sid|
          Thread.new do
            ctx = contexts_by_id[sid] || contexts_by_id[sid.to_s]
            Thread.current[:result] = evaluate_strategy(sid, ctx)
            Thread.current[:sid] = sid
          end
        end

        threads.each do |t|
          t.join(120) # per-strategy timeout
          if t.alive?
            t.kill
            t.join(1)
          end

          next unless t[:result]

          mutex.synchronize do
            tick_results << t[:result]
            pending_results << t[:result] if t[:result]["_submission"]
            @last_evaluated_at[t[:sid].to_s] = tick_started_at

            if t[:result]["timeout"]
              consecutive_timeouts += 1
            else
              consecutive_timeouts = 0
            end
          end
        end
      end
      tick_timings[:evaluation_ms] = ((Time.now - eval_start) * 1000).round

      # Mid-tick cancellation: break from outer loop if cancel arrived during evaluation
      if cancel_requested?(session_id)
        log_info("Cancel received mid-tick #{tick_num}, aborting", session_id: session_id)
        close_session_positions!(session_id)
        break
      end

      # Log cache stats for observability
      if @tick_price_cache && @tick_price_cache.size > 0
        log_info("Price cache stats: #{@tick_price_cache.hit_count} hits, #{@tick_price_cache.miss_count} misses",
          session_id: session_id)
      end

      # Phase C: Batch-submit all results + tick progress in one request
      submit_start = Time.now
      submit_batch_results(session_id, tick_num, pending_results, tick_results)
      tick_timings[:submission_ms] = ((Time.now - submit_start) * 1000).round
      tick_timings[:total_ms] = ((Time.now - tick_started_at) * 1000).round

      # L2: Structured latency telemetry — data-driven tick optimization
      log_info("Tick #{tick_num} timings: #{tick_timings.map { |k, v| "#{k}=#{v}ms" }.join(' ')} " \
               "(classic=#{classic_ids.size} ai=#{ai_ids.size} cold=#{is_cold_tick})",
        session_id: session_id)

      # Phase C.5: Profit Hunter — assess tick and fast-prune zero-performers
      if @profit_hunter
        ph_state = build_profit_hunter_state(tick_results, strategies, contexts_by_id)
        assessment = @profit_hunter.assess_tick!(tick_num, ph_state)

        if assessment[:actions]&.include?(:fast_prune) && assessment[:prune_ids].any?
          execute_fast_prune!(session_id, assessment[:prune_ids], strategies, all_strategy_ids)
          log_info("Profit hunter pruned #{assessment[:prune_ids].size} strategies " \
                   "(reserve: $#{@profit_hunter.reserve_capital.round(2)})",
            session_id: session_id, tick: tick_num)
        end
      end

      # Early completion: allow current tick to finish submitting, then break to finalize
      if completion_requested?(session_id)
        log_info("Early completion requested — finishing current tick and proceeding to finalize",
          session_id: session_id, tick: tick_num)
        break
      end

      # Phase D: Mid-session capital rebalance (if configured)
      if session_config.dig("rebalance_enabled") &&
         tick_num >= (session_config["rebalance_min_ticks"] || 3).to_i &&
         (session_config["rebalance_interval_ticks"] || 5).to_i > 0 &&
         (tick_num % (session_config["rebalance_interval_ticks"] || 5).to_i).zero?
        begin
          rebalance_result = api_client.post_with_circuit_breaker(
            "/api/v1/internal/trading/training_rebalance",
            { session_id: session_id, tick_num: tick_num },
            circuit_breaker: :trading_training
          )
          if rebalance_result["success"] && !rebalance_result.dig("data", "skipped")
            decommissioned_ids = rebalance_result.dig("data", "decommissioned") || []
            if decommissioned_ids.any?
              all_strategy_ids -= decommissioned_ids
              decommissioned_ids.each { |sid| @strategy_evaluator&.evict(sid) }
              log_info("Rebalance decommissioned #{decommissioned_ids.size} strategies", session_id: session_id)
            end
            log_info("Rebalance complete: promoted=#{rebalance_result.dig('data', 'promoted')&.size || 0}, " \
              "demoted=#{rebalance_result.dig('data', 'demoted')&.size || 0}", session_id: session_id)
          end
        rescue StandardError => e
          log_warn("Rebalance failed (non-fatal): #{e.message}", session_id: session_id)
        end
      end

      # Phase D.5: Profit Hunter — hunt for new strategy/market combinations
      if @profit_hunter && (tick_num % (@profit_hunter.config[:hunt_interval] || 5)).zero?
        hunt_result = execute_profit_hunt!(session_id, tick_num, strategies, available_markets: @discovered_markets || [])
        if hunt_result && hunt_result[:new_strategies]&.any?
          strategies.concat(hunt_result[:new_strategies])
          all_strategy_ids = strategies.map { |s| s["id"] }
          log_info("Profit hunter deployed #{hunt_result[:new_strategies].size} new strategies " \
                   "(reserve: $#{@profit_hunter.reserve_capital.round(2)})",
            session_id: session_id, tick: tick_num)
        end
      end

      # Phase E: Dispatch async learning extraction for positions closed this tick
      dispatch_learning_extraction!(all_strategy_ids)

      # Phase F: Zero-activity early exit — stop wasting ticks when no market activity
      # Applies to ALL modes: backtest (3 ticks), live/continuous (10 ticks)
      @zero_activity_ticks ||= 0
      tick_signals = tick_results.sum { |r| r["signals"]&.size || r[:signals]&.size || 0 }
      tick_had_activity = tick_signals > 0 || tick_results.any? { |r| (r["positions_opened"] || r[:positions_opened]).to_i > 0 }
      if tick_had_activity
        @zero_activity_ticks = 0
      else
        @zero_activity_ticks += 1
        max_zero = backtest ? [5, strategies.size].max : 10
        if @zero_activity_ticks >= max_zero
          log_info("#{@zero_activity_ticks} consecutive zero-activity ticks — completing early",
            session_id: session_id, tick: tick_num, mode: backtest ? "backtest" : "live")
          break
        end
      end

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
        if effective_sleep > 0
          # Interruptible sleep: check shutdown and cancel flags every second
          # so we exit within ~1s instead of blocking for the full interval.
          deadline = Time.now + effective_sleep
          while Time.now < deadline
            break if self.class.shutdown_requested? || cancel_requested?(session_id) || completion_requested?(session_id)
            sleep([1.0, deadline - Time.now].min)
          end
        end
      end
    end

    # Shutdown exit: skip finalize, let the ensure block pause the session
    # so it can be resumed by the next worker instead of being marked completed.
    if self.class.shutdown_requested?
      log_info("Shutdown requested, skipping finalize for recovery", session_id: session_id)
      return { shutdown: true, session_id: session_id }
    end

    # Phase 3: Profit Hunter reflection (before finalize)
    if @profit_hunter
      reflection = @profit_hunter.reflect!
      log_info("Profit hunter reflect: #{reflection[:hypotheses_confirmed]} confirmed, " \
               "#{reflection[:hypotheses_rejected]} rejected, #{reflection[:total_pruned]} pruned",
        session_id: session_id)
      save_profit_hunter_reflection!(session_id, reflection)
    end

    # Phase 4: Finalize
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

  # Continuous mode orchestrator. Instead of a batch tick loop, this:
  #   1. Launches independent TradingStrategyRunnerJob per strategy
  #   2. Enters a supervision loop that monitors health + runs periodic tasks
  #   3. Finalizes when session ends (time-based, user-requested, or all strategies pruned)
  #
  # The orchestrator is lightweight — strategies run themselves. It handles:
  #   - Health monitoring (detect dead runners, restart them)
  #   - Periodic parameter evolution (every 30 min)
  #   - Market scanning & rotation (every 15-30 min)
  #   - Promotion candidate detection
  #   - Capital rebalancing
  ORCHESTRATOR_POLL_INTERVAL = 30 # seconds between supervision checks (L1: halved from 60s)

  def run_continuous_orchestrator!(session_id, strategies, tick_interval, start_tick: 0)
    @aggregate_tick_counter = start_tick
    @session_started_at ||= Time.now
    log_info("Starting continuous orchestrator", session_id: session_id, strategies: strategies.size, start_tick: start_tick)

    # Read session config for supervision settings
    orchestrator_status = check_status(session_id)
    orchestrator_config = orchestrator_status&.dig("data", "config") || {}

    # Initialize profit hunter for continuous mode (same config extraction as fixed_ticks)
    if @profit_hunter.nil?
      ph_config = extract_profit_hunter_config(orchestrator_config)
      if ph_config
        @profit_hunter = Trading::ProfitHunter.new(ph_config)
        @profit_hunter_last_pnl = {} # track cumulative PnL per strategy for delta calculation
        log_info("Profit hunter initialized for continuous mode", session_id: session_id)
      end
    end

    # Launch independent runners for each strategy
    strategies.each do |strategy|
      opts = { "tick_interval" => strategy["tick_interval_seconds"] || tick_interval }
      opts["begins_at"] = strategy["begins_at"] if strategy["begins_at"]
      opts["ends_at"] = strategy["ends_at"] if strategy["ends_at"]
      TradingStrategyRunnerJob.perform_async(strategy["id"], session_id, opts)
    end
    log_info("Launched #{strategies.size} independent strategy runners", session_id: session_id)

    consecutive_status_failures = 0

    # Supervision loop
    loop do
      break if self.class.shutdown_requested?
      break if cancel_requested?(session_id)
      break if completion_requested?(session_id)

      # Write adaptive heartbeat BEFORE periodic tasks so orphan recovery
      # knows the orchestrator is alive even during expensive operations.
      write_orchestrator_heartbeat!(session_id, lease_seconds: next_operation_lease)

      # Check session status — tolerate transient failures (backend restart,
      # circuit breaker) by waiting for consecutive failures before exiting.
      status = check_status(session_id)
      if status.nil?
        consecutive_status_failures += 1
        if consecutive_status_failures >= 5
          log_warn("#{consecutive_status_failures} consecutive status failures — pausing for recovery",
            session_id: session_id)
          break
        end
        log_info("Status check failed (#{consecutive_status_failures}/5), retrying next cycle",
          session_id: session_id)
        sleep(ORCHESTRATOR_POLL_INTERVAL)
        next
      else
        consecutive_status_failures = 0
      end
      break if status.dig("data", "status").in?(%w[cancelled failed completed])

      # Check time-based expiry
      ends_at = status.dig("data", "ends_at")
      if ends_at && Time.parse(ends_at) <= Time.current
        log_info("Session time limit reached", session_id: session_id)
        break
      end

      # Max duration enforcement (safety valve for sessions without ends_at)
      max_dur = orchestrator_config["max_duration_minutes"]
      if max_dur && @session_started_at && (Time.now - @session_started_at) > max_dur.to_i * 60
        log_info("Max duration #{max_dur}m reached — completing session", session_id: session_id)
        break
      end

      # Zero-activity early termination for continuous sessions
      # Skip the first 5 minutes to allow strategies time to start up
      if @session_started_at && (Time.now - @session_started_at) > 300
        current_metrics = status.dig("data", "metrics") || {}
        current_signals = current_metrics["signals_total"].to_i
        current_positions = current_metrics["positions_opened"].to_i
        @last_activity_signals ||= 0
        @last_activity_positions ||= 0
        @zero_activity_cycles ||= 0

        if current_signals > @last_activity_signals || current_positions > @last_activity_positions
          @zero_activity_cycles = 0
          @last_activity_signals = current_signals
          @last_activity_positions = current_positions
        else
          @zero_activity_cycles += 1
          # 10 consecutive supervision cycles (~5 min at 30s interval) with no new activity
          if @zero_activity_cycles >= 10
            log_info("#{@zero_activity_cycles} consecutive zero-activity cycles — completing session",
              session_id: session_id, signals: current_signals, positions: current_positions)
            break
          end
        end
      end

      # Check if all strategies are decommissioned
      active_count = (status.dig("data", "active_strategy_count") || strategies.size).to_i
      if active_count == 0
        log_info("All strategies decommissioned — ending session", session_id: session_id)
        break
      end

      # Lifecycle decisions (evolution, promotion, pruning, rebalancing) are now
      # handled by Ralph-loop decision engines (Session Manager, Portfolio Manager).
      # The worker supervision loop only handles session-level operational concerns.

      # Aggregate session metrics from all strategy runners
      aggregate_session_metrics!(session_id, strategies)

      # Profit Hunter: assess + hunt cycle (non-fatal, like rebalancing)
      if @profit_hunter
        begin
          run_profit_hunter_cycle!(session_id, strategies)
        rescue StandardError => e
          log_warn("Profit hunter cycle failed (non-fatal): #{e.message}", session_id: session_id)
        end
      end

      # Periodic: dispatch learning extraction
      dispatch_learning_extraction!(strategies.map { |s| s["id"] })

      # Renew lock
      renew_lock_if_needed!

      # Interruptible sleep for supervision interval
      deadline = Time.now + ORCHESTRATOR_POLL_INTERVAL
      while Time.now < deadline
        break if self.class.shutdown_requested? || cancel_requested?(session_id) || completion_requested?(session_id)
        sleep([1.0, deadline - Time.now].min)
      end
    end

    # Shutdown exit: skip finalize for recovery
    if self.class.shutdown_requested?
      log_info("Shutdown requested, skipping finalize for recovery", session_id: session_id)
      return { shutdown: true, session_id: session_id }
    end

    # Profit Hunter reflection (before finalize, mirrors fixed_ticks pattern)
    if @profit_hunter
      reflection = @profit_hunter.reflect!
      log_info("Profit hunter reflect: #{reflection[:hypotheses_confirmed]} confirmed, " \
               "#{reflection[:hypotheses_rejected]} rejected, #{reflection[:total_pruned]} pruned",
        session_id: session_id)
      save_profit_hunter_reflection!(session_id, reflection)
    end

    # Finalize
    log_info("Finalizing continuous training session", session_id: session_id)
    finalize = api_client.post_with_circuit_breaker("/api/v1/internal/trading/training_finalize", {
      session_id: session_id
    }, circuit_breaker: :trading_training)

    if finalize["success"]
      log_info("Continuous training session completed", session_id: session_id)
    else
      log_warn("Finalize returned error", error: finalize["error"])
    end

    { completed: true, session_id: session_id, mode: "continuous" }
  rescue StandardError => e
    log_error("Continuous orchestrator failed", e, session_id: session_id)
    # Pause instead of fail — transient errors (circuit breaker, backend restart)
    # should not permanently kill the session. Orphan recovery or the overseer
    # will handle resume/cancel/complete decisions.
    begin
      pause_session!(session_id, "Orchestrator error: #{e.message}")
    rescue StandardError
      fail_session!(session_id, e.message)
    end
    raise
  end

  # Aggregate session-level metrics from individual strategy runners.
  # Called every supervision cycle (60s) to keep session metrics current.
  # Uses the training_tick_complete endpoint which derives all metrics
  # (signals, orders, positions, P&L, LLM cost) from DB records.
  def aggregate_session_metrics!(session_id, strategies)
    @aggregate_tick_counter = (@aggregate_tick_counter || 0) + 1

    trading_data_fetcher.training_tick_complete(
      session_id: session_id,
      tick_num: @aggregate_tick_counter,
      tick_results: []
    )
  rescue StandardError => e
    log_warn("Metrics aggregation failed (non-fatal): #{e.message}", session_id: session_id)
  end

  # Run one profit hunter assess + hunt cycle using per-strategy state from the server.
  # Each supervision cycle (~30s) acts as a virtual "tick" for the ProfitHunter.
  # The @aggregate_tick_counter is reused as tick_num for interval calculations.
  def run_profit_hunter_cycle!(session_id, strategies)
    # Fetch per-strategy state from the server
    raw_states = trading_data_fetcher.fetch_session_strategy_states(session_id: session_id)
    states = (raw_states.is_a?(Array) ? raw_states : raw_states["states"] || [])
    return if states.empty?

    # Convert cumulative PnL to deltas (ProfitHunter accumulates internally)
    @profit_hunter_last_pnl ||= {}
    ph_states = states.map do |s|
      sid = s["id"] || s[:id]
      cumulative_pnl = (s["pnl_delta"] || s[:pnl_delta]).to_f
      last_pnl = @profit_hunter_last_pnl[sid] || 0.0
      delta = cumulative_pnl - last_pnl
      @profit_hunter_last_pnl[sid] = cumulative_pnl

      {
        id: sid,
        type: s["type"] || s[:type],
        pair: s["pair"] || s[:pair],
        signals_count: (s["signals_count"] || s[:signals_count]).to_i,
        pnl_delta: delta,
        allocated_capital: (s["allocated_capital"] || s[:allocated_capital]).to_f
      }
    end

    tick_num = @aggregate_tick_counter

    # Assess: fast-prune zero-performers
    assessment = @profit_hunter.assess_tick!(tick_num, ph_states)
    if assessment[:actions]&.include?(:fast_prune) && assessment[:prune_ids].any?
      execute_continuous_prune!(session_id, assessment[:prune_ids])
      log_info("Profit hunter pruned #{assessment[:prune_ids].size} strategies " \
               "(reserve: $#{@profit_hunter.reserve_capital.round(2)})",
        session_id: session_id, tick: tick_num)
    end

    # Hunt: deploy new strategy/market combinations on hunt interval ticks
    if (tick_num % (@profit_hunter.config[:hunt_interval] || 5)).zero?
      hunt_result = execute_profit_hunt!(session_id, tick_num, strategies, available_markets: @discovered_markets || [])
      if hunt_result && hunt_result[:new_strategies]&.any?
        # In continuous mode, launch a runner job for each newly deployed strategy
        hunt_result[:new_strategies].each do |new_strategy|
          new_sid = new_strategy["id"]
          tick_interval = new_strategy["tick_interval_seconds"] || ORCHESTRATOR_POLL_INTERVAL
          TradingStrategyRunnerJob.perform_async(new_sid, session_id, { "tick_interval" => tick_interval })
          strategies << new_strategy
        end
        log_info("Profit hunter deployed #{hunt_result[:new_strategies].size} new strategies " \
                 "(reserve: $#{@profit_hunter.reserve_capital.round(2)})",
          session_id: session_id, tick: tick_num)
      end
    end
  end

  # Prune strategies in continuous mode via the prune_strategy endpoint.
  # Unlike fixed_ticks, we don't manage in-memory arrays — runners stop themselves
  # when the strategy is decommissioned.
  def execute_continuous_prune!(session_id, prune_ids)
    prune_ids.each do |sid|
      api_client.post_with_circuit_breaker(
        "/api/v1/internal/trading/prune_strategy",
        { strategy_id: sid },
        circuit_breaker: :trading_training
      )
      log_info("Continuous prune: decommissioned strategy #{sid}", session_id: session_id)
    rescue StandardError => e
      log_warn("Continuous prune failed for strategy #{sid}: #{e.message}", session_id: session_id)
    end
  end

  # Mid-session parameter evolution cycle
  # Write an adaptive orchestrator heartbeat via direct API call (not DataFetcher)
  # so lease_seconds reaches the server. The lease tells orphan recovery how long
  # to wait before declaring the orchestrator dead.
  def write_orchestrator_heartbeat!(session_id, lease_seconds: 180)
    api_client.post_with_circuit_breaker(
      "/api/v1/internal/trading/training_tick_complete",
      {
        session_id: session_id,
        tick_num: @aggregate_tick_counter || 0,
        tick_results: [],
        lease_seconds: lease_seconds
      },
      circuit_breaker: :trading_training
    )
  rescue StandardError => e
    log_warn("Orchestrator heartbeat failed (non-fatal): #{e.message}", session_id: session_id)
  end

  # Calculate lease duration for the heartbeat.
  # With lifecycle decisions moved to Ralph-loop engines, the supervision loop
  # only runs lightweight operations (metrics aggregation, heartbeat).
  def next_operation_lease
    ORCHESTRATOR_POLL_INTERVAL * 2 # 60s — generous margin for metrics aggregation
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

    # Resume path: if strategies already exist, skip setup and go to tick loop.
    # Check started_at and strategy_count to catch sessions that set up strategies
    # but crashed before the first tick completed (completed_ticks still 0).
    if config["completed_ticks"].to_i > 0 || config["started_at"].present? || config["strategy_count"].to_i > 0 || config["status"] == "running"
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

    # Transition to initializing — makes setup phase visible to users
    initialize_training_setup!(session_id)

    # Force-renew lock before each expensive phase so the runner sees a fresh TTL
    # and doesn't mistake a long-running setup for a dead job.
    force_renew_lock!

    # Phase 1: Discover markets (3-step: config → worker fetch → backend process)
    update_timeline(session_id, "Discovering markets from #{venue_slug}...")
    market_count_target = config["market_count"] || 5

    # Phase 1a: Get discovery config from backend (fast DB reads, no venue API calls)
    discovery_config = @data_fetcher.venue_discovery_config(
      session_id: session_id,
      venue_slug: venue_slug,
      market_count: market_count_target,
      config: session_config
    )

    if discovery_config["mode"] == "backtest"
      # Backtest: backend already ran discovery (DB-only, fast)
      markets = discovery_config["markets"] || []
      learning_context = discovery_config["learning_context"]
    else
      # Phase 1b-1c: Fetch and process markets with progressive expansion
      fetcher = Trading::VenueMarketFetcher.new(discovery_config)
      markets = []
      learning_context = nil
      base_limit = discovery_config["fetch_limit"] || 100

      MAX_DISCOVERY_ATTEMPTS.times do |attempt|
        return nil if cancelled?(session_id)

        current_offset = attempt * base_limit
        current_min_volume = attempt.zero? ? (discovery_config["fetch_min_volume"] || 0) : 0

        if attempt > 0
          log_info("Expanding market search (attempt #{attempt + 1}/#{MAX_DISCOVERY_ATTEMPTS}, offset #{current_offset})", session_id: session_id)
          sleep(DISCOVERY_RETRY_DELAY)
        end

        update_timeline(session_id, attempt.zero? ? "Fetching markets from #{venue_slug} API..." : "Expanding market search (attempt #{attempt + 1})...")
        force_renew_lock!

        raw_markets = fetcher.fetch_markets(
          venue_slug,
          series_list: discovery_config["series_list"] || [],
          limit: base_limit,
          min_volume: current_min_volume,
          event_tickers: attempt.zero? ? (discovery_config["event_tickers"] || []) : [],
          offset: current_offset
        )
        log_info("Fetched #{raw_markets.size} raw markets from venue API (attempt #{attempt + 1}, offset #{current_offset})", session_id: session_id)

        if raw_markets.empty?
          log_info("Venue returned no markets at offset #{current_offset}, stopping expansion", session_id: session_id)
          break
        end

        # Phase 1c: Send raw markets to backend for filtering/scoring/registration (fast)
        force_renew_lock!
        update_timeline(session_id, "Processing #{raw_markets.size} markets...")
        discovery = @data_fetcher.process_raw_markets(
          session_id: session_id,
          venue_slug: venue_slug,
          raw_markets: raw_markets,
          market_count: market_count_target,
          config: session_config,
          neg_risk_event_map: fetcher.neg_risk_event_map
        )
        markets = discovery["markets"] || []
        learning_context = discovery["learning_context"]

        break if markets.any?
      end
    end

    # Post-discovery cap: venue APIs return more contracts than market_count
    # (e.g., 2 event groups → 6 contracts). max_markets trims to exact count.
    max_markets = session_config["max_markets"]&.to_i
    if max_markets && markets.size > max_markets
      total_before_cap = markets.size
      markets = markets.first(max_markets)
      log_info("Capped markets to #{max_markets} (from #{total_before_cap})", session_id: session_id)
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

    # Stash discovered markets for profit hunter mid-session hunting
    @discovered_markets = symbolized_markets

    affinity_result = Trading::MarketAffinity.filter_assignments(
      markets: symbolized_markets,
      strategy_types: strategy_types,
      learning_context: symbolized_learning,
      venue_type: discovery_config["venue_type"]
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

    # Phase 2.5: Profit Hunter planning (opt-in)
    profit_hunter_config = extract_profit_hunter_config(session_config)
    if profit_hunter_config
      @profit_hunter = Trading::ProfitHunter.new(profit_hunter_config)
      plan = profit_hunter_plan!(session_id, session_config, assignments, strategy_types)
      if plan
        assignments = plan[:assignments] if plan[:assignments]
        initial_balance = plan[:adjusted_balance] if plan[:adjusted_balance]
        log_info("Profit hunter plan: #{plan[:exploitation_types]&.size || 0} exploit, " \
                 "#{plan[:exploration_types]&.size || 0} explore, " \
                 "reserve $#{@profit_hunter.reserve_capital.round(2)}", session_id: session_id)
      end
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
    # Allocate capital per strategy type first (equal share per type), then
    # subdivide within each type. This prevents types with many market matches
    # from starving types with fewer matches.
    grouped = assignments.group_by { |a| a[:strategy_type] }
    per_type_capital = (initial_balance / grouped.size).round(2)

    # Within each type, drop assignments that would fall below the minimum
    # tradeable capital, keeping the best candidates (sorted by volume proxy
    # via assignment order which reflects discovery ranking).
    sized_assignments = []
    grouped.each do |stype, type_assignments|
      per_strategy = (per_type_capital / type_assignments.size).round(2)
      if per_strategy < MIN_STRATEGY_CAPITAL
        # Too many markets for this type — keep only the top N that meet the minimum
        max_strategies = (per_type_capital / MIN_STRATEGY_CAPITAL).floor
        type_assignments = type_assignments.first(max_strategies)
        per_strategy = (per_type_capital / type_assignments.size).round(2) if type_assignments.any?
      end
      type_assignments.each { |a| a[:allocated_capital] = per_strategy }
      sized_assignments.concat(type_assignments)
      log_info("Capital allocation: #{stype} → #{type_assignments.size} strategies @ $#{per_strategy}/ea " \
               "(type budget: $#{per_type_capital})", session_id: session_id)
    end
    assignments = sized_assignments

    # Batch by strategy type to ensure uniform per_strategy_capital within
    # each batch (server-side uses per_strategy_capital * batch.size as budget).
    strategies = []
    batch_num = 0
    type_grouped = assignments.group_by { |a| a[:strategy_type] }
    total_batches = type_grouped.sum { |_, ta| (ta.size.to_f / STRATEGY_BATCH_SIZE).ceil }

    type_grouped.each do |_stype, type_assignments|
      capital = type_assignments.first[:allocated_capital]
      type_assignments.each_slice(STRATEGY_BATCH_SIZE) do |batch|
        return nil if cancelled?(session_id)
        force_renew_lock! # Each batch takes 30-60s; keep lock fresh for runner
        batch_num += 1
        update_timeline(session_id, "Creating strategies batch #{batch_num}/#{total_batches.to_i}...")
        result = @data_fetcher.create_training_strategies(
          session_id: session_id,
          venue_slug: venue_slug,
          assignments: batch,
          per_strategy_capital: capital
        )
        strategies.concat(result["strategies"] || [])
      end
    end
    log_info("Created #{strategies.size} strategies across #{type_grouped.size} types", session_id: session_id)

    if strategies.empty?
      fail_session!(session_id, "No strategies created — all #{assignments.size} assignments failed")
      return nil
    end

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

  # Fast cancel check: uses Redis pub/sub listener first (instant),
  # falls back to HTTP status check if listener isn't available.
  def cancel_requested?(session_id)
    return true if @session_event_listener&.cancelled?
    false
  end

  def completion_requested?(session_id)
    return true if @session_event_listener&.completion_requested?
    false
  end

  def cancelled?(session_id)
    return true if cancel_requested?(session_id)

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

  # Batch-fetch contexts for all strategies in one request.
  # Uses HTTP batch (with ticker cache + eager loading) → individual fetches fallback.
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
  # Delegates to the shared StrategyEvaluator service (extracted for reuse
  # by both batch loop and independent TradingStrategyRunnerJob).
  def evaluate_strategy(strategy_id, context)
    @strategy_evaluator ||= Trading::StrategyEvaluator.new(
      llm_client: training_llm_client,
      data_fetcher: trading_data_fetcher
    )
    result = @strategy_evaluator.evaluate(
      strategy_id, context,
      price_cache: @tick_price_cache,
      graph_cache: @graph_cache
    )
    if result["error"]
      log_warn("Strategy tick failed", strategy_id: strategy_id, error: result["error"])
    end
    result
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
    cutoff = since || @last_extraction_at || @session_started_at || 90.seconds.ago
    cutoff_iso = cutoff.is_a?(String) ? cutoff : cutoff.iso8601
    TradingLearningExtractionJob.perform_async(strategy_ids, cutoff_iso)
    @last_extraction_at = Time.now
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

  # ─── Profit Hunter helpers ──────────────────────────────────

  # Extract profit_hunter config from session config. Returns nil if not enabled.
  def extract_profit_hunter_config(session_config)
    return nil unless session_config["profit_hunter_enabled"]

    {
      reserve_pct: session_config["profit_hunter_reserve_pct"],
      fast_prune_ticks: session_config["profit_hunter_fast_prune_ticks"],
      hunt_interval: session_config["profit_hunter_hunt_interval"],
      max_experiments: session_config["profit_hunter_max_experiments"],
      llm_budget_usd: session_config["profit_hunter_llm_budget_usd"]
    }.compact
  end

  # Decision Point 1: Plan session using cross-session intelligence
  def profit_hunter_plan!(session_id, session_config, assignments, strategy_types)
    venue_slug = session_config["venue_slug"]

    # Fetch scorecards from server (Phase 3 cross-session intelligence)
    scorecards = @data_fetcher.fetch_strategy_intelligence(session_id: session_id, venue_slug: venue_slug)

    plan = @profit_hunter.plan_session!(
      scorecards: scorecards,
      available_types: strategy_types,
      venue_slug: venue_slug
    )

    # Apply reserve: hold back capital by reducing initial balance
    initial_balance = (session_config["initial_balance"] || 100_000).to_f
    reserve_pct = plan[:reserve_pct] || @profit_hunter.config[:reserve_pct]
    reserve_amount = (initial_balance * reserve_pct).round(2)
    @profit_hunter.instance_variable_set(:@reserve_capital, reserve_amount)

    # If plan has capital allocation, reweight assignments
    if plan[:capital_allocation]&.any?
      # Filter assignments to planned types only, keeping affinity results
      planned_types = plan[:strategy_types]
      filtered = assignments.select { |a| planned_types.include?(a[:strategy_type] || a["strategy_type"]) }
      # Fall back to original if filtering removes everything
      filtered = assignments if filtered.empty?

      plan[:assignments] = filtered
    end

    plan[:adjusted_balance] = initial_balance - reserve_amount
    plan
  rescue StandardError => e
    log_warn("Profit hunter plan failed (non-fatal, using defaults): #{e.message}", session_id: session_id)
    nil
  end

  # Build per-strategy state hash for ProfitHunter from tick results
  def build_profit_hunter_state(tick_results, strategies, contexts_by_id)
    strategy_map = strategies.each_with_object({}) { |s, h| h[s["id"]] = s }

    tick_results.filter_map do |result|
      sid = result["strategy_id"] || result[:strategy_id]
      next unless sid

      strategy = strategy_map[sid]
      next unless strategy

      context = contexts_by_id[sid] || contexts_by_id[sid.to_s]
      allocated = context&.dig("strategy", "allocated_capital").to_f

      signals = result["signals_generated"].to_i
      pnl = result["pnl_delta"].to_f

      {
        id: sid,
        type: strategy["type"],
        pair: strategy["pair"],
        signals_count: signals,
        pnl_delta: pnl,
        allocated_capital: allocated
      }
    end
  end

  # Execute fast prune: decommission zero-performing strategies via prune_strategy endpoint.
  # Closes open positions and releases capital back to the portfolio.
  def execute_fast_prune!(session_id, prune_ids, strategies, all_strategy_ids)
    prune_ids.each do |sid|
      result = api_client.post_with_circuit_breaker(
        "/api/v1/internal/trading/prune_strategy",
        { strategy_id: sid },
        circuit_breaker: :trading_training
      )

      all_strategy_ids.delete(sid)
      strategies.reject! { |s| s["id"] == sid }
      @strategy_evaluator&.evict(sid)
      @cold_context_cache.delete(sid.to_s)

      released = result.dig("data", "released_capital").to_f
      log_info("Fast prune: strategy #{sid} (released $#{released.round(2)})", session_id: session_id)
    rescue StandardError => e
      log_warn("Fast prune failed for strategy #{sid}: #{e.message}", session_id: session_id)
    end
  end

  # Execute profit hunt: deploy new strategies and rotate dead markets
  def execute_profit_hunt!(session_id, tick_num, strategies, available_markets: [])
    ph_state = strategies.map do |s|
      sid = s["id"]
      {
        id: sid,
        type: s["type"],
        pair: s["pair"],
        signals_count: 0, # Will be filled from @type_performance in profit hunter
        pnl_delta: 0.0
      }
    end

    hunt_result = @profit_hunter.hunt!(tick_num, ph_state, available_markets: available_markets)

    return hunt_result if hunt_result[:skip_reason]

    new_strategies = []

    # Deploy new strategy/market combinations
    if hunt_result[:new_assignments]&.any?
      session_status = check_status(session_id)
      venue_slug = session_status&.dig("data", "config", "venue_slug")

      hunt_result[:new_assignments].each do |assignment|
        result = @data_fetcher.create_training_strategies(
          session_id: session_id,
          venue_slug: venue_slug,
          assignments: [{ pair: assignment[:pair], strategy_type: assignment[:strategy_type] }],
          per_strategy_capital: assignment[:capital]
        )
        created = result["strategies"] || []
        new_strategies.concat(created)

        log_info("Hunt: deployed #{assignment[:strategy_type]} on #{assignment[:pair]} " \
                 "(hypothesis: #{assignment[:hypothesis]}, capital: $#{assignment[:capital]})",
          session_id: session_id)
      rescue StandardError => e
        log_warn("Hunt deployment failed for #{assignment[:strategy_type]} on #{assignment[:pair]}: #{e.message}",
          session_id: session_id)
        @profit_hunter.release_experiment_slot(assignment[:capital])
      end
    end

    # Log market rotations (informational — actual rotation happens via new deployments)
    hunt_result[:market_rotations]&.each do |rotation|
      log_info("Hunt: dead market #{rotation[:dead_pair]} → replacement #{rotation[:replacement_pair]} " \
               "(#{rotation[:reason]})", session_id: session_id)
    end

    hunt_result[:new_strategies] = new_strategies
    hunt_result
  rescue StandardError => e
    log_warn("Profit hunt failed (non-fatal): #{e.message}", session_id: session_id)
    nil
  end

  # Save profit hunter reflection data via shared memory
  def save_profit_hunter_reflection!(session_id, reflection)
    session_status = check_status(session_id)
    venue_slug = session_status&.dig("data", "config", "venue_slug") || "unknown"

    # Update profitability heatmap in shared memory
    @data_fetcher.write_profit_hunter_heatmap(
      venue_slug: venue_slug,
      heatmap_updates: reflection[:heatmap_updates],
      session_id: session_id
    )
  rescue StandardError => e
    log_warn("Profit hunter reflection save failed (non-fatal): #{e.message}", session_id: session_id)
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

  def initialize_training_setup!(session_id)
    api_client.post("/api/v1/internal/trading/initialize_training_setup", {
      session_id: session_id
    })
  rescue StandardError => e
    log_warn("Failed to transition to initializing", session_id: session_id, error: e.message)
  end

  # Pause session so it can be auto-resumed by the training runner.
  # Used during graceful shutdown instead of fail_session! so work isn't lost.
  # Uses a dedicated short-timeout connection to avoid being blocked by the
  # circuit breaker or connection pool during Sidekiq shutdown.
  def pause_session!(session_id, message)
    base_url = ENV.fetch('BACKEND_API_URL', 'http://localhost:3000')
    conn = Faraday.new(url: base_url) do |f|
      f.options.timeout = 10
      f.options.open_timeout = 5
      f.request :json
      f.response :json
      f.adapter Faraday.default_adapter
    end

    response = conn.post("/api/v1/internal/trading/pause_training_session") do |req|
      req.headers['Authorization'] = "Bearer #{WorkerJwt.token}"
      req.body = { session_id: session_id, error_message: message }
    end

    unless response.success?
      raise "Pause request failed: HTTP #{response.status}"
    end
  rescue StandardError => e
    log_warn("Failed to pause session", session_id: session_id, error: e.message)
    # Re-raise so the caller can fall back to fail_session!
    raise
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
