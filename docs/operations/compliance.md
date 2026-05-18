# Compliance Posture

> **When to use this runbook**: planning a deployment that must satisfy regulatory requirements (GDPR, CCPA, HIPAA, PCI DSS, SOC 2), responding to a security questionnaire from a prospective customer, or evidencing compliance during an audit.

This document describes what Powernode-the-software supports out of the box, what it leaves to operator configuration, and what it explicitly does **not** claim. **Powernode-the-software is not certified for any specific compliance regime.** Certification is operator-owned — this doc tells you what the platform makes easy versus hard.

## Contents

- [Data classification](#data-classification)
- [Retention](#retention)
- [GDPR / CCPA](#gdpr--ccpa)
- [HIPAA](#hipaa)
- [PCI DSS](#pci-dss)
- [SOC 2](#soc-2)
- [Encryption posture](#encryption-posture)
- [Access controls](#access-controls)
- [Audit log evidence](#audit-log-evidence)
- [Where to look during an audit](#where-to-look-during-an-audit)

## Data classification

Powernode stores the following classes of data. Treat each according to your regulatory scope.

| Class | Examples | Default storage | Notes |
|-------|----------|-----------------|-------|
| **Account/user PII** | name, email, password hash, last login | Postgres `users`, `accounts` | Email is the primary identifier; minimize collection if your regime requires data minimization |
| **Auth secrets** | password hashes (bcrypt), JWT secrets, API keys | Postgres + Vault | Passwords never logged. Vault stores rotation-capable secrets |
| **Agent/conversation content** | user prompts, AI responses, tool call payloads | Postgres `ai_conversations`, `ai_messages` | May contain customer-supplied PII inside prompts. Audit before retaining indefinitely |
| **Audit logs** | every state change with actor + resource + metadata | Postgres `audit_logs` | Append-only; never edited. Required for most compliance regimes |
| **Knowledge entries** | platform knowledge contributions, learnings, embeddings | Postgres `ai_shared_knowledges`, `ai_compound_learnings` | May contain operational/customer details depending on what agents recorded |
| **Vector embeddings** | 1536-dim OpenAI, 768-dim Ollama-default | Postgres pgvector columns | Re-derivable from source text |
| **Payment data** | tokens, last4, brand | Stripe/PayPal vault — NOT in Postgres | Powernode stores only payment-method *tokens* (provider-side opaque IDs). Full card data never enters the platform |
| **Generated artifacts** | PDF/CSV reports, file uploads | Worker filesystem (`worker/storage/`) | Treat the storage volume as containing whatever data the report queries returned |

## Retention

| Data | Default retention | Configured via | Compliance note |
|------|-------------------|----------------|------------------|
| Audit logs | indefinite | none — append-only | Most regimes require 1-7 years. Default is fine. Add manual archival for cost. |
| Conversations | indefinite | none | Consider auto-expiry for GDPR data-minimization. No built-in TTL. |
| Generated reports | 30 days (cleanup script) | `scripts/backup/...` retention env vars | Adjust to your regime |
| Background job dead set | 14 days (Sidekiq default) | `worker/config/sidekiq.yml` | Operational only — no customer data |
| Loki logs | 7 days | `configs/logging/loki-config.yml` `retention_period` | PCI requires 1 year minimum; adjust before claiming PCI |
| Postgres backups | 30 days local + S3 lifecycle | `scripts/backup/backup-database.sh` `RETENTION_DAYS` | Match to longest applicable retention |

## GDPR / CCPA

What the platform supports:

- **Right to erasure**: `Compliance::AccountTerminationJob` (in `worker/`) deletes an account and all associated data atomically.
- **Right of access**: data export endpoint (`/api/v1/users/me/data_export` — verify present in your release) bundles the user's personal data into a JSON download.
- **Audit log of access**: `AuditLog.where(user_id: X)` evidences who touched what data and when. The `read` actions are logged for sensitive resources.
- **Privacy by default**: new accounts have minimum visibility; the operator opts into broader sharing.

What the operator must add:

- **Data Processing Agreement (DPA)** template with your customers.
- **Subject access request (SAR) workflow** — Powernode provides the data, you provide the workflow.
- **Cookie consent banner** for the frontend if collecting analytics cookies — not shipped.
- **PII minimization** review per your jurisdiction.

## HIPAA

Powernode is **not HIPAA-ready out of the box**. The platform can technically store PHI in any text column, but lacks:

- BAA-compliant infrastructure agreements (operator-owned)
- Designated HIPAA-trained admin role separate from `super_admin`
- Encryption-at-rest on every persistent volume by default (operator-configured)
- Automatic PHI tagging in audit logs (would require schema additions)

If you must run on Powernode in a HIPAA context, plan for a custom audit + additional controls. The platform doesn't actively prevent HIPAA-grade use, but it doesn't help.

## PCI DSS

`server/config/initializers/pci_compliance.rb` scaffolds:

- Parameter filtering for `card_number`, `cvv`, `expiry`, etc. in Rails request logs
- HSTS + secure-cookie defaults
- Rate limiting on payment endpoints

What's NOT shipped:

- Network segmentation for the cardholder-data environment (operator-owned)
- Quarterly external ASV scans (third-party)
- Penetration testing artifacts (third-party)
- Annual SAQ-D or ROC

Critically, Powernode **does not store full card data** — Stripe/PayPal handle that. The platform's PCI scope is "merchant of record using a PCI-compliant processor" (SAQ-A territory) unless you've done something custom.

## SOC 2

Powernode supports SOC 2 Type II evidence collection via the audit log + access control system. Trust services criteria evidence map:

| Criterion | Where to find evidence in Powernode |
|-----------|-------------------------------------|
| Security: access control | `AuditLog.where(action: ~/login|logout|permission_change/)`, `users.roles`, `permissions` |
| Security: change management | `git log` (code), `AuditLog.where(action: ~/admin_settings_update/)` (config), migration history |
| Availability | Service metrics in Prometheus + status checks (see [observability.md](./observability.md)) |
| Confidentiality: encryption | TLS via reverse proxy (operator), at-rest via Postgres TDE (operator), secret storage via Vault |
| Processing integrity | `AuditLog`, request/response logs in Loki, per-job result records in Sidekiq |
| Privacy | See [GDPR / CCPA](#gdpr--ccpa) section |

SOC 2 reporting itself requires an external auditor and 12+ months of evidence. Powernode generates the evidence; you contract the auditor.

## Encryption posture

| Layer | Default | Notes |
|-------|---------|-------|
| TLS in flight | Operator-configured at reverse proxy (Traefik default — see project_reverse_proxy_state memory) | Verify HSTS enabled |
| Postgres at-rest | Off (operator may enable LUKS/filesystem encryption / Cloud SQL CMEK / etc.) | Required for HIPAA, encouraged for PII |
| Vault transit secrets | AES-256-GCM by default | Vault handles this internally |
| Backup files | Plaintext .sql.gz by default | Add GPG or use SSE-KMS on S3 for encryption-at-rest |
| Worker file storage | Plaintext on local filesystem | Generated reports may contain sensitive data — encrypt the volume |

## Access controls

- **Permissions, not roles**: every protected operation checks `has_permission?('name')`. Roles bundle permissions but the actual gate is per-permission.
- **Worker JWTs** are short-lived (5 min) with a 4-min cache window. Compromise impact bounded.
- **Vault-stored credentials** rotate independently of code deploys.
- **Kill switch**: any administrator can halt all AI activity globally (see [incident-response.md#the-kill-switch](./incident-response.md#the-kill-switch)).
- **Account scoping**: API endpoints default to `current_user.account.scope` for data isolation. Cross-account access requires explicit `analytics.global`-style permissions.

## Audit log evidence

The `audit_logs` table is the platform's primary compliance evidence store. Schema:

| Column | Use |
|--------|-----|
| `action` | What happened (from `AuditActions::ALL_ACTIONS` allowlist; rejections fail validation) |
| `user_id` | Who did it (nullable for system/worker actions) |
| `account_id` | Scope of the action |
| `resource_type` + `resource_id` | What was touched |
| `old_values` + `new_values` | State diff (subset of changed columns) |
| `metadata` | Free-form context |
| `severity` + `risk_level` | Triage hints |
| `source` | Origin: `user`, `system`, `worker`, `api` |
| `ip_address` + `user_agent` | Request provenance |
| `created_at` | Timestamp |

Adding a new action: extend the appropriate `*_ACTIONS` constant in `server/app/models/concerns/audit_actions.rb` and include it in `ALL_ACTIONS`. Forgetting this causes silent log-write failures, which surface as missing evidence during audits — see the recent `REPORT_REQUEST_ACTIONS` addition for the pattern.

## Where to look during an audit

| Auditor asks for... | Locate via |
|----------------------|------------|
| "Show me who accessed X" | `AuditLog.where(resource_id: 'X')` |
| "Show me all admin actions in Q1" | `AuditLog.joins(:user).where(action: ADMIN_PATTERNS, created_at: Q1).order(:created_at)` |
| "Show me the change-management trail for production deploys" | `git log --since=...` + CI pipeline records (see `docs/operations/production-deployment.md`) |
| "Show me failed login attempts" | `AuditLog.where(action: 'login_failed', created_at: <window>)` |
| "Show me data exports" | `AuditLog.where(action: 'gdpr.data_export', created_at: <window>)` (verify action present in your release) |
| "Show me kill switch activations" | `ai_kill_switch_states` table; cross-reference `AuditLog.where(action: 'ai.kill_switch.activate')` |
| "Prove this user's data was deleted" | `Compliance::AccountTerminationJob` records; `AuditLog.where(action: 'gdpr.account_terminated', user_id: X)` |

## See also

- [incident-response.md](./incident-response.md) — security event response
- [postgres-backup.md](./postgres-backup.md) — backup policy + retention
- [observability.md](./observability.md) — log retention configuration
- `server/app/models/concerns/audit_actions.rb` — canonical action list
- `server/config/initializers/pci_compliance.rb` — PCI parameter filtering
