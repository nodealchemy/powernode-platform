# Trading Efficiency Audit — Bottleneck Analysis

**Date:** 2026-03-20
**Scope:** Full trading pipeline — signal generation, evaluation, order execution, position management, risk checks
**Status:** Remediated — all 13 bottlenecks addressed (2026-03-20)

---

## 1. Executive Summary

**13 bottlenecks** identified across 3 severity tiers, plus **5 positive patterns** already in place.

| Severity | Count | Theme |
|----------|-------|-------|
| Critical | 4 | Will cause missed trades in live/arb scenarios |
| High | 4 | Degrade throughput under load |
| Medium | 5 | Incremental latency and resource waste |

**Estimated worst-case tick latency:** 5+ minutes for a training session with 10 AI strategies — each AI strategy evaluation takes 30–120s (C2) and they run sequentially (C3) with a 2-second inter-strategy delay.

**Core theme:** The system is optimized for correctness over latency. This is appropriate for paper trading and training sessions but will miss real arbitrage opportunities where windows are sub-second (prediction markets) to low-seconds (CEX/DEX spreads).

---

## 2. Critical Bottlenecks (Will Cause Missed Trades)

### C1: Sequential Multi-Leg Execution

**File:** `extensions/trading/server/app/services/trading/multi_leg_executor.rb:29-48`
**Latency impact:** 15–25s per 3-leg arbitrage

The `execute_all_legs!` method processes legs sequentially via `.each_with_index` with a blocking `execute_leg` call per iteration. Each leg waits for the previous to complete before starting.

```ruby
# Lines 29-48
legs.each_with_index do |leg, idx|
  result = execute_leg(leg, timeout: timeout)  # Blocking call per leg
  if result[:success]
    filled_legs << result
    orders << result[:order]
  else
    unwound = unwind_legs!(filled_legs)  # Also sequential (intentionally — reverse order)
    return { success: false, error: "Leg #{idx + 1} failed: #{result[:error]}", ... }
  end
end
```

For a 3-leg arbitrage with a 5s per-leg adapter timeout, minimum execution time is 15s when it could be ~5s with concurrent submission. In prediction markets where arb windows collapse in <1s, this guarantees the opportunity is gone before leg 2 even starts.

**Note:** The `unwind_legs!` method (lines 119–164) is correctly sequential — unwinding must respect reverse order for hedge integrity.

---

### C2: LLM Calls in Critical Trading Path

**File:** `worker/app/services/trading/evaluators/agent_ensemble.rb:140-302`
**Latency impact:** 30–120s per AI strategy tick

The agent ensemble evaluator makes multiple LLM calls per strategy evaluation. It **does** use Ruby threads to parallelize analyst opinions (lines 140–166) and debate rounds (lines 199–271), but the overall pipeline is still heavyweight:

| Phase | Lines | Parallelism | Time |
|-------|-------|-------------|------|
| Analyst opinions (5 roles) | 140–166 | Threaded (up to `@max_llm_calls`) | 10–30s |
| Debate rounds (bull/bear) | 199–271 | Threaded (2 per round) | 10–60s |
| Synthesis decision | 273–302 | **Single blocking call** | 5–15s |

Each thread joins with a 30s timeout (`param("analyst_timeout_seconds", 30)` at line 155). Even with parallelization, the three serial phases sum to 30–120s — an eternity for time-sensitive trading.

**Mitigating factor:** Ruby's GIL doesn't block here because LLM calls are I/O-bound (network wait), so the thread parallelism is effective for the analyst and debate phases.

---

### C3: Single-Threaded Strategy Ticking

**File:** `worker/app/jobs/trading_training_session_job.rb:529-554`
**Latency impact:** 320s+ for 10 AI strategies per tick

Strategies are evaluated sequentially in two `.each` loops — first classic strategies (fast, no delay), then AI strategies with `INTER_STRATEGY_DELAY = 2` seconds between each:

```ruby
# Lines 529-538 — Classic strategies (fast)
classic_ids.each do |sid|
  break if cancel_requested?(session_id)
  result = evaluate_strategy(sid, context)
  tick_results << result
end

# Lines 539-554 — AI strategies (slow, with delay)
ai_ids.each_with_index do |sid, idx|
  break if cancel_requested?(session_id)
  result = evaluate_strategy(sid, context)  # 30-120s per call (C2)
  tick_results << result
  sleep(dry_run ? 0.5 : INTER_STRATEGY_DELAY) if idx < ai_ids.size - 1  # +2s between
end
```

