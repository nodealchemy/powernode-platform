# Scripts Reference

47 shell scripts organized by function. All in the `scripts/` directory.

---

## Code Quality (10 scripts)

| Script | Description |
|--------|-------------|
| `add-frozen-string-literals.sh` | Add `# frozen_string_literal: true` pragma to Ruby files |
| `audit-role-access-control.sh` | Audit frontend code for forbidden role-based access control |
| `cleanup-all-console-logs.sh` | Remove `console.log` statements from frontend code |
| `convert-relative-imports.sh` | Convert relative imports to path aliases (`@/`) |
| `enhanced-pattern-cleanup.sh` | Enhanced pattern cleanup with advanced fixes |
| `fix-hardcoded-colors.sh` | Convert hardcoded colors to theme classes |
| `generate-pattern-stats.sh` | Generate statistics on pattern compliance |
| `pattern-validation.sh` | Full pattern audit across codebase |
| `quick-pattern-check.sh` | Quick pattern compliance check |
| `refined-pattern-validation.sh` | Refined pattern validation with detailed output |

## Pre-Commit & Validation (4 scripts)

| Script | Description |
|--------|-------------|
| `pre-commit-pattern-check.sh` | Git pre-commit hook for pattern checks |
| `pre-commit-quality-check.sh` | Git pre-commit hook for quality checks |
| `validate.sh` | Full validation suite (RSpec + TypeScript + patterns). Use `--skip-tests` for TS + patterns only |
| `install-git-hooks.sh` | Install git hooks for the repository |

## Security (2 scripts)

| Script | Description |
|--------|-------------|
| `security-cleanup.sh` | Clean up security-related issues |
| `security-scan.sh` | Run security scanning tools |

## Git (1 script)

| Script | Description |
|--------|-------------|
| `git-flow-init.sh` | Initialize git-flow branching model |

## Controller Analysis (2 scripts)

| Script | Description |
|--------|-------------|
| `categorize-controllers.sh` | Categorize controllers by namespace and function |
| `update-api-responses.sh` | Update controllers to use standard API response methods |

## Version Management (2 scripts)

| Script | Description |
|--------|-------------|
| `version-bump.sh` | Bump version numbers across the project |
| `version-manager.sh` | Version management utilities |

## Testing (1 script)

| Script | Description |
|--------|-------------|
| `run-file-integration-tests.sh` | Run file storage integration tests |

## MCP Testing (2 scripts)

| Script | Description |
|--------|-------------|
| `mcp-smoke-test.sh` | MCP tool execution smoke test |
| `sse-mcp-smoke.sh` | SSE MCP endpoint smoke test |

## Deployment (8 scripts)

Located in `scripts/deployment/`:

| Script | Description |
|--------|-------------|
| `deploy.sh` | Main deployment script |
| `backup.sh` | Pre-deployment backup |
| `environment-setup.sh` | Environment configuration setup |
| `health-check.sh` | Local health check after deployment |
| `health-check-remote.sh` | Remote server health check |
| `rollback.sh` | Deployment rollback |
| `setup-secrets.sh` | Configure production secrets |
| `smoke-tests.sh` | Post-deployment smoke tests |

Plus `deploy-remote.sh` and `setup-remote-deployment.sh` at the top level.

## Backup (2 scripts)

Located in `scripts/backup/`:

| Script | Description |
|--------|-------------|
| `backup-database.sh` | PostgreSQL database backup (supports S3 upload) |
| `restore-database.sh` | Database restore from backup |

## Docker (3 scripts)

Located in `scripts/docker/`:

| Script | Description |
|--------|-------------|
| `powernode-build.sh` | Build Docker images for all services |
| `powernode-deploy.sh` | Deploy via Docker Compose |
| `powernode-package.sh` | Package Docker images for distribution |

## Systemd (5 scripts)

Located in `scripts/systemd/`:

| Script | Description |
|--------|-------------|
| `powernode-installer.sh` | Install/manage systemd units. Commands: `install`, `add-instance`, `status` |
| `powernode-backend.sh` | Backend service wrapper |
| `powernode-frontend.sh` | Frontend service wrapper |
| `powernode-worker.sh` | Worker service wrapper |
| `powernode-worker-web.sh` | Sidekiq Web dashboard wrapper |

## Monitoring (2 scripts)

Located in `scripts/monitoring/`:

| Script | Description |
|--------|-------------|
| `tmux-monitor.sh` | tmux-based multi-pane service monitor |
| `ws-monitor.sh` | WebSocket connection monitor |

## Infrastructure (1 script)

| Script | Description |
|--------|-------------|
| `manage-proxy-hosts.sh` | Manage Nginx Proxy Manager hosts via API |
