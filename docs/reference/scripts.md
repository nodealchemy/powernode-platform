# Scripts Reference

> Status: active

> Authoritative catalogue of repository-level scripts under `scripts/`.

## Table of Contents

- [Overview](#overview)
- [Code Quality](#code-quality)
- [Pre-Commit & Validation](#pre-commit--validation)
- [Security](#security)
- [Git](#git)
- [Service Lifecycle](#service-lifecycle)
- [Controller Analysis](#controller-analysis)
- [Version Management](#version-management)
- [Testing](#testing)
- [MCP Testing](#mcp-testing)
- [Backup](#backup)
- [Systemd](#systemd)
- [Monitoring](#monitoring)
- [Infrastructure](#infrastructure)
- [Extensions](#extensions)
- [Marketing](#marketing)

## Overview

Repository scripts live under `scripts/` at the project root. Subdirectories group related scripts by lifecycle stage (backup, systemd, monitoring). This reference catalogues every script available in the platform repo; extension-specific scripts that live under `extensions/*/scripts/` are documented inside the relevant extension.

## Code Quality

| Script | Description |
|--------|-------------|
| `add-frozen-string-literals.sh` | Add `# frozen_string_literal: true` pragma to Ruby files |
| `audit-role-access-control.sh` | Audit frontend code for forbidden role-based access control |
| `cleanup-all-console-logs.sh` | Remove `console.log` statements from frontend code |
| `convert-relative-imports.sh` | Convert relative imports to path aliases (`@/`) |
| `enhanced-pattern-cleanup.sh` | Pattern cleanup with advanced fixes |
| `fix-hardcoded-colors.sh` | Convert hardcoded colors to theme classes |
| `generate-pattern-stats.sh` | Generate statistics on pattern compliance |
| `pattern-validation.sh` | Full pattern audit across codebase |
| `quick-pattern-check.sh` | Quick pattern compliance check |
| `refined-pattern-validation.sh` | Refined pattern validation with detailed output |

## Pre-Commit & Validation

| Script | Description |
|--------|-------------|
| `pre-commit-pattern-check.sh` | Git pre-commit hook for pattern checks |
| `pre-commit-quality-check.sh` | Git pre-commit hook for quality checks |
| `validate.sh` | Full validation suite (RSpec + TypeScript + patterns). Use `--skip-tests` for TS + patterns only |
| `install-git-hooks.sh` | Install git hooks (quality + pattern + secret scan) for the repository |

## Security

| Script | Description |
|--------|-------------|
| `security-cleanup.sh` | Clean up security-related issues |
| `security-history-scan.sh` | Full git history secret scan (main repo + submodules, all branches). Run on demand before audits or contributor changes |
| `security-scan.sh` | Run security scanning tools (gitleaks + ancillary checks) |

## Git

| Script | Description |
|--------|-------------|
| `git-flow-init.sh` | Initialise git-flow branching model |

## Service Lifecycle

| Script | Description |
|--------|-------------|
| `reload-backend.sh` | Clear bootsnap cache and soft-restart Puma via SIGUSR2. Used by the Claude Code Stop hook for mid-turn reloads after `.rb` edits |
| `health-check.sh` | Headless service health check for the running platform (backend / worker / frontend) |

## Controller Analysis

| Script | Description |
|--------|-------------|
| `categorize-controllers.sh` | Categorise controllers by namespace and function |
| `update-api-responses.sh` | Update controllers to use standard API response methods |

## Version Management

| Script | Description |
|--------|-------------|
| `version-bump.sh` | Bump version numbers across the project |
| `version-manager.sh` | Version management utilities |

## Testing

| Script | Description |
|--------|-------------|
| `run-file-integration-tests.sh` | Run file storage integration tests |

## MCP Testing

| Script | Description |
|--------|-------------|
| `mcp-smoke-test.sh` | MCP tool execution smoke test |

## Backup

There are **no** backup shell scripts. Database backups and restores run as
standalone-worker maintenance jobs (`Maintenance::ScheduledBackupJob`,
`DatabaseBackupJob`, `DatabaseRestoreJob`, `BackupCleanupJob`) scheduled in
`worker/config/sidekiq.yml`; they wrap `pg_dump -Fc` / `pg_restore`. For the
operator runbook (manual backups, restores, retention) see
[../operations/postgres-backup.md](../operations/postgres-backup.md).

## Systemd

Inside `scripts/systemd/`:

| Script | Description |
|--------|-------------|
| `powernode-installer.sh` | Install / manage systemd units. Commands: `install`, `add-instance`, `status` |
| `powernode-backend.sh` | Backend service wrapper |
| `powernode-frontend.sh` | Frontend service wrapper |
| `powernode-worker.sh` | Worker service wrapper |
| `powernode-worker-web.sh` | Sidekiq Web dashboard wrapper |
| `powernode-reverse-proxy.sh` | Reverse-proxy service wrapper (Traefik) |

Companion directories used by the installer:

- `scripts/systemd/configs/` — sample environment-conf files copied into `/etc/powernode/`
- `scripts/systemd/units/` — systemd unit templates installed under `/etc/systemd/system/`
- `scripts/systemd/nginx/` — nginx configuration assets

## Monitoring

Inside `scripts/monitoring/`:

| Script | Description |
|--------|-------------|
| `tmux-monitor.sh` | tmux-based multi-pane service monitor |
| `ws-monitor.sh` | WebSocket connection monitor |

## Infrastructure

| Script | Description |
|--------|-------------|
| `manage-proxy-hosts.sh` | Manage reverse-proxy trusted hosts and generate `.mcp.json`. Commands: `add`, `remove`, `list`, `sync`, `generate-mcp`, `status` |

## Extensions

| Script | Description |
|--------|-------------|
| `setup-extension-frontend-symlinks.sh` | Symlink each extension's `frontend/node_modules` to the parent for Jest test resolution. Run once after a fresh `frontend/` install |

## Marketing

| Script | Description |
|--------|-------------|
| `capture-marketing-screenshots.js` | Capture marketing-site screenshots via Playwright (Node.js, not shell) |

---

## Related docs

- [../operations/production-deployment.md](../operations/production-deployment.md) — Production deployment runbook
- [../operations/docker-swarm.md](../operations/docker-swarm.md) — Docker Swarm operational procedures
- [../contributing/development-setup.md](../contributing/development-setup.md) — Local development scripts

## Materials previously at

- `docs/infrastructure/SCRIPTS_REFERENCE.md`

_Last verified: 2026-06-03_
