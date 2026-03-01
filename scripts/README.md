# Powernode Process Management Scripts

This directory contains systemd-based service management for the Powernode platform, supporting multi-instance deployment, configurable environments, and boot-time startup.

## Overview

Services are managed via **systemd template units** (`@.service`). Each service type supports multiple named instances (e.g., `powernode-backend@default`, `powernode-backend@api2`), each with its own configuration file in `/etc/powernode/`.

### Services

| Service | Unit | Default Port | Purpose |
|---------|------|-------------|---------|
| Backend | `powernode-backend@.service` | 3000 | Rails/Puma API server |
| Worker | `powernode-worker@.service` | — | Sidekiq background jobs |
| Worker Web | `powernode-worker-web@.service` | 4567 | Sidekiq web dashboard |
| Frontend | `powernode-frontend@.service` | 3001 | Vite dev server |
| Target | `powernode.target` | — | Groups all services |

## Quick Start

```bash
# Install (one-time setup)
sudo scripts/systemd/powernode-installer.sh install

# Start all services
sudo systemctl start powernode.target

# Check status
sudo scripts/systemd/powernode-installer.sh status

# Stop all services
sudo systemctl stop powernode.target
```

## Installer Commands

```bash
sudo scripts/systemd/powernode-installer.sh install [--production]
sudo scripts/systemd/powernode-installer.sh uninstall [--purge]
sudo scripts/systemd/powernode-installer.sh add-instance <service> <name>
sudo scripts/systemd/powernode-installer.sh remove-instance <service> <name>
sudo scripts/systemd/powernode-installer.sh enable <service> [instance]
sudo scripts/systemd/powernode-installer.sh disable <service> [instance]
sudo scripts/systemd/powernode-installer.sh status
sudo scripts/systemd/powernode-installer.sh generate-nginx <instance>
```

## Individual Service Control

```bash
# Start/stop/restart individual services
sudo systemctl start powernode-backend@default
sudo systemctl stop powernode-worker@default
sudo systemctl restart powernode-frontend@default

# Enable/disable at boot
sudo systemctl enable powernode-backend@default
sudo systemctl disable powernode-frontend@default
```

## Viewing Logs

```bash
# Follow logs for a specific service
journalctl -u powernode-backend@default -f

# View all Powernode logs
journalctl -u 'powernode-*' --since "5 min ago"

# View logs for a specific time range
journalctl -u powernode-worker@default --since "2025-01-01" --until "2025-01-02"
```

## Multi-Instance Support

```bash
# Add a second backend on port 3002
sudo scripts/systemd/powernode-installer.sh add-instance backend api2
# Edit /etc/powernode/backend-api2.conf → PORT=3002
sudo systemctl enable --now powernode-backend@api2

# Add a high-concurrency worker
sudo scripts/systemd/powernode-installer.sh add-instance worker ai-heavy
# Edit /etc/powernode/worker-ai-heavy.conf → WORKER_CONCURRENCY=15
sudo systemctl enable --now powernode-worker@ai-heavy

# Remove an instance
sudo scripts/systemd/powernode-installer.sh remove-instance backend api2
```

## Configuration

Configuration files live in `/etc/powernode/`:

| File | Purpose |
|------|---------|
| `powernode.conf` | Global: base path, RVM/nvm paths, Ruby/Node versions, mode |
| `backend-default.conf` | Backend: PORT, RAILS_ENV, Redis, JWT, service tokens |
| `worker-default.conf` | Worker: WORKER_ENV, REDIS_URL, concurrency, auth token |
| `worker-web-default.conf` | Worker Web: host, port, Redis |
| `frontend-default.conf` | Frontend: PORT, VITE_API_BASE_URL |

Config files are never overwritten on reinstall — only new files are created from templates.

## Architecture

### Dependency Chain

```
postgresql + redis
      ↓
powernode-backend@*
      ↓ (After, soft)
powernode-worker@*  ←── Requires redis
      ↓ (BindsTo)
powernode-worker-web@*

powernode-frontend@* (independent, skipped if /etc/powernode/no-frontend exists)
```

### Wrapper Scripts

Each service has a wrapper script (`scripts/systemd/powernode-*.sh`) that:
1. Sources RVM or nvm for the correct Ruby/Node version
2. Uses `exec` so the application process becomes PID 1 for proper signal handling

### Production Mode

```bash
sudo scripts/systemd/powernode-installer.sh install --production
```

Production mode:
- Creates a `powernode` system user (nologin shell)
- Sets `POWERNODE_MODE=production`
- Creates `/etc/powernode/no-frontend` flag (disables frontend dev server)
- Enables security hardening: `NoNewPrivileges`, `ProtectSystem=strict`, `PrivateTmp`
- Frontend is served via nginx (use `generate-nginx` to create config)

## Port Reference

| Service | Default Port | Access |
|---------|-------------|--------|
| Backend API | 3000 | `http://localhost:3000` |
| Frontend | 3001 | `http://localhost:3001` |
| Worker Web UI | 4567 | `http://localhost:4567` |
| Backend Health | 3000 | `http://localhost:3000/api/v1/health` |

## Troubleshooting

### Service Won't Start

```bash
# Check the journal for errors
journalctl -u powernode-backend@default --since "5 min ago" --no-pager

# Reset failed state
sudo systemctl reset-failed powernode-backend@default
sudo systemctl start powernode-backend@default
```

### Port Already in Use

```bash
# Find what's using the port
ss -tlnp | grep :3000

# Kill the process and restart
sudo systemctl restart powernode-backend@default
```

### RVM/Ruby Issues

```bash
# Verify config has correct paths
cat /etc/powernode/powernode.conf | grep -E 'RVM|RUBY'

# Test wrapper script manually
sudo -u $(whoami) /path/to/scripts/systemd/powernode-backend.sh
```

### Reinstall from Scratch

```bash
sudo scripts/systemd/powernode-installer.sh uninstall --purge
sudo scripts/systemd/powernode-installer.sh install
```

## File Structure

```
scripts/
├── systemd/
│   ├── powernode-installer.sh        # Main installer/manager
│   ├── powernode-backend.sh          # Backend wrapper (sources RVM)
│   ├── powernode-worker.sh           # Worker wrapper (sources RVM)
│   ├── powernode-worker-web.sh       # Worker web wrapper (sources RVM)
│   ├── powernode-frontend.sh         # Frontend wrapper (sources nvm)
│   ├── units/
│   │   ├── powernode-backend@.service
│   │   ├── powernode-worker@.service
│   │   ├── powernode-worker-web@.service
│   │   ├── powernode-frontend@.service
│   │   └── powernode.target
│   ├── configs/
│   │   ├── powernode.conf            # Global config template
│   │   ├── backend-default.conf
│   │   ├── worker-default.conf
│   │   ├── worker-web-default.conf
│   │   └── frontend-default.conf
│   └── nginx/
│       └── powernode-frontend.conf.template
├── backup/                           # Database backup/restore
├── deployment/                       # Deployment utilities
└── [code quality scripts]            # Linting, patterns, cleanup
```

## Other Utility Scripts

```bash
# Code quality
./scripts/pre-commit-quality-check.sh    # Run all checks
./scripts/fix-hardcoded-colors.sh        # Fix theme violations
./scripts/cleanup-all-console-logs.sh    # Remove console.log
./scripts/convert-relative-imports.sh    # Fix import paths

# Pattern validation
./scripts/pattern-validation.sh          # Full audit
./scripts/quick-pattern-check.sh         # Quick check
```
