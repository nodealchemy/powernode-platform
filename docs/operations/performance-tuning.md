# Performance Tuning

> When to use this runbook: tuning Powernode's throughput, latency, and resource usage when capacity planning, investigating slow queries, or hardening for production load.

## Table of Contents

- [Prerequisites](#prerequisites)
- [When to use this](#when-to-use-this)
- [Overview](#overview)
- [Key Performance Targets](#key-performance-targets)
- [Application Performance Monitoring](#application-performance-monitoring)
- [Database Performance](#database-performance)
- [Caching Strategy](#caching-strategy)
- [Redis Tuning](#redis-tuning)
- [Background Worker Tuning](#background-worker-tuning)
- [AI Provider Throughput](#ai-provider-throughput)
- [Frontend Performance](#frontend-performance)
- [Load Testing](#load-testing)
- [Capacity Planning](#capacity-planning)
- [Procedure — investigate a slow endpoint](#procedure--investigate-a-slow-endpoint)
- [Procedure — investigate a queue backlog](#procedure--investigate-a-queue-backlog)
- [Verification](#verification)
- [Rollback](#rollback)
- [Troubleshooting](#troubleshooting)

## Prerequisites

- Backend, worker, and frontend services running.
- APM provider configured (Sentry / New Relic / DataDog / AppSignal) with credentials in place.
- Postgres `EXPLAIN ANALYZE` access for the production / staging DB.
- Redis client (`redis-cli`) accessible from the worker host.
- For load tests: a non-production environment that mirrors production sizing.

## When to use this

- Sustained P95 latency above target on a hot endpoint.
- Sidekiq queue backlog (any queue > 1000 enqueued).
- Memory pressure or OOM-kills on backend / worker pods.
- Pre-launch capacity planning for a new wave of AI traffic.
- After adding a new agent / mission flow that materially shifts load.

## Overview

Performance work at Powernode spans three layers:

1. **Synchronous request path** — Rails controllers serving `/api/v1/*` and `/api/v1/ai/*`. Targets: low P95 latency, low error rate, no N+1 queries.
2. **Asynchronous worker path** — Standalone Sidekiq processing AI orchestration, DevOps, Docker sync, and maintenance. Targets: short queue latency, bounded retry depth, predictable nightly maintenance windows.
3. **External provider path** — Calls into AI providers (OpenAI / Anthropic / Ollama / etc.) and managed Docker / Vault / Stripe APIs. Targets: circuit-breaker discipline, per-provider quota awareness, predictable timeouts.

Most tuning work begins by identifying which layer is the bottleneck (APM is the primary tool), then applying the targeted patterns in the rest of this runbook.

## Key Performance Targets

### API Latency (P95)

| Endpoint Type | Target | Maximum Acceptable |
|---------------|--------|--------------------|
| Authentication | < 100ms | 200ms |
| Read-heavy CRUD | < 150ms | 300ms |
| Mutation CRUD | < 200ms | 400ms |
| AI orchestration (synchronous) | < 500ms | 1000ms |
| AI orchestration (LLM call) | < 30s | 60s |
| Analytics / reporting | < 500ms | 1000ms |
| Webhook ingest | < 250ms | 500ms |

### Database

| Metric | Target |
|--------|--------|
| Connection pool size | 25-50 |
| Max query time | < 100ms |
| Index coverage on hot tables | > 95% |
| N+1 queries | 0 |

### Worker / Background Jobs

| Metric | Target |
|--------|--------|
| Queue latency (steady state) | < 60s |
| Job processing time (avg) | < 5 seconds |
| Failed job rate | < 1% |
| Worker concurrency per instance | 5-25 |

### AI Provider Calls

| Metric | Target |
|--------|--------|
| Circuit breaker open events | < 3 active |
| Provider P95 round-trip | < 2 × baseline |
| Retry depth | < 3 per call |

## Application Performance Monitoring

Configure APM via a Rails initializer (e.g., `<server>/config/initializers/performance_monitoring.rb`). The pattern below assumes New Relic but applies equally to DataDog / AppSignal — switch the SDK calls accordingly.

```ruby
# config/initializers/performance_monitoring.rb
if Rails.env.production? || Rails.env.staging?
  Rails.application.config.after_initialize do
    # Mission lifecycle
    ActiveSupport::Notifications.subscribe('ai.mission.completed') do |_n, start, finish, _id, payload|
      duration = (finish - start) * 1000
      record_metric('AI/Mission/Completed', duration, account_id: payload[:account_id])
      log_slow('AI mission', duration, threshold: 60_000)
    end

    # Agent execution
    ActiveSupport::Notifications.subscribe('ai.agent.execution.completed') do |_n, start, finish, _id, payload|
      duration = (finish - start) * 1000
      record_metric('AI/Agent/Execution', duration,
                    agent_id: payload[:agent_id],
                    provider: payload[:provider])
      log_slow('Agent execution', duration, threshold: 30_000)
    end

    # Background job timing
    ActiveSupport::Notifications.subscribe('job.performed') do |_n, start, finish, _id, payload|
      duration = (finish - start) * 1000
      job_class = payload[:job].class.name
      record_metric("Worker/Job/#{job_class}", duration)
      log_slow('Background job', duration, threshold: 30_000, context: { job: job_class })
    end
  end
end
```

### Per-Request Tracking Middleware

```ruby
class PerformanceTrackingMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    start = Time.current
    status, headers, response = @app.call(env)
    duration = (Time.current - start) * 1000

    request = Rack::Request.new(env)
    endpoint = "#{request.method} #{request.path_info}"

    if duration > 1000
      Rails.logger.performance "Slow request: #{endpoint} took #{duration.round(2)}ms"
      record_metric("SlowRequest/#{request.method}", duration)
    end

    if Rails.env.development?
      headers['X-Response-Time'] = "#{duration.round(2)}ms"
      headers['X-DB-Query-Count'] = ActiveRecord::Base.connection.query_cache.size.to_s
    end

    [status, headers, response]
  end
end
```

## Database Performance

### Slow Query Logging

```ruby
class DatabasePerformanceMonitor
  def self.track_slow_queries
    ActiveSupport::Notifications.subscribe('sql.active_record') do |_n, start, finish, _id, payload|
      duration = (finish - start) * 1000
      next if duration < 500

      Rails.logger.performance "Slow query: #{payload[:sql]} (#{duration.round(2)}ms)"
      record_metric('Database/SlowQuery', duration, sql_type: extract_sql_type(payload[:sql]))
    end
  end

  def self.monitor_connection_pool
    Thread.new do
      loop do
        pool = ActiveRecord::Base.connection_pool
        record_metric('Database/Pool/Size', pool.size)
        record_metric('Database/Pool/Available', pool.available_connection_count)
        record_metric('Database/Pool/Active', pool.size - pool.available_connection_count)

        if pool.available_connection_count < 3
          Rails.logger.performance "DB pool nearly exhausted: #{pool.available_connection_count} available"
        end

        sleep 30
      end
    end
  end
end
```

### Query Optimization Heuristics

Common red flags in `EXPLAIN ANALYZE`:

1. **Seq Scan on a hot table** — add a covering index on the WHERE / JOIN column.
2. **Loop over an association without `includes()`** — classic N+1; always use `.includes(:assoc)` when iterating.
3. **`ORDER BY` without `LIMIT`** — paginate or chunk.
4. **Large `IN (...)` lists** — prefer a join against a temporary table or batched queries.

The repo enforces eager loading via lint patterns and CI; see [../guides/backend.md](../guides/backend.md) for the canonical patterns.

### Index Health

- All foreign keys are indexed automatically via `t.references` (never `add_index` separately).
- pgvector tables use HNSW indexes for embedding columns.
- Run quarterly: `SELECT schemaname, relname, n_dead_tup, last_autovacuum FROM pg_stat_user_tables ORDER BY n_dead_tup DESC LIMIT 25;` and `VACUUM ANALYZE` heavy-write tables on a maintenance window.

## Caching Strategy

### Multi-Layer Cache Configuration

```ruby
class PerformanceCacheService
  CACHE_CONFIGS = {
    user_session:         { ttl: 15.minutes, compress: false },
    user_profile:         { ttl: 1.hour,     compress: true  },
    account_settings:     { ttl: 30.minutes, compress: true  },
    ai_provider_models:   { ttl: 6.hours,    compress: true  },
    ai_pricing:           { ttl: 24.hours,   compress: true  },
    analytics_dashboard:  { ttl: 1.hour,     compress: true  },
    system_configuration: { ttl: 24.hours,   compress: true  }
  }.freeze

  def self.cache_with_performance(key, cache_type: :default, &block)
    config = CACHE_CONFIGS[cache_type] || { ttl: 1.hour, compress: false }
    Rails.cache.fetch(key, expires_in: config[:ttl], compress: config[:compress], &block)
  end

  def self.warm_critical_caches
    %w[system:configuration navigation:menu_items features:enabled_features].each do |key|
      Thread.new { warm_cache(key) }
    end
  end

  def self.invalidate_related_caches(pattern)
    case pattern
    when /user_(\d+)/    then invalidate_user_caches($1)
    when /account_(\w+)/ then invalidate_account_caches($1)
    when /provider_/     then invalidate_provider_caches
    end
  end
end
```

### Cache Hit-Rate Monitoring

Track `cache_hits / total_lookups` per cache_type. Alert when:

- Overall hit rate < 70%.
- Individual `cache_type` hit rate < 50% (indicates TTL too short or eviction pressure).

## Redis Tuning

```ruby
class RedisPerformanceOptimizer
  def self.configure_optimal_connection
    Redis.current = Redis.new(
      url: ENV['REDIS_URL'],
      size: ENV.fetch('REDIS_POOL_SIZE', 25).to_i,
      timeout: ENV.fetch('REDIS_TIMEOUT', 5).to_i,
      tcp_keepalive: 60,
      reconnect_attempts: 3,
      reconnect_delay: 1.5,
      reconnect_delay_max: 10,
      driver: :hiredis,
      connect_timeout: 2,
      read_timeout: 1,
      write_timeout: 1
    )
  end
end
```

Monitor:

- `used_memory / maxmemory` — alert at > 80%.
- `connected_clients` — alert if persistently > 80% of `maxclients`.
- `instantaneous_ops_per_sec` — establish a baseline, alert on > 2× sustained.
- Slow log (`SLOWLOG GET 10`) — review weekly.

Optimisation actions:

- **Large keys** (> 1 MB) → compress at the application layer or restructure the value.
- **Stale keys** without TTL → audit producers and add `expires_in:` to all `Rails.cache.write` calls.
- **High eviction count** → increase `maxmemory` or reduce TTLs on the noisiest cache types.

## Background Worker Tuning

The worker is the platform's most variable performance dimension. See [worker-operations.md](worker-operations.md) for queue layout, schedules, and service management.

Tuning levers (in order of likely impact):

1. **Concurrency** — bump `WORKER_CONCURRENCY` env var on the systemd unit. Default 5; raise to 10-25 for AI-heavy workloads.
2. **Dedicated worker instances** — `sudo scripts/systemd/powernode-installer.sh add-instance worker ai-heavy` then set per-instance config in `/etc/powernode/worker-ai-heavy.conf`.
3. **Queue weighting** — increase the weight of starving queues in `worker/config/sidekiq.yml` (current default: critical=3, standard=2, low=1).
4. **Circuit breaker thresholds** — adjust `failure_threshold` / `recovery_timeout` for noisy providers in the relevant circuit-breaker config.

Watch:

- Queue latency per queue (Sidekiq dashboard / `enqueued_at` vs `processed_at`).
- Retry depth (`Sidekiq::RetrySet`).
- Failed-job rate per job class.

## AI Provider Throughput

Each AI provider call goes through `LlmProxyClient`, which wraps the request in a circuit breaker:

- Failure threshold: 5
- Recovery timeout: 120s
- Request timeout: 600s

Common tuning patterns:

- **Hot-spot provider** → register a second credential on the provider and split traffic via `Ai::AgentModelSelector`.
- **Provider rate-limit churn** → respect the provider's recommended request rate; lower `concurrency` for the relevant queue.
- **Cost vs. latency trade-off** → use the `ModelRouter` to route latency-sensitive flows to a faster but more expensive model and batch / non-interactive flows to a cheaper model.

Reference: [ai-operations.md](ai-operations.md) for SLO definitions and incident runbooks.

## Frontend Performance

Frontend is React + TypeScript + Vite.

Targets:

- Initial bundle (gzipped) < 300 KB.
- Route-level code splitting on every top-level feature.
- Largest Contentful Paint (LCP) < 2.5s on a cold load.
- No layout shift after first paint.

Patterns:

- Use route-level `React.lazy()` for every feature directory.
- Prefer `useInfiniteResourceList` over Previous/Next pagination on list pages.
- Use `data-testid` for E2E selectors instead of class / role matchers.
- Run `npx --prefix frontend tsc --noEmit` after TS changes.
- Bundle analysis: `cd frontend && npm run build && npx vite-bundle-visualizer`.

For component-level patterns and conventions, see [../guides/frontend.md](../guides/frontend.md).

## Load Testing

### Realistic Scenarios

Tune the scenarios below to your fleet's actual traffic mix. They're a starting point — not gospel.

| Scenario | Endpoint | Method | Concurrent users | Duration | Ramp-up |
|----------|----------|--------|------------------|----------|---------|
| Auth burst | `/api/v1/auth/login` | POST | 50 | 5m | 1m |
| Agent execute (sync) | `/api/v1/ai/agents/:id/execute` | POST | 20 | 10m | 2m |
| Mission create | `/api/v1/ai/missions` | POST | 10 | 5m | 1m |
| Dashboard load | `/api/v1/ai/monitoring/dashboard` | GET | 100 | 5m | 1m |
| WebSocket subscribe | `/cable` | WS | 200 | 5m | 1m |

### Tooling

- **k6** (`k6.io`) for HTTP + WebSocket scenarios.
- **Apache Bench (`ab`)** for one-off endpoint smoke checks.
- **Locust** if you need Python-defined ramp logic.

Sample k6 script skeleton:

```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '1m', target: 50 },
    { duration: '5m', target: 50 },
    { duration: '1m', target: 0 },
  ],
};

const jwt = __ENV.JWT;
export default function () {
  const res = http.get('https://api.staging.powernode.example.com/api/v1/ai/monitoring/dashboard', {
    headers: { Authorization: `Bearer ${jwt}` },
  });
  check(res, { 'status 200': r => r.status === 200, 'p95 < 500ms': r => r.timings.duration < 500 });
  sleep(1);
}
```

### Thresholds

| Metric | Threshold | Action |
|--------|-----------|--------|
| P95 response time | < 2000ms | Investigate slow query / serializer |
| P99 response time | < 5000ms | Investigate provider timeout or queue contention |
| Error rate | < 1% | Investigate failing endpoints |
| Throughput | ≥ baseline × 0.8 | Investigate regression vs. last run |

## Capacity Planning

When sizing for a known growth target (new account onboarding, mission burst, etc.):

1. **Establish baseline.** Use APM dashboards to capture P50 / P95 / P99 latency and throughput at current load.
2. **Project growth.** Multiply baseline traffic by the expected growth factor.
3. **Identify saturation.** Run a graduated load test against staging until you hit the first SLO violation. Note the limiting resource (CPU, memory, DB pool, Redis, provider quota).
4. **Plan capacity.** Add the appropriate dimension headroom:
   - CPU saturation → scale backend / worker horizontally (Docker Swarm / Compose `--scale`).
   - DB pool saturation → bump pool size or add PgBouncer.
   - Redis saturation → bump `maxmemory` or split Sidekiq DBs.
   - Provider quota → register additional credentials or upgrade vendor tier.
5. **Re-test.** Confirm the SLO violation moves out beyond the projected growth.

## Procedure — investigate a slow endpoint

1. Identify the endpoint in APM. Confirm sustained P95 latency above target for the relevant endpoint class.
2. Inspect the trace breakdown — pinpoint whether the time is in DB, Ruby code, or downstream HTTP.
3. **DB-bound:** run `EXPLAIN ANALYZE` on the offending query; look for seq scans, large sorts, or missing indexes.
4. **Ruby-bound:** profile the controller with `rack-mini-profiler` locally; check for N+1 queries via `bullet` gem output.
5. **External call-bound:** check circuit breaker state and provider quota.
6. Apply the fix (index, `.includes()`, caching, provider-side change) and confirm the trace breakdown improves.

## Procedure — investigate a queue backlog

1. Check the Sidekiq dashboard: which queue is backed up, and what's the latency?
2. Inspect retry / failed sets for systemic errors.
3. **Capacity issue** → bump `WORKER_CONCURRENCY` or add a worker instance.
4. **Slow job** → profile the job; bring the long path under a circuit breaker or split into smaller jobs.
5. **External provider stalling** → check provider status; consider failing-fast via the breaker.
6. Verify the queue depth returns to steady state within the next 15 minutes.

## Verification

After applying a tuning change:

- APM dashboard shows the relevant percentile within target for at least one full peak window.
- Sidekiq dashboard shows queue latency within SLO and no growing retry set.
- `SELECT * FROM pg_stat_activity WHERE state = 'active'` does not show stuck queries.
- No new error spikes in Sentry / Rollbar.

## Rollback

If a tuning change degrades performance:

1. Revert the Git commit and redeploy the affected service (backend, worker, or frontend).
2. Confirm the previous baseline restores within one peak window.
3. If the change was a config flag (env var / sidekiq.yml weighting), restore via systemd unit edit:

   ```bash
   sudo nano /etc/powernode/worker-default.conf
   sudo systemctl restart powernode-worker@default
   ```

4. Capture the failure mode in `platform.create_learning` (category `failure_mode`) so we don't repeat.

## Troubleshooting

| Symptom | Likely cause | First action |
|---------|--------------|--------------|
| P95 latency creeping up | Cache hit rate degraded | Inspect Redis stats + `cache_hits/total_lookups` |
| Sidekiq retry set growing | Failing job class | Inspect `Sidekiq::RetrySet`; investigate top retried job |
| Backend OOM-kill | Memory leak in long-running process | Restart backend with `scripts/reload-backend.sh`; profile with `derailed_benchmarks` |
| Frontend bundle ballooned | New dep without code-split | Run bundle visualiser; lazy-load the new feature |
| Provider P95 doubled | Provider-side incident | Check provider status page; lower call rate via worker concurrency |
| Mission completion rate dropped | AI provider quota / circuit breaker | Check provider quota + open breakers |

---

## Related runbooks

- [production-deployment.md](production-deployment.md) — Initial service install + scaling commands
- [worker-operations.md](worker-operations.md) — Worker job catalogue + queue config
- [ai-operations.md](ai-operations.md) — AI-specific operational procedures
- [docker-swarm.md](docker-swarm.md) — Multi-host scaling

## Materials previously at

- `docs/infrastructure/PERFORMANCE_OPTIMIZER.md` (2025-08-24; rewritten 2026-05-17 for current platform identity)

_Last verified: 2026-05-17_