With 10 AI strategies at 30s each (optimistic C2 estimate) plus 2s inter-strategy delay: `(30 + 2) × 10 = 320s`. Pessimistic: `(120 + 2) × 10 = 1,220s` (~20 minutes).

**Note:** `trading_strategy_runner_job.rb` (257 lines) already implements a per-strategy concurrent runner pattern as a solution. Its docstring states: "Replaces the monolithic tick loop in TradingTrainingSessionJob for continuous-mode sessions."

---

### C4: Hard Sleep-Based Rate Limiting

**Files:** Multiple adapters and fetcher services
**Latency impact:** 0.5–2.5s per order; 50s+ per 100 series

| File | Location | Sleep Duration | Context |
|------|----------|---------------|---------|
| `polymarket_adapter.rb:101` | `submit_order` | `rand(0.5..2.5)` | Paper trading CLOB simulation |
| `kalshi_adapter.rb:259` | Candlestick batch | `RATE_DELAY (0.5s)` | After every 100 tickers |
| `kalshi_adapter.rb:381` | Market pagination | `0.5s` | Between paginated pages |
| `kalshi_adapter.rb:395` | Series probe | `0.5s` | Between series lookups |
| `kalshi_adapter.rb:497` | Event market fetch | `0.5s` | Between event batches |
| `kalshi_adapter.rb:572` | `discover_series` | `0.5s` | Between paginated pages |
| `kalshi_adapter.rb:990` | Paper order | `rand(0.1..0.5)` | Paper trading simulation |
| `venue_market_fetcher.rb:52` | PM event slugs | `POLYMARKET_RATE_DELAY (0.7s)` | Between event slug fetches |
| `venue_market_fetcher.rb:80,88` | Kalshi iteration | `RATE_DELAY (0.5s)` | Between event/series fetches |
| `venue_market_fetcher.rb:239` | Kalshi pagination | `0.5s` | Between pages |

All rate limiting uses blocking `sleep()` calls. For Kalshi market discovery across N series: `N × 0.5s`. With 100 series, that's 50s of pure sleep time — not counting the actual API call latency.

**Nuance:** Polymarket's `submit_order` sleep simulates CLOB matching delay for paper trading — it's intentional simulation latency, not rate limiting. The `CLOB_RATE_DELAY` (0.7s) is used for fetch caching, which is correct.

---

## 3. High-Impact Issues (Degrade Throughput)

### H1: Position Update Loop Without Batching

**File:** `extensions/trading/server/app/services/trading/strategy_engine.rb:161-196`
**Impact:** 50–100 individual UPDATE queries per tick

The `update_positions` method iterates open positions with `.find_each`, calling `position.update_mark_price!` individually. Additionally, closed position broadcasts fire individually within the loop:

```ruby
# Lines 161-196
strategy.open_positions.includes(:venue).find_each do |position|
  position.update_mark_price!(market_data[:last_price])  # Individual UPDATE per position

  if position.stop_loss_triggered?(market_data[:last_price])
    close_position!(position, ...)
    broadcast_service&.broadcast_position_closed!(strategy, position.reload)  # Individual broadcast
  elsif position.take_profit_triggered?(market_data[:last_price])
    close_position!(position, ...)
    broadcast_service&.broadcast_position_closed!(strategy, position.reload)  # Individual broadcast
  else
    updated_positions << position
  end
end

# Lines 184-195 — Open position broadcasts ARE batched (good)
TradingChannel.broadcast_to_account(..., "positions_updated", { positions: updated_positions.map { ... } })
```

**Mixed pattern:** Open position mark-price broadcasts are correctly batched (lines 184–195), but individual `broadcast_position_closed!` calls (lines 172, 177) and individual `position.reload` calls bypass the `.includes(:venue)` eager load.

---

### H2: Sequential Price Fetching (N+1)

**Files:** `strategy_engine.rb:149-159`, `simulation_runner.rb:129-145`
**Impact:** Duplicate API calls across strategies sharing the same pair

`StrategyEngine.fetch_market_data` makes a single `adapter.fetch_ticker(pair)` call per engine instance. When multiple strategies trade the same pair, each independently fetches the same data:

```ruby
# strategy_engine.rb:149-159
def fetch_market_data
  adapter = venue_adapter
  ticker = adapter.fetch_ticker(strategy.pair)  # One call per strategy instance
  { last_price: ticker[:last_price], bid: ticker[:bid], ... }
end
```

