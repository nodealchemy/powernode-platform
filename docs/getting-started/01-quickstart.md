# Quickstart

> Run Powernode locally in 10 minutes.

> Status: active

Powernode is open-source mission control for AI agent fleets. This quickstart gets the platform running on a single machine so you can log in, kick the tires, and see the agent surface.

## Table of Contents

- [Prerequisites](#prerequisites)
- [1. Clone and install dependencies](#1-clone-and-install-dependencies)
- [2. Install and start all services](#2-install-and-start-all-services)
- [3. Access the application](#3-access-the-application)
- [4. Create your first user](#4-create-your-first-user)
- [Running tests](#running-tests)
- [Common development tasks](#common-development-tasks)
- [Code quality](#code-quality)
- [Architecture at a glance](#architecture-at-a-glance)
- [Troubleshooting](#troubleshooting)
- [Where to go next](#where-to-go-next)

## Prerequisites

| Requirement | Version | Verify Command |
|-------------|---------|----------------|
| Node.js | 20+ | `node --version` |
| Ruby | 3.2.8 (pinned) | `ruby --version` |
| PostgreSQL + pgvector | recent stable, `pgvector` extension installed | `psql --version` |
| Redis | 7+ | `redis-server --version` |
| Docker | 24+ | `docker --version` |

A working `systemd` user session is assumed for the recommended path. If you do not have systemd, see the manual workflow in [contributing/development-setup.md](../contributing/development-setup.md).

## 1. Clone and install dependencies

```bash
git clone https://github.com/nodealchemy/powernode-platform.git
cd powernode-platform

# Install gems and packages
cd server && bundle install
cd ../frontend && npm install
cd ../worker && bundle install
cd ..

# Create the database, run migrations, and seed
cd server && bundle exec rails db:create db:migrate db:seed
cd ..
```

The seed step creates the initial admin account plus the AI provider records, skills, and intervention policies the platform needs to boot.

## 2. Install and start all services

```bash
# One-time: install systemd units + config under /etc/powernode/
sudo scripts/systemd/powernode-installer.sh install

# Start backend + worker + worker-web + frontend
sudo systemctl start powernode.target

# Confirm everything came up
sudo scripts/systemd/powernode-installer.sh status
```

The installer creates four service units (`powernode-backend@default`, `powernode-worker@default`, `powernode-worker-web@default`, `powernode-frontend@default`) plus the `powernode.target` group.

## 3. Access the application

| Service | URL |
|---------|-----|
| Frontend | http://localhost:3001 |
| Backend API | http://localhost:3000 |
| API health | http://localhost:3000/api/v1/health |
| Worker HTTP control plane | http://localhost:4567 (Sidekiq dashboard at http://localhost:4567/sidekiq) |

If anything is unreachable, see [Troubleshooting](#troubleshooting).

## 4. Create your first user

The seeded admin works for poking around. For routine work, create a personal account:

```bash
cd server && bundle exec rails c
User.create!(email: 'dev@example.com', password: 'DevPassword123!', name: 'Developer')
```

Log in at http://localhost:3001 with the credentials you just created.

## Running tests

```bash
# Backend tests (RSpec)
cd server && bundle exec rspec --format progress

# Frontend tests
cd frontend && CI=true npm test

# E2E tests (Playwright)
cd frontend && npx playwright test

# Type checking
cd frontend && npx tsc --noEmit
```

Long-form testing guidance lives in [guides/testing.md](../guides/testing.md) and [guides/e2e-testing.md](../guides/e2e-testing.md).

## Common development tasks

### Add a new API endpoint

1. Add the route in `server/config/routes.rb`.
2. Create the controller under `server/app/controllers/api/v1/`.
3. Use the standard response helpers:
   ```ruby
   render_success(data: { ... })
   render_error(message: 'Error', status: :bad_request)
   ```
4. Add request specs under `server/spec/requests/`.

### Add a new frontend page

1. Create the page under `frontend/src/pages/app/`.
2. Add the route in `frontend/src/App.tsx`.
3. Wrap content in `PageContainer` for consistent layout, breadcrumbs, and actions.

### Add a background job

1. Create the job under `worker/app/jobs/`.
2. Inherit from `BaseJob` and implement `execute`.
3. Enqueue from the server via the worker HTTP API — the server itself does not run Sidekiq.

## Code quality

```bash
# Full pre-commit gate (specs + TypeScript + patterns)
./scripts/validate.sh

# Pattern-only sweep
./scripts/quick-pattern-check.sh

# Auto-fix theme + import drift
./scripts/fix-hardcoded-colors.sh
./scripts/cleanup-all-console-logs.sh
```

## Architecture at a glance

```
powernode-platform/
├── server/           Rails 8 API
├── frontend/         React + TypeScript + Tailwind
├── worker/           Standalone Sidekiq
├── extensions/       Submodules (system, supply-chain, marketing public; business, trading private)
├── docs/             You are here
├── scripts/          Dev + ops scripts
└── docker/           Container assets
```

Deeper reading: [concepts/architecture.md](../concepts/architecture.md).

## Troubleshooting

### Services will not start

```bash
journalctl -u powernode-backend@default --since "5 min ago" --no-pager
sudo systemctl reset-failed 'powernode-*'
sudo systemctl start powernode.target
```

### Database issues

```bash
cd server
bundle exec rails db:reset      # WARNING: drops and recreates the database
bundle exec rails db:migrate
```

### Frontend build errors

```bash
cd frontend
rm -rf node_modules
npm install
npm run typecheck
```

### Redis connection issues

```bash
redis-cli ping     # expect: PONG
```

More common errors live in [04-troubleshooting.md](./04-troubleshooting.md).

## Where to go next

1. Ship your first agent → [02-first-agent.md](./02-first-agent.md)
2. Understand the extension model → [03-extensions.md](./03-extensions.md)
3. Read the architecture → [../concepts/architecture.md](../concepts/architecture.md)
4. Become a contributor → [../contributing/development-setup.md](../contributing/development-setup.md)

---

## Materials previously at

- `docs/QUICKSTART.md`

_Last verified: 2026-06-04_
