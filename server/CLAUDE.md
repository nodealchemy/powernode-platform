# Server CLAUDE.md

Rails 8 API backend for Powernode.

## Critical Rules

- `# frozen_string_literal: true` pragma in every .rb file
- `Rails.logger` only - no puts/print
- Always use `render_success()`, `render_error()`
- Use `current_user.has_permission?('name')` - NEVER `permissions.include?()`
- Controllers: `Api::V1` namespace, inherit ApplicationController
- Migrations: Index in `t.references` declaration - never separate

## Context-Aware Documentation

| When working on | Load this documentation |
|-----------------|------------------------|
| `app/services/mcp/*` | [MCP_CONFIGURATION.md](../docs/platform/MCP_CONFIGURATION.md) |
| `app/models/ai/*` | [AI_ORCHESTRATION_GUIDE.md](../docs/platform/AI_ORCHESTRATION_GUIDE.md) |
| `app/controllers/api/v1/*` | [API_RESPONSE_STANDARDS.md](../docs/platform/API_RESPONSE_STANDARDS.md) |
| `app/services/billing/*` | [BILLING_ENGINE_DEVELOPER_SPECIALIST.md](../docs/backend/BILLING_ENGINE_DEVELOPER_SPECIALIST.md) |
| `app/services/payments/*` | [PAYMENT_INTEGRATION_SPECIALIST.md](../docs/backend/PAYMENT_INTEGRATION_SPECIALIST.md) |
| `db/migrate/*` | [UUID_SYSTEM_IMPLEMENTATION.md](../docs/platform/UUID_SYSTEM_IMPLEMENTATION.md) |
| Permission models/services | [PERMISSION_SYSTEM_REFERENCE.md](../docs/platform/PERMISSION_SYSTEM_REFERENCE.md) |

## Test Execution

```bash
bundle exec rspec spec/                          # Run full suite
bundle exec rspec spec/path_spec.rb              # Run single file
bundle exec rspec spec/path_spec.rb:42           # Run single example
```

- Uses `DatabaseCleaner` with `:deletion` strategy (avoids `TRUNCATE` deadlocks)
- Transactional fixtures enabled — each test rolls back automatically
- Frontend tests and TypeScript checks are always safe to run concurrently

## Worker Architecture

- This server does **NOT** run Sidekiq — the worker is a separate service (`worker/`)
- **NEVER** create job classes in `server/app/jobs/`
- The worker communicates with this server via HTTP API only
- Background work is dispatched to the worker, not run in-process

## Key Specialists

- [Rails Architect](../docs/backend/RAILS_ARCHITECT_SPECIALIST.md)
- [API Developer](../docs/backend/API_DEVELOPER_SPECIALIST.md)
- [Data Modeler](../docs/backend/DATA_MODELER_SPECIALIST.md)
- [Background Job Engineer](../docs/backend/BACKGROUND_JOB_ENGINEER_SPECIALIST.md)