**Positive contrast:** `SimulationRunner` (lines 129–145) correctly solves this with a `ticker_cache` that pre-fetches unique pairs once and passes cached data via `engine.tick!(market_data: ticker_cache[strategy.pair])`. The `StrategyEngine.tick!` method accepts `market_data: nil` — the infrastructure for dedup exists, it's just not used outside simulation/training contexts.

---

### H3: Trading Queue Weight = 2, Shared With 21 Other Queues

**File:** `worker/config/sidekiq.yml:47`
**Impact:** Queue starvation for time-sensitive trading jobs

```yaml
- [trading, 2]  # Trading strategy execution, price feeds, risk monitoring
```

The `trading` queue has weight 2, identical to 21 other queues including `ai_workflows`, `ai_agents`, `ai_execution`, `billing`, `email`, `reports`, etc. With `concurrency: 25` (line 14), Sidekiq distributes workers across queues proportionally — trading jobs compete equally with email delivery and report generation.

There is no separate `trading_critical` queue for time-sensitive operations (order execution, risk alerts) versus batch operations (compounding checks, sweep scans).

---

### H4: Sequential Portfolio Iteration in Batch Jobs

**Files:** 4 jobs with identical patterns
**Impact:** `N × (API_call_latency)` blocking time; ~200s for 100 portfolios at 2s/call

All four batch jobs iterate portfolios sequentially with a blocking HTTP API call per portfolio:

| Job | File | Lines | API Endpoint |
|-----|------|-------|-------------|
| Compounding check | `trading_compounding_check_job.rb` | 13–25 | `POST /internal/trading/check_compounding` |
| Sweep check | `trading_sweep_check_job.rb` | 13–25 | `POST /internal/trading/check_sweep_opportunities` |
| Earnings transfer | `trading_earnings_transfer_job.rb` | 13–25 | `POST /internal/trading/check_earnings_transfers` |
| Overseer cycle | `trading_overseer_cycle_job.rb` | 17–31 | `POST /internal/trading/overseer_decision_cycle` |

All follow the identical pattern:

```ruby
portfolios.each do |portfolio|
  result = api_client.post("/api/v1/internal/trading/...", { portfolio_id: portfolio["id"] })
  # ... process result ...
end
```

No parallelism, no batching, no fan-out into per-portfolio sub-jobs.

---

## 4. Medium-Impact Issues

### M1: Risk Check Overhead Per-Tick (No Debounce on pre_trade)

**Files:** `strategy_engine.rb:31`, `risk_manager_service.rb:44-59`
**Impact:** Redundant risk profile lookups and checks on every tick

`StrategyEngine.tick!` calls `pre_trade_risk_check` on every tick (line 31) without debouncing. This queries the risk profile, checks circuit breakers, counts open positions, and evaluates multiple limits — every single tick, even when nothing has changed.

**Irony:** `RiskManagerService.check_critical_risk!` (lines 44–59) implements a proper 5-second cache-based debounce:

```ruby
# risk_manager_service.rb:49-51 — The correct pattern exists
cache_key = "trading:critical_risk:#{portfolio.id}"
return { skipped: true, reason: "debounced" } if Rails.cache.exist?(cache_key) rescue false
Rails.cache.write(cache_key, true, expires_in: 5.seconds) rescue nil
```

This debounce pattern is not applied to the `pre_trade_risk_check` path in `StrategyEngine`.

---

### M2: Stale Lock Recovery = 15 Minutes

**File:** `worker/app/jobs/trading_training_session_runner_job.rb:18`
**Impact:** Dead training sessions block restart for up to 15 minutes

```ruby
# Line 18
STALE_LOCK_AGE_THRESHOLD = 900  # 15 minutes
```

If a training session job dies (OOM, SIGKILL), the Redis lock persists for up to 15 minutes before the runner considers it stale and allows re-dispatch. A secondary proactive cleanup (line 150) uses a more aggressive 5-minute threshold (`next if lock_age < 300`) but only runs during batch scans.

---

### M3: No Request Deduplication Outside Training Sessions

**File:** `strategy_engine.rb:14-22`, `strategy_execution_job.rb`
**Impact:** Duplicate API calls when multiple trigger paths fire simultaneously

`StrategyEngine.tick!` accepts a `market_data:` parameter for callers to inject pre-fetched data, but:
- No fallback cache for failed fetches
- No dedup key to prevent concurrent ticks from double-fetching
- Each `StrategyExecutionJob` creates its own engine instance and fetches independently

