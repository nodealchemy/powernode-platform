# AIOps Dashboard

> Status: active

> The in-app operational view of an AI agent fleet — live health, provider and agent
> performance, cost, reliability (alerts + circuit breakers), and short-window trends.
> Distinct from the infra logging/metrics stack in [operations/observability.md](../operations/observability.md)
> and from the deep historical analytics surface.

## Table of Contents

- [What this covers](#what-this-covers)
- [Where it lives](#where-it-lives)
- [Dashboard sections](#dashboard-sections)
- [API contract](#api-contract)
- [Trend semantics](#trend-semantics)
- [Operational vs analytics boundary](#operational-vs-analytics-boundary)
- [See also](#see-also)

## What this covers

The AIOps dashboard answers "how is my AI fleet doing **right now**, and over the last few
hours?" It reads from `Ai::Analytics::DashboardService` (the `AiopsMetrics` concern) which
aggregates `Ai::AgentExecution`, `Ai::ProviderMetric`, cost attribution, and circuit-breaker
state — all account-scoped. It is **read-only**: it surfaces live operational data, it does not
mutate fleet state.

AIOps lives inside the **Observability** hub (`ObservabilityPage`, `/app/ai/observability/*`),
inside an `AiErrorBoundary`. Observability used to be split across two pages (this one plus a
dedicated Operations hub); they were merged into one page, one URL, one Systems backend — see
[AI Navigation IA](ai-navigation-ia.md). It is path-based (canonical `PathTabs`, one URL segment
per tab):

- **Systems** tab — the AIOps operational core: KPIs + system health + an active-provider-alerts
  callout, trend charts, providers table, agents table. Body component: `AiOpsContent`
  (`frontend/src/features/ai/aiops/components/AiOpsDashboard.tsx`).
- **Circuit Breakers** tab — agent circuit breakers (`Ai::CircuitBreaker`, resettable) and
  provider circuit breakers (`Ai::CircuitBreakerRegistry`, resettable, the live registry that
  actually gates provider calls) under distinct labels, plus the AIOps recent-errors feed.
  Replaces the old `ReliabilitySection`, whose circuit-breaker table read a stale
  `Ai::ProviderMetric` snapshot rather than the live registry state.
- **Alerts** tab — the alert-management center (`Monitoring::UnifiedService`'s stateful,
  acknowledgeable alerts — a different backend from the AIOps tabs above; see
  [AI Navigation IA](ai-navigation-ia.md) for why both stayed).
- **Execution Traces** tab — the distributed-trace viewer (`ExecutionTracesContent`).

AIOps cost analysis is part of the **Cost** domain (`/app/ai/cost`), not Observability.

Backend: `Api::V1::Ai::AiOpsController` under `scope :aiops` — all reads gated by the
`ai.aiops.read` permission (`record_metrics` is the only writer, gated by `ai.aiops.write`
and used by the worker, not the UI).

Data fetching follows the platform standard: `@tanstack/react-query` hooks
(`features/ai/aiops/api/aiopsApi.ts`) with a query-key factory. Sections self-fetch via the
shared `useAiOpsDashboard` hook; react-query dedupes by query key, so all sections share a single
fetch regardless of which tab renders them.

## Where the data surfaces

The sections render across the **Observability** hub tabs:

| Observability tab | AIOps content | Source |
|---|---|---|
| **Systems** | execution / latency / cost KPIs, system-health components, active-provider-alerts callout, hourly trend charts, providers table, agents table | `dashboard.overview`, `dashboard.health`, `dashboard.alerts[]`, `/trends`, `dashboard.providers[]`, `dashboard.agents[]` |
| **Circuit Breakers** | provider circuit-breaker status (`Ai::CircuitBreakerRegistry`, live) + recent execution errors; agent circuit breakers (`Ai::CircuitBreaker`) render alongside, from a different backend | `dashboard.circuit_breakers[]` no longer backs this — see the tab's own component; `/recent_errors` |

AIOps `cost_analysis` data surfaces in the **Cost** domain (`/app/ai/cost`), not Observability.

## API contract

All responses use the standard `{ success, data, meta }` envelope; the frontend `BaseApiService`
unwraps `data`. Endpoints (under `/api/v1/ai/aiops`):

| Endpoint | Returns |
|----------|---------|
| `GET /dashboard?time_range=` | `{ dashboard: { health, overview (incl. `latency_aggregate`), providers[], agents[], cost_analysis, alerts[], circuit_breakers[], real_time, generated_at }, time_range }` |
| `GET /real_time` | live snapshot: `{ current_requests_per_second, current_avg_latency_ms, current_error_rate (0–1), active_connections, queue_depth, timestamp }` |
| `GET /trends?time_range=` | `{ trends: { bucket: "hour", bucket_count, latency[], error_rate[], throughput[], cost[] }, time_range }` |
| `GET /latency_aggregate?time_range=` | `{ latency_aggregate: { avg_ms, p95_ms, p99_ms, max_ms, sample_provider_count }, time_range }` |
| `GET /recent_errors?limit=` | `{ recent_errors: [{ execution_id, agent_name, error, failed_at }], count, timestamp }` |

`success_rate` fields are percentages (0–100); `current_error_rate` and trend `error_rate` are
fractions (0–1). The frontend types `latency_aggregate`, `trends`, and `recent_errors` as
optional so the UI degrades gracefully if a deployment predates those endpoints.

## Trend semantics

`GET /trends` returns four parallel time series sharing one x-axis. Key invariants:

- **Hourly buckets, capped at 168** (7 days). Bucket keys are **ISO8601 UTC** timestamps; the
  frontend localizes for display.
- **Zero-filled**: every series has exactly `bucket_count` points — buckets with no activity are
  emitted as zeros, never omitted. This keeps the chart x-axes aligned.
- Latency p95/p99 come from `Ai::ProviderMetric` (the only source with true percentiles). When an
  account has no provider metrics for a window, the series fall back to per-execution aggregates
  and report `p95 = p99 = avg` (a documented approximation).

## Operational vs analytics boundary

AIOps is intentionally **operational and live**: health, providers, alerts, circuit breakers,
real-time, short hourly trends, recent errors. It does **not** duplicate the deeper
`/api/v1/ai/analytics/*` surface (ROI, forecasting, insights, recommendations, export, day-level
30-day trends). When you need historical/financial analysis, use that surface and
[cost-and-finops.md](./cost-and-finops.md); when you need "is the fleet healthy now," use AIOps.

## See also

- [agents-and-autonomy.md](./agents-and-autonomy.md) — what produces the executions AIOps measures
- [cost-and-finops.md](./cost-and-finops.md) — deep cost analytics and budgets
- [operations/observability.md](../operations/observability.md) — infra logs/metrics (Loki/Grafana/Prometheus)
