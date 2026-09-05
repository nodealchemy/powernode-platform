---
name: deploy
description: Restart local services and verify health after code changes
disable-model-invocation: true
argument-hint: [scope: all|backend|worker|frontend]
---

# /deploy — Local Service Restart & Verify

Safely restart local Powernode services and verify they're healthy. This is for LOCAL development restarts, not remote/Docker deployment.

## Step 1: Pre-flight Check

```bash
pwd
git status --short | head -10
```

Note any uncommitted changes — warn if there are unstaged migrations.

## Step 2: Restart Services

Based on scope (default: `all`):

### backend
```bash
bash scripts/reload-backend.sh
```
Backend uses SIGUSR2 hot reload (~30ms). No downtime.

### worker
This cell is module-composed: the unit is `powernode-<moduleID>-sidekiq.service` (a UUID),
never `powernode-worker@default` — a guessed name fails `systemctl` silently. Discover it,
then restart and verify the discovered unit (fall back to `powernode-worker@default` only if
discovery finds nothing, for a plain installer-shape host):
```bash
UNIT=$(systemctl list-units 'powernode-*-sidekiq.service' --no-pager --no-legend --plain | awk '{print $1}' | head -1)
sudo systemctl restart "${UNIT:-powernode-worker@default}"
systemctl is-active "${UNIT:-powernode-worker@default}"
```
Worker drains jobs before stopping (~28s). **Do not proceed to health check for 30 seconds.**

### worker-web (always restart with worker)
Same discovery, `-worker-web` instead of `-sidekiq`:
```bash
UNIT=$(systemctl list-units 'powernode-*-worker-web.service' --no-pager --no-legend --plain | awk '{print $1}' | head -1)
sudo systemctl restart "${UNIT:-powernode-worker-web@default}"
systemctl is-active "${UNIT:-powernode-worker-web@default}"
```

### frontend
Same discovery, `-frontend`:
```bash
UNIT=$(systemctl list-units 'powernode-*-frontend.service' --no-pager --no-legend --plain | awk '{print $1}' | head -1)
sudo systemctl restart "${UNIT:-powernode-frontend@default}"
systemctl is-active "${UNIT:-powernode-frontend@default}"
```

### all (default)
Restart in this order: backend (reload), worker + worker-web, frontend.

## Step 3: Wait for Drain (worker only)

If worker was restarted, wait 30 seconds before health checks:
```bash
sleep 30
```

## Step 4: Health Check

```bash
bash scripts/health-check.sh
```

If any checks fail, report which services are down and suggest remediation.

## Step 5: Smoke Test (optional)

If all health checks pass, run a quick API smoke test:
```bash
curl -s http://localhost:3000/api/v1/health | python3 -m json.tool
curl -s http://localhost:4567/health | python3 -m json.tool
```

## Step 6: MCP Connectivity (optional)

If MCP-related changes were made:
```bash
bash scripts/mcp-smoke-test.sh
```

## Step 7: Report

```
| Service        | Status | Details          |
|----------------|--------|------------------|
| Backend        | ✅/❌  | reload/restart   |
| Worker         | ✅/❌  | drain time       |
| Worker Web     | ✅/❌  | port 4567        |
| Frontend       | ✅/❌  | port 5173        |
| API Health     | ✅/❌  | HTTP status      |
| Worker API     | ✅/❌  | HTTP status      |
| MCP            | ✅/❌/⏭ | if tested       |
```
