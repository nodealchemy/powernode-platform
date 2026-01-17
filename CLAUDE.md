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

## Specialist Documentation Index

**Task Delegation**: See [MCP Configuration](docs/platform/MCP_CONFIGURATION.md#task-tool-specialist-delegation) for spawning specialists via Task tool.

### Backend Specialists
| Specialist | Documentation | Model |
|------------|---------------|-------|
| Rails Architect | [RAILS_ARCHITECT_SPECIALIST.md](docs/backend/RAILS_ARCHITECT_SPECIALIST.md) | sonnet |
| Data Modeler | [DATA_MODELER_SPECIALIST.md](docs/backend/DATA_MODELER_SPECIALIST.md) | sonnet |
| API Developer | [API_DEVELOPER_SPECIALIST.md](docs/backend/API_DEVELOPER_SPECIALIST.md) | sonnet |
| Payment Integration | [PAYMENT_INTEGRATION_SPECIALIST.md](docs/backend/PAYMENT_INTEGRATION_SPECIALIST.md) | **opus** |
| Billing Engine | [BILLING_ENGINE_DEVELOPER_SPECIALIST.md](docs/backend/BILLING_ENGINE_DEVELOPER_SPECIALIST.md) | **opus** |
| Background Jobs | [BACKGROUND_JOB_ENGINEER_SPECIALIST.md](docs/backend/BACKGROUND_JOB_ENGINEER_SPECIALIST.md) | sonnet |

### Frontend Specialists
| Specialist | Documentation | Model |
|------------|---------------|-------|
| React Architect | [REACT_ARCHITECT_SPECIALIST.md](docs/frontend/REACT_ARCHITECT_SPECIALIST.md) | sonnet |
| UI Components | [UI_COMPONENT_DEVELOPER_SPECIALIST.md](docs/frontend/UI_COMPONENT_DEVELOPER_SPECIALIST.md) | haiku |
| Dashboard | [DASHBOARD_SPECIALIST.md](docs/frontend/DASHBOARD_SPECIALIST.md) | sonnet |
| Admin Panel | [ADMIN_PANEL_DEVELOPER_SPECIALIST.md](docs/frontend/ADMIN_PANEL_DEVELOPER_SPECIALIST.md) | sonnet |

### Infrastructure & Testing Specialists
| Specialist | Documentation | Model |
|------------|---------------|-------|
| DevOps Engineer | [DEVOPS_ENGINEER_SPECIALIST.md](docs/infrastructure/DEVOPS_ENGINEER_SPECIALIST.md) | **opus** |
| Security | [SECURITY_SPECIALIST.md](docs/infrastructure/SECURITY_SPECIALIST.md) | **opus** |
| Performance | [PERFORMANCE_OPTIMIZER.md](docs/infrastructure/PERFORMANCE_OPTIMIZER.md) | **opus** |
| Backend Testing | [BACKEND_TEST_ENGINEER_SPECIALIST.md](docs/testing/BACKEND_TEST_ENGINEER_SPECIALIST.md) | sonnet |
| Frontend Testing | [FRONTEND_TEST_ENGINEER_SPECIALIST.md](docs/testing/FRONTEND_TEST_ENGINEER_SPECIALIST.md) | haiku |

### Service Specialists
| Specialist | Documentation | Model |
|------------|---------------|-------|
| Project Manager | [PROJECT_MANAGER_SPECIALIST.md](docs/services/PROJECT_MANAGER_SPECIALIST.md) | sonnet |
| Notifications | [NOTIFICATION_ENGINEER.md](docs/services/NOTIFICATION_ENGINEER.md) | sonnet |
| Documentation | [DOCUMENTATION_SPECIALIST.md](docs/services/DOCUMENTATION_SPECIALIST.md) | haiku |
| Analytics | [ANALYTICS_ENGINEER.md](docs/services/ANALYTICS_ENGINEER.md) | **opus** |

---

## Quick Reference - Critical Rules

### Git Rules
- **NEVER** commit unless explicitly requested
- **NEVER** include Claude attribution in commits
- Branch strategy: `develop` → `feature/*` → `release/*` → `main`

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

## Task Tool Delegation

For complex tasks, spawn specialists using the Task tool:

```
Task({
  description: "Brief task description",
  subagent_type: "general-purpose",
  model: "sonnet",  // or "opus" for critical, "haiku" for routine
  prompt: `You are a [Specialist] for Powernode.
Reference: [path/to/SPECIALIST.md]
Task: [specific task]
Follow patterns in specialist documentation.`
})
```

**Model Selection**:
- **opus**: Payment, Security, DevOps, Performance, Analytics, Billing
- **sonnet**: Rails, React, Data, API, Jobs, Dashboard, Admin, Backend Tests, Project Manager, Notifications
- **haiku**: UI Components, Documentation, Frontend Tests

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
