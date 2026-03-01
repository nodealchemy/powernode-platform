# AI Orchestration Operations Guide

**Testing, Monitoring, and Operational Procedures for the AI Platform**

**Version**: 3.0 | **Last Updated**: February 2026

---

## Testing Strategy

### Testing Pyramid

```
        ┌──────────────┐
        │  E2E Tests   │  (10% - Mission/workflow execution scenarios)
        │   Cypress     │
        ├──────────────┤
        │ Integration  │  (30% - API + DB + WebSocket)
        │    Tests     │
        ├──────────────┤
        │   Unit Tests │  (60% - Services, models, components)
        │ RSpec + Jest │
        └──────────────┘
```

### Coverage Targets

| Layer | Target | Focus Areas |
|-------|--------|-------------|
| Services | 85%+ | Orchestration, autonomy, security, memory, RAG |
| Models | 90%+ | Trust scoring, delegation, guardrails, missions |
| Controllers | 80%+ | 73 AI controllers |
| Jobs | 75%+ | Mission phase jobs, maintenance jobs |
| Frontend Components | 70%+ | Workflow builder, mission dashboard |
| Frontend Services | 90%+ | API integration layer |

### Key Test Patterns

```ruby
# User setup with permissions
user = user_with_permissions('ai.workflows.execute')

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

---

## Monitoring & Alerting

### Key Metrics

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| API response time | P95 across 73 controllers | > 500ms |
| API error rate | 5xx errors | > 5% |
| Mission completion rate | Successful missions | < 80% |
| Ralph task success rate | Passed vs failed tasks | < 85% |
| Trust score distribution | Agent tier breakdown | > 50% supervised |
| Memory consolidation lag | STM entries pending promotion | > 1000 |
| RAG query latency | Average retrieval time | > 2s |
| Guardrail block rate | Blocked vs allowed requests | > 20% |
| Circuit breaker opens | Open provider breakers | > 3 |
| Skill conflict count | Unresolved conflicts | > 10 |
| Budget utilization | Per-agent budget usage | > 90% |
| Queue depth | AI execution queue | > 1000 jobs |

### Critical Alerts (P1)

**AI Platform Availability**:
```yaml
- alert: AIPlatformHighErrorRate
  expr: |
    (sum(rate(ai_api_requests_500[5m])) /
     sum(rate(ai_api_requests_total[5m]))) > 0.05
  for: 5m
  labels:
    severity: critical
```

**Agent Quarantine Surge**:
```yaml
- alert: MassAgentQuarantine
  expr: ai_quarantine_records_active > 10
  for: 5m
  labels:
    severity: high
```

**Trust Score Decay**:
```yaml
- alert: TrustScoreWidespreadDecay
  expr: ai_agents_supervised_tier_count / ai_agents_total > 0.5
  for: 1h
  labels:
    severity: warning
```

---

## Automated Maintenance Jobs

| Job | Schedule | Purpose |
|-----|----------|---------|
| Trust score decay | 2:00 AM daily | Decays idle agent trust scores toward 0.5 baseline |
| Learning decay | 3:45 AM daily | Exponential decay on stale compound learnings |
| Memory consolidation | 4:00 AM daily | STM → LTM promotion (access >= 3) |
| Context rot detection | 4:00 AM daily | Archives context entries with staleness >= 0.9 |
| Skill conflict scan | 4:15 AM daily | Detects overlapping/contradictory skills |
| Skill stale decay | 5:00 AM weekly | Reduces effectiveness of unused skills |
| Skill re-embedding | 5:00 AM weekly | Updates skill embeddings for discovery |
| Knowledge doc sync | 5:30 AM daily | Syncs knowledge to documentation files |
| Skill gap detection | 3:00 AM monthly | Identifies missing capabilities |

---

## Operational Procedures

### Daily Checklist (10 minutes)

- [ ] Check dashboard for anomalies (error rates, latencies)
- [ ] Review overnight quarantine records
- [ ] Verify all services running: `sudo scripts/systemd/powernode-installer.sh status`
- [ ] Check mission pipeline: any stuck missions?
- [ ] Review cost tracking: any budget alerts?

### Weekly Review (30 minutes)

- [ ] Analyze trust score distribution across agents
- [ ] Review skill conflict report
- [ ] Check memory consolidation metrics
- [ ] Review RAG query quality scores
- [ ] Audit guardrail block rates
- [ ] Check model router optimization recommendations

### Monthly Review (2 hours)

- [ ] Trust tier promotion/demotion analysis
- [ ] Cost attribution deep-dive by provider/model/agent
- [ ] Skill gap detection results
- [ ] Security audit trail review (high-risk events)
- [ ] Memory tier capacity planning
- [ ] Knowledge base freshness assessment

### Incident Runbooks

**Mission Stuck in Phase**:
1. Check mission status: `Ai::Mission.find(id).current_phase`
2. Check worker job status: `systemctl status powernode-worker@default`
3. Review worker logs: `journalctl -u powernode-worker@default -f`
4. Check for failed Ralph tasks: `mission.ralph_loop.ralph_tasks.failed`
5. Retry phase: `mission_orchestrator.retry_phase!`

**Agent Quarantined Unexpectedly**:
1. Check quarantine record: `Ai::QuarantineRecord.for_agent(agent_id).active`
2. Review trigger reason and source
3. Check behavioral fingerprint anomalies
4. If false positive, restore agent and tune thresholds
5. Review security audit trail for context

**Trust Score Collapsed**:
1. Check recent executions: `agent.agent_executions.recent`
2. Review dimension breakdown: `agent.agent_trust_score.dimensions`
3. Check for emergency demotion events
4. If legitimate, agent will naturally recover with successful executions
5. If anomalous, investigate security audit trail

---

## Success Metrics

**Reliability Targets**:
- API Availability: 99.9% uptime
- API Response Time: < 200ms (P95)
- Mission Success Rate: > 80%
- Ralph Task Pass Rate: > 85%

**Performance Targets**:
- RAG Query Latency: < 2s (P95)
- Memory Consolidation: < 5 minutes
- Trust Evaluation: < 100ms
- Model Route Decision: < 50ms

---

## Quick Reference Commands

```bash
# Backend tests
cd server && bundle exec rspec

# Frontend tests
cd frontend && CI=true npm test

# TypeScript check
cd frontend && npx tsc --noEmit

# Service status
sudo scripts/systemd/powernode-installer.sh status

# View logs
journalctl -u powernode-backend@default -f

# Monitor worker
systemctl status powernode-worker@default
```

---

**Document Status**: Complete
