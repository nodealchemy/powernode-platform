# Worker CLAUDE.md

Sidekiq standalone worker for Powernode.

## Critical Rules

- Jobs inherit from `BaseJob`, implement `execute()` method
- API-only communication with server
- `Rails.logger` - no puts/print
- `# frozen_string_literal: true` pragma required

## Context-Aware Documentation

| When working on | Load this documentation |
|-----------------|------------------------|
| `app/jobs/*` | [BACKGROUND_JOB_ENGINEER_SPECIALIST.md](../docs/backend/BACKGROUND_JOB_ENGINEER_SPECIALIST.md) |
| AI workflow jobs | [WORKFLOW_SYSTEM_STANDARDS.md](../docs/platform/WORKFLOW_SYSTEM_STANDARDS.md) |
| MCP jobs | [MCP_CONFIGURATION.md](../docs/platform/MCP_CONFIGURATION.md) |
| Billing jobs | [BILLING_ENGINE_DEVELOPER_SPECIALIST.md](../docs/backend/BILLING_ENGINE_DEVELOPER_SPECIALIST.md) |
