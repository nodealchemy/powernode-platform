# Service Management & Ops

Deep runbooks: [../../operations/](../../operations/). **NEVER** use manual commands (`rails server`, `sidekiq`, `npm start`) — systemd only.

## Services

```bash
sudo systemctl start powernode.target            # Start all
sudo systemctl restart powernode-backend@default # Restart one
sudo scripts/systemd/powernode-installer.sh status
journalctl -u powernode-backend@default -f       # Tail logs
```

| Service | Unit | Port | Restart |
|---------|------|------|---------|
| Rails API | `powernode-backend@default` | 3000 | SIGUSR2 reload (~30ms) via `scripts/reload-backend.sh`; auto-reloaded by Stop hook after `.rb` edits |
| Sidekiq | `powernode-worker@default` | — | Full restart (~28s drain). Wait 30s before checking — "deactivating" is normal |
| Worker HTTP API | `powernode-worker-web@default` | 4567 | If port 4567 refused, restart THIS, not `powernode-worker` |
| Frontend | `powernode-frontend@default` | 3001 | Full restart |

**Stuck worker** (draining >30s): `sudo systemctl stop powernode-worker@default && sudo systemctl start powernode-worker@default` (stop+start, not restart). Never restart the worker multiple times in quick succession — batch code changes, ONE restart at end.

## Worker Architecture (CRITICAL — also in CLAUDE.md core)

- The **server** (`server/`) is a Rails API — it does **NOT** run Sidekiq.
- The **worker** (`worker/`) is a standalone Sidekiq process — communicates with server via HTTP API only.
- **NEVER** create job classes in `server/app/jobs/`; **NEVER** add Sidekiq gems to `server/Gemfile`; **NEVER** modify `worker/` files when fixing server issues.

## Automation Scripts

```bash
./scripts/pre-commit-quality-check.sh   # All checks
./scripts/pattern-validation.sh         # Full convention audit (adherence metric)
./scripts/quick-pattern-check.sh        # Quick check
./scripts/validate.sh [--skip-tests]    # Specs + TS + patterns
./scripts/fix-hardcoded-colors.sh       # Fix theme violations
./scripts/cleanup-all-console-logs.sh   # Remove console.log
./scripts/convert-relative-imports.sh   # Fix import paths
```
