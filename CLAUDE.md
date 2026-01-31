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
| Logging | No `console.log` in production |
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

---

## Service Management

```bash
# Primary - use auto-dev.sh
scripts/auto-dev.sh ensure    # Start all services
scripts/auto-dev.sh status    # Check status
scripts/auto-dev.sh stop      # Stop all
scripts/auto-dev.sh health    # Health check
```

**NEVER** use manual commands (`rails server`, `sidekiq`, `npm start`)

---

## Test Execution

**Before running RSpec tests**:
```bash
pkill -f rspec 2>/dev/null || true; sleep 1; bundle exec rspec --format progress
```

**Frontend tests** - always use CI=true:
```bash
cd frontend && CI=true npm test
```

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
```
