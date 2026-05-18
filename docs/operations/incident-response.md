# Incident Response Runbook

> **When to use this runbook**: a Powernode service is degraded or down, agent activity is misbehaving, or a security event needs containment. Use the [Triage decision tree](#triage-decision-tree) to find the right section quickly.

## Contents

- [Triage decision tree](#triage-decision-tree)
- [Severity definitions](#severity-definitions)
- [The kill switch](#the-kill-switch)
- [Service-degradation incidents](#service-degradation-incidents)
- [AI agent misbehavior incidents](#ai-agent-misbehavior-incidents)
- [Security incidents](#security-incidents)
- [Communications](#communications)
- [Post-mortem template](#post-mortem-template)

## Triage decision tree

```
Is the platform doing something it should not be doing right now?
├── YES — agents are taking unwanted actions, secrets are leaking,
│         compromised account is acting
│         → flip THE KILL SWITCH (see below), then proceed
└── NO  — platform is unable to do something it should do
          (API down, requests failing, jobs stuck)
          → SERVICE-DEGRADATION INCIDENTS section

Is there a security dimension (auth bypass, data exfil, code
execution, key disclosure)?
├── YES → SECURITY INCIDENTS section (do not skip kill switch step)
└── NO  → continue with above branch
```

## Severity definitions

| Severity | Definition | Target response time |
|----------|------------|----------------------|
| **SEV1** | Customer-facing outage, data loss in progress, active security breach | Acknowledge in 5 min, all-hands |
| **SEV2** | Significant degradation, agent autonomy malfunctioning, one-tenant impact | Acknowledge in 15 min, primary on-call |
| **SEV3** | Recoverable degradation, single-user impact, internal-only outage | Acknowledge in 1 hour, normal hours OK |
| **SEV4** | Minor regression, cosmetic issue, no customer impact | Next business day |

If unsure, **escalate one level higher**. Downgrading mid-incident is fine; upgrading after an under-call is not.

## The kill switch

Powernode has a global AI activity kill switch. Use it when AI agents are taking unwanted actions, an extraction-style attack is in progress, or you need a clean stop before triage.

### How to engage

**Via MCP (preferred — auditable)**:
```
platform.emergency_halt(reason: "<one-sentence reason>")
```

**Via API**:
```bash
TOKEN=$(curl -s -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@yourdomain","password":"..."}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['access_token'])")
curl -X POST http://localhost:3000/api/v1/ai/kill_switch/halt \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"reason":"<one-sentence reason>"}'
```

**What it does**:
- Marks all AI activity as suspended in `ai_kill_switch_state`.
- Existing in-flight AI jobs (worker `ai_agents`, `ai_orchestration`, `ai_execution` queues) check the suspension flag and bail out at safe checkpoints. Tool calls that have already been emitted will complete; new calls are blocked.
- The chat surface refuses new prompt submissions.
- Non-AI workloads (webhook delivery, billing, report generation) are not affected.

### Check status

```
platform.kill_switch_status()
```

Returns `{ halted: bool, halted_at: ..., halted_by: ..., reason: ... }`.

### Resume

Only after root cause is understood and remediation is in place:

```
platform.emergency_resume(reason: "<remediation summary>")
```

Source: `server/app/services/ai/autonomy/kill_switch_service.rb`.

## Service-degradation incidents

### API returning 5xx

1. **Check service status**:
   ```bash
   sudo scripts/systemd/powernode-installer.sh status
   journalctl -u powernode-backend@default -n 100 --no-pager
   ```
2. **Look for recent deploys**: `git -C /opt/powernode log --since="1 hour ago" --oneline` — most outages correlate with a deploy.
3. **Check the database**: `cd server && bundle exec rails db:migrate:status | tail -5` — a half-applied migration locks tables.
4. **Check Redis** (Sidekiq queue, ActionCable): `redis-cli -n 1 PING`, `redis-cli -n 1 LLEN reports` for queue depth.
5. **Rollback if recent deploy** is suspect — see [production-deployment.md#rollback](./production-deployment.md#rollback).

### Worker jobs stuck

Symptoms: `ReportRequest.where(status: 'processing').count` growing, agent executions never completing.

1. **Worker process up?**
   ```bash
   sudo systemctl status powernode-worker@default
   ```
2. **Drain didn't complete cleanly?** Per `feedback_service_restarts`, wait 30s after restart before troubleshooting; Sidekiq drain is normal.
3. **Stuck worker — full restart**:
   ```bash
   sudo systemctl stop powernode-worker@default && sleep 30 && sudo systemctl start powernode-worker@default
   ```
   Do NOT use `restart` — it skips drain. Stop + start gives a clean state.
4. **Backend HTTP API on port 4567 refused?** Restart `powernode-worker-web@default`, NOT `powernode-worker@default` (per `feedback_worker_web_port`).
5. **Inspect dead jobs**: `redis-cli -n 1 LLEN sidekiq:dead`. If non-empty, jobs are exhausting retries — investigate the exception class.

### Database unresponsive

1. **Connection check**:
   ```bash
   psql -h localhost -U powernode -c "SELECT now();"
   ```
2. **Connection pool exhausted**: `SELECT count(*), state FROM pg_stat_activity GROUP BY state;`. Idle-in-transaction > 50% means a leaked connection.
3. **Disk full**: `df -h /var/lib/postgresql/` — Postgres dies hard at 100% disk; clear old WAL or expand volume.
4. **Lock contention**: `SELECT * FROM pg_stat_activity WHERE wait_event IS NOT NULL;`.

If unrecoverable, escalate to disaster scenario in [postgres-backup.md#disaster-scenarios](./postgres-backup.md#disaster-scenarios).

## AI agent misbehavior incidents

Symptoms include: agent loops, runaway costs, agents writing to wrong resources, agents leaking secrets in conversation, autonomy taking unapproved actions.

1. **Engage kill switch FIRST**. Triage second. This costs nothing if the suspicion is wrong.
2. **Identify the agent**:
   ```
   platform.list_agents(status: "executing")
   platform.recent_events(limit: 50)
   ```
3. **Inspect the most recent executions**:
   ```
   platform.agent_introspect(agent_id: "<id>")
   ```
4. **Check intervention policies**:
   ```
   platform.list_intervention_policies(agent_id: "<id>")
   ```
   A missing or mis-configured policy is the most common cause.
5. **Pause the specific agent** (preferred over kill switch once scope is known):
   ```
   platform.update_agent(id: "<id>", status: "paused")
   ```
6. **Cost spike?** Check `platform.cost_analysis()` for the spending shape. Throttle via the agent's `max_cost_per_run` budget setting.

After remediation, lift the kill switch and monitor `platform.recent_events()` for 30 minutes before declaring the incident resolved.

## Security incidents

### Suspected credential leak

1. **Engage kill switch** to prevent further automated actions with the leaked credential.
2. **Rotate the credential**:
   - User: force password reset via admin UI or `User.find(...).request_password_reset!`
   - API key: `User.find(...).api_keys.find(...).revoke!`
   - Worker JWT: `Worker.find(...).rotate_token!` (or restart the worker — JWT is short-lived)
   - Vault-backed secret: rotate via Vault, then `VaultCredential` re-fetches on next access
3. **Audit the trail** — `AuditLog.where(user_id: ..., created_at: <leak window>).order(:created_at)`.
4. **Notify affected accounts** if any non-self resources were accessed during the window.

### Suspected data exfiltration

1. **Kill switch**.
2. **Identify the access pattern**: query `audit_logs` for the actor and resource_type within the suspected window.
3. **Pull the access logs** from the load balancer / reverse proxy (Traefik) for HTTP-level evidence.
4. **Snapshot the database** before any remediation (`backup-database.sh "incident_$(date +%s)"`) — preserves evidence.
5. **Engage legal/compliance** per your regulatory obligations.

### Active code execution / shell access

1. **Take affected host(s) off the load balancer immediately** — do not stop services first (running services preserve evidence in memory).
2. **Snapshot disk + memory** (`virsh snapshot-create` if KVM, or `aws ec2 create-snapshot` if EC2).
3. **Engage external IR** if you have a retainer. The cost of an outside firm is small compared to mishandled forensics.
4. **Rotate ALL credentials reachable from the compromised host** — assume worst case.

## Communications

### Status page

Powernode does not ship a status page out of the box. If you don't have one, in-platform notifications via:

```
platform.send_proactive_notification(
  account_id: "all" | "<specific>",
  title: "...",
  body: "...",
  severity: "high"
)
```

reach logged-in users immediately via ActionCable.

### Internal comms cadence

| Severity | Update cadence | Channel |
|----------|---------------|---------|
| SEV1 | Every 15 min until resolution | War-room |
| SEV2 | Every 30 min | Incident channel |
| SEV3 | Hourly | Incident channel |

### Customer comms

If user data is affected — even potentially — communicate proactively. Template:

> Subject: Service incident — [brief description]
>
> Hi,
>
> At [start time UTC], we detected [symptom]. Our team engaged immediately and [restored service | confirmed contained] at [end time UTC].
>
> Impact: [what users experienced]
>
> Cause: [if known, plain language; if not, "investigation ongoing"]
>
> What we're doing: [remediation steps + timeline for full post-mortem]
>
> If you have questions, reply to this email.

## Post-mortem template

Run within 5 business days of any SEV1/SEV2. Blameless format.

```markdown
# Incident YYYY-MM-DD: [short title]

**Severity:** SEV[1|2|3|4]
**Duration:** [start UTC] — [end UTC] ([N] hours [M] minutes)
**Detected by:** [alert | customer report | engineer noticed]
**Resolved by:** [name / on-call rotation]

## Impact

- Number of accounts affected:
- User-visible symptoms:
- Data integrity impact (none / data loss / corruption):
- SLA breach: yes/no, by [N] minutes

## Timeline (all times UTC)

| Time | Event |
|------|-------|
| HH:MM | First symptom (in logs / metrics / user report) |
| HH:MM | Alert fired / report received |
| HH:MM | Engineer acknowledged |
| HH:MM | Root cause identified |
| HH:MM | Remediation applied |
| HH:MM | All-clear |

## What happened (technical)

[Narrative: state of system before, change that triggered, propagation, observable effects.]

## Root cause

[The actual underlying cause, not the proximate trigger. Use 5-whys if the cause is non-obvious.]

## What went well

- [What allowed faster detection / shorter MTTR]

## What went poorly

- [Gaps in monitoring, runbooks, tooling]

## Action items

| Action | Owner | Due | Status |
|--------|-------|-----|--------|
| [Fix root cause permanently] | | | open |
| [Add monitoring/alert that would have caught this] | | | open |
| [Update runbook section X] | | | open |

## Lessons (for future on-call rotations)

[1-2 bullet points worth remembering. Add to `platform.create_learning` so other operators benefit.]
```

## See also

- [production-deployment.md](./production-deployment.md) — deploy / rollback procedures
- [postgres-backup.md](./postgres-backup.md) — disaster recovery
- [worker-operations.md](./worker-operations.md) — worker queue/job operations
- [docker-swarm.md](./docker-swarm.md) — Swarm-specific operations
- [ai-operations.md](./ai-operations.md) — AI agent operations
- [observability.md](./observability.md) — log aggregation + monitoring
