# AI Operations

> When to use this runbook: monitoring, alerting, and incident response for the AI orchestration platform.

## Table of Contents

- [Prerequisites](#prerequisites)
- [When to use this](#when-to-use-this)
- [Testing Strategy](#testing-strategy)
- [Key Metrics](#key-metrics)
- [Critical Alerts](#critical-alerts)
- [Automated Maintenance Jobs](#automated-maintenance-jobs)
- [Procedure — Daily Operational Checklist](#procedure--daily-operational-checklist)
- [Procedure — Weekly Review](#procedure--weekly-review)
- [Procedure — Monthly Review](#procedure--monthly-review)
- [Incident Runbooks](#incident-runbooks)
- [Verification](#verification)
- [Rollback](#rollback)
- [Troubleshooting](#troubleshooting)

## Prerequisites

- Backend (`powernode-backend@default`), worker (`powernode-worker@default`), and frontend (`powernode-frontend@default`) services running — verify with `sudo scripts/systemd/powernode-installer.sh status`
- `ai.monitoring.read`, `ai.autonomy.manage` permissions for operators
- Sidekiq dashboard accessible (default `http://localhost:4567`)
- Sentry / APM credentials configured (see [production-deployment.md](production-deployment.md))

## When to use this

- Daily operational sweeps for the AI platform
- After a deploy that touched orchestration code
- When an automated alert fires (mission stuck, agent quarantined, trust score collapse, etc.)
- Weekly / monthly governance reviews

## Testing Strategy

### Testing Pyramid

```
        ┌──────────────┐
        │  E2E Tests   │   ~10% — Mission/workflow execution scenarios
        │  Playwright  │
        ├──────────────┤
        │ Integration  │   ~30% — API + DB + WebSocket
        │   Tests      │
        ├──────────────┤
        │ Unit Tests   │   ~60% — Services, models, components
        │ RSpec + Jest │
        └──────────────┘
```

### Coverage Targets

| Layer | Target | Focus |
|-------|--------|-------|
| Services | 85%+ | Orchestration, autonomy, security, memory, RAG |
| Models | 90%+ | Trust scoring, delegation, guardrails, missions |
| Controllers | 80%+ | AI controllers under `/api/v1/ai` |
| Jobs | 75%+ | Mission phase jobs, maintenance jobs |
| Frontend components | 70%+ | Mission dashboard, agent index, team index |
| Frontend services | 90%+ | API integration layer |

### Key Test Patterns

```ruby
# Setup with permissions
user = user_with_permissions('ai.missions.manage')

# Auth headers for request specs
headers = auth_headers_for(user)

# Response helpers
expect_success_response(json_response_data)
expect_error_response("Not found", :not_found)

# Shared examples
include_examples 'requires authentication'
include_examples 'requires permission', 'ai.missions.manage'
include_examples 'scopes to current account'
```

## Key Metrics

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| API response time | P95 across AI controllers | > 500ms |
| API error rate | 5xx errors | > 5% |
| Mission completion rate | Successful missions | < 80% |
| Ralph task success rate | Passed vs failed tasks | < 85% |
| Trust score distribution | Agent tier breakdown | > 50% supervised |
| Memory consolidation lag | STM entries pending promotion | > 1000 |
| RAG query latency | Average retrieval time | > 2s |
| Guardrail block rate | Blocked vs allowed requests | > 20% |
| Circuit breaker opens | Open provider breakers | > 3 |
| Skill conflict count | Unresolved conflicts | > 10 |
| Budget utilisation | Per-agent budget usage | > 90% |
| Queue depth | AI execution queue | > 1000 jobs |

## Critical Alerts

**AI Platform availability (P1):**

```yaml
- alert: AIPlatformHighErrorRate
  expr: |
    (sum(rate(ai_api_requests_500[5m])) /
     sum(rate(ai_api_requests_total[5m]))) > 0.05
  for: 5m
  labels:
    severity: critical
```

**Agent quarantine surge:**

```yaml
- alert: MassAgentQuarantine
  expr: ai_quarantine_records_active > 10
  for: 5m
  labels:
    severity: high
```

**Trust score widespread decay:**

```yaml
- alert: TrustScoreWidespreadDecay
  expr: ai_agents_supervised_tier_count / ai_agents_total > 0.5
  for: 1h
  labels:
    severity: warning
```

## Automated Maintenance Jobs

The worker runs the following jobs on the schedules shown. Full job catalogue: [worker-operations.md](worker-operations.md).

| Job | Schedule | Purpose |
|-----|----------|---------|
| Trust score decay | 2:00 AM daily | Decay idle agent trust toward 0.5 baseline |
| Learning decay | 3:45 AM daily | Exponential decay on stale compound learnings |
| Memory consolidation | 4:00 AM daily | STM → LTM promotion (access ≥ 3) |
| Context rot detection | 4:00 AM daily | Archive context entries with staleness ≥ 0.9 |
| Skill conflict scan | 4:15 AM daily | Detect overlapping / contradictory skills |
| Skill stale decay | 5:00 AM weekly | Reduce effectiveness of unused skills |
| Skill re-embedding | 5:00 AM weekly | Refresh skill embeddings for discovery |
| Knowledge doc sync | 5:30 AM daily | Sync knowledge to documentation files |
| Skill gap detection | 3:00 AM monthly | Identify missing capabilities |

## Procedure — Daily Operational Checklist

Roughly 10 minutes per day.

- [ ] Check dashboard for anomalies (error rates, latencies)
- [ ] Review overnight quarantine records
- [ ] Verify all services running: `sudo scripts/systemd/powernode-installer.sh status`
- [ ] Check mission pipeline — any stuck missions?
- [ ] Review cost tracking — any budget alerts?

## Procedure — Weekly Review

Roughly 30 minutes per week.

- [ ] Analyse trust score distribution across agents
- [ ] Review skill conflict report
- [ ] Check memory consolidation metrics
- [ ] Review RAG query quality scores
- [ ] Audit guardrail block rates
- [ ] Check model router optimisation recommendations

## Procedure — Monthly Review

Roughly 2 hours per month.

- [ ] Trust tier promotion / demotion analysis
- [ ] Cost attribution deep-dive by provider / model / agent
- [ ] Skill gap detection results
- [ ] Security audit trail review (high-risk events)
- [ ] Memory tier capacity planning
- [ ] Knowledge base freshness assessment

## Incident Runbooks

### Mission Stuck in Phase

1. Check mission status: `Ai::Mission.find(id).current_phase`
2. Check worker job status: `systemctl status powernode-worker@default`
3. Review worker logs: `journalctl -u powernode-worker@default -f`
4. Check for failed Ralph tasks: `mission.ralph_loop.ralph_tasks.failed`
5. Retry the current phase: `mission_orchestrator.retry_phase!`

### Agent Quarantined Unexpectedly

1. Check the quarantine record: `Ai::QuarantineRecord.for_agent(agent_id).active`
2. Review trigger reason and source
3. Check behavioural fingerprint anomalies
4. If false positive: restore the agent and tune thresholds
5. Review the security audit trail for context

### Trust Score Collapsed

1. Check recent executions: `agent.agent_executions.recent`
2. Review dimension breakdown: `agent.agent_trust_score.dimensions`
3. Check for emergency demotion events
4. If legitimate: agent will recover naturally with successful executions
5. If anomalous: investigate the security audit trail

## Verification

After any intervention:

- `GET /api/v1/ai/monitoring/health` → `data.healthy: true`
- `GET /api/v1/ai/missions?status=stuck` → returns no items
- `sudo scripts/systemd/powernode-installer.sh status` → all services `active`

Reliability targets:

| Target | Threshold |
|--------|-----------|
| API availability | 99.9% uptime |
| API response time (P95) | < 200ms |
| Mission success rate | > 80% |
| Ralph task pass rate | > 85% |

Performance targets:

| Target | Threshold |
|--------|-----------|
| RAG query latency (P95) | < 2s |
| Memory consolidation | < 5 minutes |
| Trust evaluation | < 100ms |
| Model route decision | < 50ms |

## Rollback

If an intervention destabilises an agent or mission:

1. `POST /api/v1/ai/autonomy/kill_switch` → emergency halt
2. Investigate via `GET /api/v1/ai/kill_switch/status`
3. Restore from the most recent good agent state (via admin UI or rails console: `Ai::Agent.find(id).restore_from_history!(version: N)`)
4. `POST /api/v1/ai/autonomy/kill_switch/release` once safe

## Troubleshooting

### Quick Reference Commands

```bash
# Backend tests
cd server && bundle exec rspec

# Frontend tests
cd frontend && CI=true npm test

# TypeScript check
cd frontend && npx tsc --noEmit

# Service status
sudo scripts/systemd/powernode-installer.sh status

# Backend logs
journalctl -u powernode-backend@default -f

# Worker monitor
systemctl status powernode-worker@default
```

| Symptom | Likely cause | First action |
|---------|--------------|--------------|
| `429 Too Many Requests` from `/api/v1/ai/*` | Rate limiting | Check `current_quota_usage` on the data source / provider |
| Memory consolidation never runs | Worker scheduler stopped | Restart `powernode-worker@default`; verify `sidekiq-cron` job list |
| RAG retrieval returns no chunks | Embedding job behind | Check `AiKnowledgeGraphMaintenanceJob` + run manual sync |
| Skill conflict count > 10 | Recent skill changes introduced overlaps | Run `platform.skill_health`, resolve via `resolve_contradiction` |

---

## Related runbooks

- [worker-operations.md](worker-operations.md) — Worker job reference
- [production-deployment.md](production-deployment.md) — Initial AI service deployment
- [performance-tuning.md](performance-tuning.md) — Latency & throughput tuning

## Materials previously at

- `docs/platform/AI_ORCHESTRATION_OPERATIONS.md`

_Last verified: 2026-05-17_