The `SimulationRunner` and `TickPriceCache` solve this for training sessions, but the pattern is not ported to standalone strategy execution.

---

### M4: Broadcast Storm From Position Updates

**File:** `strategy_engine.rb:172,177`
**Impact:** N individual WebSocket broadcasts for N closed positions per tick

Within the `update_positions` loop (H1), each stop-loss or take-profit trigger fires an individual `broadcast_position_closed!` call. If 10 positions hit stop-loss in one tick, that's 10 separate ActionCable broadcasts instead of one batched message.

Open position mark-price updates are correctly batched via `TradingChannel.broadcast_to_account` (lines 184–195), showing the team knows the pattern — it just isn't applied to closures.

---

### M5: P&L Recalculation Every Tick Regardless of Activity

**File:** `strategy_engine.rb:54-56`
**Impact:** Unnecessary computation when no orders were submitted

```ruby
# Lines 54-56
strategy.update!(last_tick_at: Time.current)
strategy.recalculate_pnl!       # Full P&L recalc — even if no trades happened
strategy.update_high_water_mark! # HWM check — even if P&L didn't change
```

These run unconditionally on every tick. For a 100-tick simulation with 10 strategies, that's 1,000 P&L recalculations when P&L only changes on position open/close or material price movement. A simple guard (`skip if no orders this tick AND mark prices unchanged`) would eliminate most calls.

---

## 5. Positive Patterns (What's Working Well)

### P1: TickPriceCache With WS-First, REST-Fallback

**File:** `worker/app/jobs/trading_training_session_job.rb:30`

The `TickPriceCache` class (defined at line 30, instantiated at line 476) provides per-tick price caching during training sessions. It eliminates redundant API calls by caching ticker data across all strategies within a single tick. Tracks `hit_count` and `miss_count` for observability.

---

### P2: WebSocket Streaming With Reference-Counted Lifecycle

**Files:** `extensions/trading/worker/app/services/trading/kalshi_ws_manager.rb`, `polymarket_ws_manager.rb`, `polymarket_ws_client.rb`

Both Kalshi and Polymarket have reference-counted WebSocket managers:

```ruby
# kalshi_ws_manager.rb:29-30,43,77-82
@ref_count = 0
@pair_refs = Hash.new(0)  # pair -> reference count

# On subscribe:
@ref_count += 1

# On unsubscribe:
@ref_count -= 1
if @ref_count <= 0
  disconnect!
  @ref_count = 0
end
```

This ensures WebSocket connections stay alive as long as any session needs them and cleanly disconnect when the last subscriber leaves. Prevents connection thrashing across concurrent training sessions.

---

### P3: Risk Check Debouncing (5s Cache Key)

**File:** `extensions/trading/server/app/services/trading/risk_manager_service.rb:44-59`

`check_critical_risk!` implements a 5-second cache-based debounce scoped per portfolio. Prevents redundant critical risk checks when multiple strategies in the same portfolio tick within the same window.

---

### P4: Position Mark-Price Optimization

**File:** `extensions/trading/server/app/models/trading/position.rb:61-90`

The `update_mark_price!` method skips metadata writes (MFE/MAE tracking) when extremes haven't changed:

```ruby
if mfe_changed || mae_changed
  update!(current_price: price, unrealized_pnl_usd: pnl, metadata: updated_metadata)
else
  update!(current_price: price, unrealized_pnl_usd: pnl)  # Lighter write
end
```

This reduces write amplification by avoiding JSON column updates on every tick.

---

### P5: Redis Pub/Sub for Session Lifecycle Events

**File:** `worker/app/jobs/trading_training_session_job.rb:87-88,250-253`

Training session cancellation uses Redis pub/sub (`SessionEventListener`, channel: `training_session_events`) for immediate signal delivery, with HTTP polling as a fallback. This enables sub-second cancellation propagation without polling overhead.

```ruby
# Line 88
CHANNEL = "training_session_events"
# Line 252
@session_event_listener = SessionEventListener.new(session_id)
@session_event_listener.start!
```

---

## 6. Prioritized Recommendations

### Quick Wins (1–2 days each)

