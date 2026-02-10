# CLAUDE.md

Development guidance for **Powernode** subscription platform.

## Project Overview

**Powernode** - Subscription lifecycle management platform:
- **Backend**: Rails 8 API (`./server`) - JWT auth, UUIDv7 primary keys
- **Frontend**: React TypeScript (`./frontend`) - Theme-aware, Tailwind CSS
- **Worker**: Sidekiq standalone (`./worker`) - API-only communication
- **Database**: PostgreSQL with native UUID schema
- **Payments**: Stripe, PayPal with PCI compliance

**Project Status**: See [docs/TODO.md](docs/TODO.md)

### Core Models
```
Account → User (many), Subscription (one)
Subscription → Plan, Payments, Invoices
User → Roles, Permissions, Invitations
```

---

## Specialists

For specialist documentation and Task tool delegation, see [MCP_CONFIGURATION.md](docs/platform/MCP_CONFIGURATION.md).

---

## Quick Reference - Critical Rules

### Git Rules
- **NEVER** commit unless explicitly requested
- **NEVER** include Claude attribution in commits
- Branch strategy: `develop` → `feature/*` → `release/*` → `master`
- Tag naming: **NO "v" prefix** - use `0.2.0` not `v0.2.0`
- Release branches: `release/0.2.0` (no "v" prefix)
- **Staged commits**: Group changes into logical commits by concern (models, services, controllers, frontend, tests, config) — never one monolithic commit

### Permission-Based Access Control (CRITICAL)
**Frontend MUST use permissions ONLY - NEVER roles for access control**

```typescript
// ✅ CORRECT
currentUser?.permissions?.includes('users.manage')

// ❌ FORBIDDEN
currentUser?.roles?.includes('admin')
user.role === 'manager'
```

**Backend**: Use `current_user.has_permission?('name')` - NEVER `permissions.include?()` (returns objects)

### Frontend Patterns
| Pattern | Rule |
|---------|------|
| Colors | Theme classes only: `bg-theme-*`, `text-theme-*` |
| Navigation | Flat structure - no submenus |
| Actions | ALL in PageContainer - none in page content |
| State | Global notifications only - no local success/error |
| Imports | Path aliases for cross-feature: `@/shared/`, `@/features/` |
| Logging | No `console.log` in production — use `import { logger } from '@/shared/utils/logger'` instead |
| Types | No `any` - proper TypeScript types required |

### Backend Patterns
| Pattern | Rule |
|---------|------|
| Controllers | `Api::V1` namespace, inherit ApplicationController |
| Responses | MANDATORY: `render_success()`, `render_error()` |
| Worker Jobs | Inherit BaseJob, use `execute()` method, API-only |
| Ruby Files | `# frozen_string_literal: true` pragma required |
| Logging | `Rails.logger` - no `puts`/`print` |
| Migrations | **NEVER** create separate indexes for `t.references` columns - configure index in the references declaration itself: `t.references :account, index: { unique: true }` |
| AI Namespace | `Ai::AgentTeam` not `AiAgentTeam` — always use `Ai::` prefix with `::` references |
| Seeds | After modifying seeds, run `cd server && rails db:seed` and verify completion |
| Service Restart | After API endpoint changes, restart: `sudo systemctl restart powernode-backend@default` |
| Associations | Always pair `class_name:` with `foreign_key:` — e.g. `belongs_to :provider, class_name: "Ai::Provider", foreign_key: "ai_provider_id"` |
| Foreign Keys | AI models use `ai_` prefix on FKs: `ai_agent_id`, `ai_workflow_id`, `ai_provider_id` — never bare `agent_id` |
| JSON Columns | Always use lambda defaults: `attribute :config, :json, default: -> { {} }` — never `default: {}` |
| Controller Size | Controllers MUST stay under 300 lines — extract query logic to services, serialization to concerns |
| Eager Loading | Always use `.includes()` when iterating associations — never bare `.all` followed by `.map`/`.each` accessing relations |
| Webhook Receivers | Inbound webhooks MUST return 200/202 on processing errors — NEVER 500 (causes provider retry storms) |

### Design Principles
| Principle | Rule |
|-----------|------|
| Reuse First | Always reuse existing services/patterns — never propose standalone/greenfield when infrastructure exists |
| Quality Gates | Run `cd frontend && npx tsc --noEmit` after TS changes, verify Ruby syntax after .rb changes |
| Verify Seeds | After seed modifications: `cd server && rails db:seed` — watch for association/validation errors |
| Stop & Ask | After 3 failed attempts at the same fix, stop and ask the user for guidance — do not continue iterating |

---

## Service Management

```bash
# Systemd services (requires initial install: sudo scripts/systemd/powernode-installer.sh install)
sudo systemctl start powernode.target           # Start all services
sudo systemctl stop powernode.target            # Stop all services
sudo systemctl restart powernode-backend@default  # Restart individual service
sudo scripts/systemd/powernode-installer.sh status  # Show all service status
journalctl -u powernode-backend@default -f      # Tail service logs
```

