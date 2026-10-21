# Backend Patterns (Rails API)

Canonical backend conventions for `server/`. Most are **mechanically enforced** — see the Enforcement column; you don't need to memorize them, the hook/scanner will flag violations. Deep how-to: [../../guides/backend.md](../../guides/backend.md).

| Pattern | Rule | Enforcement |
|---------|------|-------------|
| Controllers | `Api::V1` namespace, inherit ApplicationController | review |
| Responses | MANDATORY: `render_success()`, `render_error()` | `pattern-validation.sh` |
| Worker Jobs | Inherit BaseJob, use `execute()` method, API-only | `pattern-validation.sh` |
| Ruby Files | `# frozen_string_literal: true` pragma required | `ruby-syntax-check.sh` + `pattern-validation.sh` |
| Logging | `Rails.logger` — no `puts`/`print` | `pattern-validation.sh` |
| Migrations | `t.references` automatically creates an index — **NEVER** `add_index` for reference columns. Customize via the declaration: `t.references :account, index: { unique: true }` | `ruby-convention-check.sh` |
| Namespaces | ALL namespaced models MUST use `::` in `class_name:` — `Ai::AgentTeam` not `AiAgentTeam`, `Devops::Pipeline`, `BaaS::Tenant` | `ruby-convention-check.sh` |
| Seeds | After modifying seeds, run `cd server && rails db:seed` and verify completion | review |
| Associations | Always pair `class_name:` with `foreign_key:` — `belongs_to :provider, class_name: "Ai::Provider", foreign_key: "ai_provider_id"` | `ruby-convention-check.sh` |
| Foreign Keys | Namespaced FK prefixes: `Ai::`→`ai_`, `Devops::`→`devops_`, `BaaS::`→`baas_`. Others: explicit FK or omit if unambiguous | `ruby-convention-check.sh` (model/migrate paths only) |
| JSON Columns | Always lambda defaults: `attribute :config, :json, default: -> { {} }` — never `default: {}` | `ruby-convention-check.sh` |
| Controller Size | Controllers MUST stay under 300 lines — extract query logic to services, serialization to concerns | `controller-size-check.sh` |

## Kept in CLAUDE.md core (high-stakes, no full mechanical enforcement)

These two remain in the always-loaded core because a violation is costly and no hook fully catches them — the hooks below are only advisory nudges:

- **Eager Loading** — always use `.includes()` when iterating associations; never bare `.all` then `.map`/`.each` accessing relations. Nudge: `n-plus-one-check.sh`.
- **Webhook Receivers** — inbound webhooks MUST return 200/202 on processing errors, NEVER 500 (causes provider retry storms). Nudge: `webhook-500-check.sh`.

## Platform-scoped audit rows (no account)

Some audit rows must outlive the account that wrote them (the `account.destroyed` record and the
retained key-operation trail of an account teardown). Convention: **`audit_logs.account_id` is NULL**,
not a sentinel "platform account" row (an `Audit::PlatformAccount`).

Why NULL: a sentinel account is a fake tenant that every account-scoped query, FK and permission path
would have to learn to special-case, can be selected or deleted like a real one, and would give the
platform trail a tenant identity it should not have. NULL is invisible to tenant scopes by construction
(`account.audit_logs`, `AuditLog.by_account`, the tenant listing never match it) and is visible only to
platform auditors (`admin.audit.read`).

Guards that make NULL safe:

- `AuditLog` requires an account unless the action is in `AuditActions::PLATFORM_SCOPED_ACTIONS`.
- The DB CHECK `chk_audit_logs_account_unless_platform` enforces the same for writers that skip validations.
  Adding a platform-scoped action needs a migration updating that constraint.
- `Account has_many :audit_logs, dependent: :restrict_with_exception`; only the teardown deletes them.

Rows stay in the one global hash chain. `account_id` is part of the row hash, so a row is never UPDATEd to
NULL: it is copied as a new chained row that carries `original_integrity_hash` / `original_sequence_number`,
and `account.destroyed` records the deleted sequence range. Key-operation actions that get retained are an
explicit list (`AuditActions::CORE_KEY_OPERATION_ACTIONS` plus `register_key_operation_actions`), never a pattern.