| # | Recommendation | Addresses | Expected Impact |
|---|---------------|-----------|-----------------|
| 1 | **Split `trading` queue** into `trading_critical` (weight 3) and `trading_batch` (weight 1). Route order execution and risk alerts to critical; compounding/sweep/earnings to batch. | H3 | Eliminates queue starvation for time-sensitive jobs |
| 2 | **Batch position mark-price updates** into a single `UPDATE...CASE` query instead of N individual UPDATEs in the `update_positions` loop. | H1 | Reduces DB round-trips from N to 1 per tick |
| 3 | **Extend 5s debounce to `pre_trade_risk_check`** in StrategyEngine, mirroring the pattern in `RiskManagerService.check_critical_risk!`. | M1 | Eliminates redundant risk lookups for same-portfolio strategies |
| 4 | **Guard `recalculate_pnl!`** — skip when no orders were submitted during the tick and mark prices haven't changed materially. | M5 | Eliminates ~90% of unnecessary P&L recalculations |
| 5 | **Reduce `STALE_LOCK_AGE_THRESHOLD`** from 900 → 300 seconds to match the proactive cleanup threshold already in use at line 150. | M2 | Dead sessions recover in 5 min instead of 15 |

### Medium Effort (1–2 weeks)

| # | Recommendation | Addresses | Expected Impact |
|---|---------------|-----------|-----------------|
| 6 | **Thread pool for AI strategy evaluation** in training sessions. Replace the sequential `.each` loop (C3) with a bounded thread pool (e.g., `Concurrent::FixedThreadPool`). The per-strategy runner (`trading_strategy_runner_job.rb`) already demonstrates the concurrent pattern. | C3 | 10 AI strategies in ~120s instead of ~320s |
| 7 | **Port `TickPriceCache` to regular strategy execution** (non-training). Create a shared price cache for `StrategyExecutionJob` instances that tick within the same window. | H2, M3 | Eliminates duplicate API calls across co-ticking strategies |
| 8 | **Replace `sleep()` with async rate limiters.** Use a token bucket or sliding window algorithm backed by Redis. Callers `await` a token instead of blocking the entire thread. | C4 | Reclaims ~50s of blocked thread time per 100-series fetch |
| 9 | **Fan out batch portfolio jobs** into per-portfolio sub-jobs. Replace the sequential `portfolios.each` loop with `portfolios.each { |p| SubJob.perform_async(p["id"]) }`. | H4 | All 4 batch jobs scale linearly with Sidekiq concurrency |

### Architectural (1+ month)

| # | Recommendation | Addresses | Expected Impact |
|---|---------------|-----------|-----------------|
| 10 | **Concurrent multi-leg execution with async HTTP.** Submit all legs simultaneously (e.g., via `Async` or `Typhoeus::Hydra`), then validate fills and unwind partial failures. Requires careful handling of partial-fill scenarios. | C1 | 3-leg arb in ~5s instead of ~15s |
| 11 | **LLM call timeout/cancellation with per-strategy tick budget.** Add a global timer per strategy tick (e.g., 45s) that cancels remaining LLM phases if exceeded. Allow strategies to submit with partial analysis rather than waiting for full ensemble. | C2 | Caps worst-case AI strategy tick at 45s |
| 12 | **Dedicated Sidekiq process for trading queues.** Run a separate Sidekiq process (`-q trading_critical -q trading_batch`) with its own concurrency pool, isolated from AI/billing/email workloads. | H3 | Full isolation — trading throughput unaffected by platform load |
| 13 | **Streaming position update pipeline.** Batch mark-price updates, P&L recalcs, and broadcasts across ALL strategies in a tick into a single SQL + single broadcast. Replace per-strategy `update_positions` with a coordinator that collects all price changes and flushes once. | H1, M4, M5 | One DB round-trip and one broadcast per tick, regardless of strategy count |

---

## Appendix: Files Referenced