**NEVER** use manual commands (`rails server`, `sidekiq`, `npm start`)

---

## Test Execution

**RSpec**:
```bash
cd server && bundle exec rspec --format progress    # Full suite
cd server && bundle exec rspec spec/path_spec.rb    # Single file
```

**Frontend tests** - always use CI=true:
```bash
cd frontend && CI=true npm test
```

### Multi-Agent Test Rules
- Uses `DatabaseCleaner` with `:deletion` strategy — avoids `TRUNCATE` deadlocks between concurrent processes.
- Do NOT run multiple single-process rspec instances simultaneously on the same database.
- Frontend tests (`CI=true npm test`) and TypeScript checks (`npx tsc --noEmit`) are always safe to run concurrently.

### Worker Architecture (CRITICAL)
- The **server** (`server/`) is a Rails API — it does **NOT** run Sidekiq
- The **worker** (`worker/`) is a standalone Sidekiq process — it communicates with server via HTTP API only
- **NEVER** create job classes in `server/app/jobs/` — jobs belong in `worker/app/jobs/`
- **NEVER** add Sidekiq gems to `server/Gemfile`
- **NEVER** modify `worker/` files when fixing server issues

### Test Patterns Reference
| Pattern | Rule |
|---------|------|
| Factories | `spec/factories/` — use existing factories with traits (`:active`, `:paused`, `:archived`). AI factories in `spec/factories/ai/` |
| User Setup | `user_with_permissions('perm.name')` from `permission_test_helpers.rb` — never create users manually |
| Auth Headers | `auth_headers_for(user)` returns `{ Authorization: Bearer ... }` — use in all request specs |
| Response Helpers | `json_response`, `json_response_data`, `expect_success_response(data)`, `expect_error_response(msg, status)` |
| Shared Examples | `include_examples 'requires authentication'`, `'requires permission'`, `'scopes to current account'` — see `spec/support/shared_examples/` |
| AI Matchers | `be_a_valid_ai_response`, `have_execution_status(:status)`, `create_audit_log(:action)` — see `spec/support/ai_matchers.rb` |
| AI Helpers | `ProviderHelpers`, `AgentHelpers`, `WorkflowHelpers`, `SecurityHelpers` — see `spec/support/ai_test_helpers.rb` |
| E2E Pages | Page objects in `e2e/pages/` — always use existing page objects, check `e2e/pages/ai/` for AI features |
| E2E Selectors | `data-testid` first, then `class*="pattern"`, then `getByRole` — add `data-testid` to new components |
| E2E Guards | `page.on('pageerror', () => {})` in beforeEach, `if (await el.count() > 0)` for optional elements |

---

## Key Platform Documentation

| Topic | Documentation |
|-------|---------------|
| MCP Configuration | [MCP_CONFIGURATION.md](docs/platform/MCP_CONFIGURATION.md) |
| Permission System | [PERMISSION_SYSTEM_REFERENCE.md](docs/platform/PERMISSION_SYSTEM_REFERENCE.md) |
| Theme System | [THEME_SYSTEM_REFERENCE.md](docs/platform/THEME_SYSTEM_REFERENCE.md) |
| API Standards | [API_RESPONSE_STANDARDS.md](docs/platform/API_RESPONSE_STANDARDS.md) |
| UUID System | [UUID_SYSTEM_IMPLEMENTATION.md](docs/platform/UUID_SYSTEM_IMPLEMENTATION.md) |
| Workflow System | [WORKFLOW_SYSTEM_STANDARDS.md](docs/platform/WORKFLOW_SYSTEM_STANDARDS.md) |
| Development | [DEVELOPMENT.md](docs/DEVELOPMENT.md) |

---

## File Organization

**NEVER save files to project root**. Use:
- `docs/platform/` - Platform architecture
- `docs/backend/` - Backend documentation
- `docs/frontend/` - Frontend documentation
- `docs/testing/` - Testing documentation
- `docs/services/` - Service documentation
- `docs/infrastructure/` - Infrastructure documentation

---

## Automation Scripts

```bash
# Code quality
./scripts/pre-commit-quality-check.sh    # Run all checks
./scripts/fix-hardcoded-colors.sh        # Fix theme violations
./scripts/cleanup-all-console-logs.sh    # Remove console.log
./scripts/convert-relative-imports.sh    # Fix import paths

# Pattern validation
./scripts/pattern-validation.sh          # Full audit
./scripts/quick-pattern-check.sh         # Quick check

# Service management (systemd)
sudo scripts/systemd/powernode-installer.sh install           # Install units + configs
sudo scripts/systemd/powernode-installer.sh add-instance backend api2  # Add instance
sudo scripts/systemd/powernode-installer.sh status            # Show all services
```
