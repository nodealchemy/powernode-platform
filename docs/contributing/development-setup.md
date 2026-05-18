# Development Setup

> End-to-end setup for contributors working on the Powernode platform.

> Status: active

This guide covers the full contributor path: prerequisites, cloning the repo, installing dependencies, running services, running tests, and the optional proxy-based setups for remote development. If you only need to boot the app and look around, [getting-started/01-quickstart.md](../getting-started/01-quickstart.md) is shorter.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Clone the repository](#clone-the-repository)
- [Install dependencies](#install-dependencies)
- [Run the services](#run-the-services)
- [Run the tests](#run-the-tests)
- [Proxy setup for local dev](#proxy-setup-for-local-dev)
- [Configuration files](#configuration-files)
- [Multi-instance support](#multi-instance-support)
- [Troubleshooting](#troubleshooting)
- [Next steps](#next-steps)

## Prerequisites

| Requirement | Version | Verify Command |
|-------------|---------|----------------|
| Node.js | 20+ | `node --version` |
| Ruby | 3.2.8 (pinned) | `ruby --version` |
| PostgreSQL | 16+ | `psql --version` |
| Redis | 7+ | `redis-server --version` |
| Docker | 24+ | `docker --version` |

Linux with `systemd` is the smoothest path. macOS works for backend + frontend dev; the systemd installer is Linux-only.

## Clone the repository

```bash
git clone https://github.com/nodealchemy/powernode-platform.git
cd powernode-platform

# Initialize the public submodules (system, marketing, supply-chain).
git submodule update --init --recursive
```

The `extensions/business` and `extensions/trading` submodules are private; they will be absent for external contributors and the platform falls back to single-user core mode automatically. See [getting-started/03-extensions.md](../getting-started/03-extensions.md).

## Install dependencies

```bash
# Backend
cd server && bundle install
cd ..

# Frontend
cd frontend && npm install
cd ..

# Worker
cd worker && bundle install
cd ..
```

Initialize the database:

```bash
cd server
bundle exec rails db:create
bundle exec rails db:migrate
bundle exec rails db:seed
```

The seed populates AI provider records, skills, intervention policies, and the admin account. If a seed step errors out, fix the underlying association problem before re-running — partial seeds leave the system in a confusing state.

## Run the services

### Recommended: systemd

```bash
# First-time install (puts units under /etc/systemd/system + config under /etc/powernode/)
sudo scripts/systemd/powernode-installer.sh install

# Start everything
sudo systemctl start powernode.target

# Check status
sudo scripts/systemd/powernode-installer.sh status

# Stop everything
sudo systemctl stop powernode.target

# Tail a single service
journalctl -u powernode-backend@default -f
```

Individual service control:

```bash
sudo systemctl start powernode-backend@default
sudo systemctl start powernode-worker@default
sudo systemctl start powernode-worker-web@default
sudo systemctl start powernode-frontend@default

journalctl -u 'powernode-*' --since "5 min ago"
```

Do not run `rails server`, `sidekiq`, or `npm start` directly when systemd units are active — you will end up with two backends fighting for port 3000.

### Service map

| Service | Unit | Port | Restart Behavior |
|---------|------|------|------------------|
| Rails API | `powernode-backend@default` | 3000 | SIGUSR2 reload (~30 ms) via `scripts/reload-backend.sh` |
| Sidekiq | `powernode-worker@default` | — | Full restart (~28 s drain) |
| Worker HTTP API | `powernode-worker-web@default` | 4567 | If port 4567 is refused, restart THIS service |
| Frontend (Vite) | `powernode-frontend@default` | 5173 | Full restart |

## Run the tests

```bash
# Full backend suite
cd server && bundle exec rspec --format progress

# Single backend file
cd server && bundle exec rspec spec/path_spec.rb

# Frontend tests — always CI=true so they exit
cd frontend && CI=true npm test

# E2E tests (Playwright)
cd frontend && npx playwright test

# Type checking
cd frontend && npx tsc --noEmit
```

RSpec uses `DatabaseCleaner` with the `:deletion` strategy so we avoid TRUNCATE deadlocks across worker processes. Do not run multiple single-process rspec instances against the same database.

## Proxy setup for local dev

If you develop against a domain other than `localhost` (e.g. behind a reverse proxy on a dev box), Vite needs help so Hot Module Replacement points at the right URL.

### Built-in reverse proxy mode

The frontend supports a generic reverse-proxy mode via `.env.local`:

```bash
# Critical for reverse-proxy operation
VITE_BEHIND_PROXY=true
VITE_PROXY_HOST=app.example.com
VITE_PROXY_PROTOCOL=https

# API endpoints — match your proxy
VITE_API_BASE_URL=https://app.example.com/api/v1
VITE_WS_BASE_URL=wss://app.example.com/cable

# Optional: pre-declare allowed hosts (defends against DNS rebinding)
VITE_ALLOWED_HOSTS=app.example.com,staging.example.com
```

Then:

```bash
cd frontend
cp .env.proxy .env.local      # template
npm run dev -- --host 0.0.0.0
```

Or use the helper script:

```bash
cd frontend && ./scripts/dev-proxy.sh
```

### External proxy preset

If you have an existing reverse proxy on your dev host (e.g. `dev-1.example.com`), use the external-proxy preset:

```bash
cd frontend
./scripts/dev-external-proxy.sh
```

This sets `VITE_BEHIND_PROXY=true`, points HMR at `wss://<proxy-host>/@vite/hmr`, and serves on port 3001 bound to all interfaces so your proxy can reach it.

Manual form:

```bash
cd frontend
export VITE_BEHIND_PROXY=true
export VITE_PROXY_HOST=dev-1.example.com
export VITE_PROXY_PROTOCOL=https
npx vite --config vite.config.external-proxy.ts --host 0.0.0.0
```

### Nginx template

```nginx
server {
    listen 443 ssl http2;
    server_name app.example.com;

    location / {
        proxy_pass http://localhost:5173;
        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;

        # Required for HMR
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    location ~ ^/@vite/(client|hmr) {
        proxy_pass http://localhost:5173;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

### Proxy troubleshooting

| Symptom | Fix |
|---------|-----|
| "This host is not allowed" | Add the hostname to `VITE_ALLOWED_HOSTS` |
| WebSocket connection fails | Confirm `Upgrade` / `Connection: upgrade` headers are forwarded |
| HMR not working | Verify `VITE_BEHIND_PROXY=true` and `/@vite/` paths are forwarded |
| Assets load from wrong URL | Verify `VITE_PROXY_HOST` and `VITE_PROXY_PROTOCOL` match the public origin |

## Configuration files

| Service | Config File | Key Settings |
|---------|-------------|--------------|
| Global | `/etc/powernode/powernode.conf` | Base path, Ruby/Node versions |
| Backend | `/etc/powernode/backend-default.conf` | Port, binding, CORS |
| Worker | `/etc/powernode/worker-default.conf` | Redis URL, concurrency |
| Worker Web | `/etc/powernode/worker-web-default.conf` | Dashboard port |
| Frontend | `/etc/powernode/frontend-default.conf` | API URL, binding |

## Multi-instance support

The installer can layer additional instances on top of the defaults:

```bash
# Add a second backend on port 3002
sudo scripts/systemd/powernode-installer.sh add-instance backend api2
# Edit /etc/powernode/backend-api2.conf → set PORT=3002
sudo systemctl enable --now powernode-backend@api2

# Add a high-concurrency worker for AI workloads
sudo scripts/systemd/powernode-installer.sh add-instance worker ai-heavy
# Edit /etc/powernode/worker-ai-heavy.conf → set WORKER_CONCURRENCY=15
sudo systemctl enable --now powernode-worker@ai-heavy
```

## Troubleshooting

### Services will not start

```bash
journalctl -u powernode-backend@default --since "5 min ago" --no-pager
sudo systemctl reset-failed 'powernode-*'
sudo systemctl start powernode.target
```

### Port conflicts

```bash
ss -tlnp | grep :3000
# Edit /etc/powernode/backend-default.conf
sudo systemctl daemon-reload && sudo systemctl restart powernode-backend@default
```

### CORS issues

The backend allows `localhost` and the configured proxy hostname by default. If you change either, restart the backend and confirm the new value with `curl -I` against the API.

### Worker stuck draining

If a worker is draining for more than 30 seconds, do a stop + start rather than `restart`:

```bash
sudo systemctl stop powernode-worker@default
sudo systemctl start powernode-worker@default
```

## Next steps

- Conventions and patterns → [conventions.md](./conventions.md)
- Doc conventions → [doc-conventions.md](./doc-conventions.md)
- Branching and releases → [github-workflow.md](./github-workflow.md), [release-process.md](./release-process.md)
- Architecture deep dive → [../concepts/architecture.md](../concepts/architecture.md)

---

## Materials previously at

- `docs/DEVELOPMENT.md`
- `docs/frontend/EXTERNAL_PROXY_QUICKSTART.md`
- `docs/frontend/REVERSE_PROXY_SETUP.md`

_Last verified: 2026-05-17_