| File | Lines | Bottlenecks |
|------|-------|-------------|
| `extensions/trading/server/app/services/trading/multi_leg_executor.rb` | 173 | C1 |
| `extensions/trading/server/app/services/trading/strategy_engine.rb` | 855 | H1, H2, M1, M3, M4, M5 |
| `extensions/trading/server/app/services/trading/risk_manager_service.rb` | 391 | M1, P3 |
| `extensions/trading/server/app/services/trading/simulation_runner.rb` | 365 | H2 (positive contrast) |
| `extensions/trading/server/app/services/trading/live_training_runner.rb` | 3219 | Context |
| `extensions/trading/server/app/models/trading/position.rb` | 127 | P4 |
| `extensions/trading/server/app/services/trading/venue_adapter/prediction_market/polymarket_adapter.rb` | 582 | C4 |
| `extensions/trading/server/app/services/trading/venue_adapter/prediction_market/kalshi_adapter.rb` | 1000+ | C4 |
| `extensions/trading/worker/app/services/trading/venue_market_fetcher.rb` | 401 | C4 |
| `extensions/trading/worker/app/services/trading/kalshi_ws_manager.rb` | — | P2 |
| `extensions/trading/worker/app/services/trading/polymarket_ws_manager.rb` | — | P2 |
| `extensions/trading/worker/app/services/trading/polymarket_ws_client.rb` | — | P2 |
| `worker/app/services/trading/evaluators/agent_ensemble.rb` | 427 | C2 |
| `worker/app/jobs/trading_training_session_job.rb` | 1522 | C3, P1, P5 |
| `worker/app/jobs/trading_strategy_runner_job.rb` | 257 | (solution pattern for C3) |
| `worker/app/jobs/trading_training_session_runner_job.rb` | 162 | M2 |
| `worker/app/jobs/trading_compounding_check_job.rb` | 30 | H4 |
| `worker/app/jobs/trading_sweep_check_job.rb` | 30 | H4 |
| `worker/app/jobs/trading_earnings_transfer_job.rb` | 30 | H4 |
| `worker/app/jobs/trading_overseer_cycle_job.rb` | 46 | H4 |
| `worker/config/sidekiq.yml` | 569 | H3 |

---

## 8. Remediation Status

All 13 bottlenecks addressed across 5 parallel work streams on 2026-03-20.

### Critical (C1–C4)

| ID | Bottleneck | Fix | Files |
|----|-----------|-----|-------|
| C1 | Sequential multi-leg execution | Concurrent `Thread.new` per leg with join + timeout budget | `multi_leg_executor.rb` |
| C2 | No LLM call timeout budget | 45s tick budget with `MIN_SYNTHESIS_TIMEOUT` reserve; debate skipped when budget low | `agent_ensemble.rb` |
| C3 | Sequential AI strategy evaluation | `each_slice(3)` batched threading replaces sequential loop + sleep | `trading_training_session_job.rb` |
| C4 | Fixed-sleep rate limiting | Redis-backed token bucket via atomic Lua script | `token_bucket_rate_limiter.rb`, `kalshi_adapter.rb`, `venue_market_fetcher.rb` |

### High (H1–H4)

| ID | Bottleneck | Fix | Files |
|----|-----------|-----|-------|
| H1 | N+1 position mark-price UPDATEs | `BatchPositionUpdater` flushes all via single `UPDATE...CASE` SQL | `batch_position_updater.rb`, `strategy_engine.rb` |
| H2 | Redundant price fetches across runners | `SharedPriceCache` (Redis, 5s TTL) shared between concurrent runners | `shared_price_cache.rb`, `trading_strategy_runner_job.rb` |
| H3 | Single trading queue contention | Split into `trading_critical` (weight 3) + `trading_batch` (weight 1) + dedicated Sidekiq process config | `sidekiq.yml`, `sidekiq_trading.yml` |
| H4 | Sequential portfolio iteration in batch jobs | Fan-out pattern: dispatch per-portfolio/account `perform_async` | `trading_compounding_check_job.rb`, `trading_sweep_check_job.rb`, `trading_earnings_transfer_job.rb`, `trading_overseer_cycle_job.rb` |

### Medium (M1–M5)

| ID | Bottleneck | Fix | Files |
|----|-----------|-----|-------|
| M1 | Redundant pre-trade risk checks | 5s cache-based debounce on `pre_trade_risk_check` | `strategy_engine.rb` |
| M2 | Stale lock threshold too conservative | `STALE_LOCK_AGE_THRESHOLD` reduced from 900s to 300s | `trading_training_session_runner_job.rb` |
| M3 | Price cache misses for shared pairs | SharedPriceCache stores market data after fetch_context | `trading_strategy_runner_job.rb` |
| M4 | Individual position-closed broadcasts | Collected into array during loop, batch broadcast after | `strategy_engine.rb` |
| M5 | Unconditional PnL recalculation | Guarded behind `orders.any? \|\| @positions_changed` | `strategy_engine.rb` |

### New files created

| File | Purpose |
|------|---------|
| `extensions/trading/server/app/services/trading/batch_position_updater.rb` | Single-SQL position mark-price flush |
| `extensions/trading/server/app/services/trading/token_bucket_rate_limiter.rb` | Redis Lua token bucket rate limiter |
| `worker/app/services/trading/shared_price_cache.rb` | Cross-runner Redis price cache |
| `worker/config/sidekiq_trading.yml` | Dedicated trading Sidekiq process config |
