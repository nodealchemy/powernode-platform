# Compliance Posture

> Status: active
>
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
| Generated reports | none built-in | manual — files live on the worker filesystem (`worker/storage/`) | Regenerable from data; snapshot/prune the storage volume per your regime |
| Background job dead set | 14 days (Sidekiq default) | `worker/config/sidekiq.yml` | Operational only — no customer data |
| Loki logs | 7 days | `configs/logging/loki-config.yml` `retention_period` | PCI requires 1 year minimum; adjust before claiming PCI |
| Postgres backups | 30 days local | `Maintenance::BackupCleanupJob` (`BACKUP_RETENTION_DAYS`) | Match to longest applicable retention; off-host/S3 copies are operator-managed |

## GDPR / CCPA

What the platform supports:

- **Right to erasure**: `Compliance::AccountTerminationJob` and `Compliance::DataDeletionJob` (in `worker/`) are each a sequence of internal API calls, not a single atomic transaction. As of IMP-b33a3ecca331 (server-side params contract, gained during review: response-body key handling, an index-filter gap, a status-transition guard) both jobs reliably reach a **terminal state** (`completed`/`grace_period`-for-retry, or `failed`) with the effects they claim actually applied.
  - **The jobs literally never ran correctly before this fix, independent of everything else below.** `BackendApiClient#handle_response` (`worker/app/services/backend_api_client.rb`) returns the parsed JSON body verbatim — STRING keys — on a 2xx response and raises on any non-2xx; it is not a `{success:, data:}` symbol-keyed envelope. Every response read in both jobs used symbol keys (`response[:success]`, `response[:data]`) against that string-keyed hash, so those reads were always `nil` — `DataDeletionJob` raised "Failed to fetch" on every single run, and `AccountTerminationJob`'s `return unless response[:success]` made it a permanent no-op. Worker specs never caught this because they stub symbol-keyed doubles. Fixed by reading responses the way the rest of the worker's compliance-adjacent jobs do (string keys, e.g. `Ai::ApprovalExpiryJob`) — applied to every response read in both files, including ones that predate this task. `Api::V1::Internal::DataDeletionRequestsController#show` also nests its payload one level deeper (`data.data_deletion_request`, not `data`) — the job now unwraps both levels.
  - **The account-termination job's index query used to ignore its own filter.** `Api::V1::Internal::AccountTerminationsController#index` used to return every active (`pending`/`grace_period`/`processing`) termination regardless of the `status`/`grace_period_expired` params the job sent — once the key bug above was fixed, the next 6-hourly run would have destructively processed (anonymize users, delete API keys/webhooks, cancel the account) every termination still `pending` (never confirmed by the account owner) and every `grace_period` termination whose 30-day window hadn't actually elapsed. Fixed by honoring those params, reusing the model's own `Account::Termination.ready_for_processing` scope for the job's exact "ready to process" query rather than reimplementing its semantics.
  - **Account termination — per-user step**: works. Consents/terms-acceptances/password-history are deleted, and the user record is **anonymized** in place (email/name/credentials/2FA/preferences cleared, password history purged, status set `inactive` — see `Api::V1::Internal::UsersController#anonymize`) rather than the row being deleted.
  - **Account termination — account-level step**: works. The account-status update goes through one narrow, purpose-built action — `PATCH /api/v1/internal/accounts/:id/terminate` (`Api::V1::Internal::AccountsController#terminate`) — instead of an unrouted, payload-driven `PATCH accounts/:id`. Operator decision on what "terminated" means for the account row: `status` is set to `cancelled`, the existing `valid_account_status` enum value closest to "this account is done" (no migration, no new status value, no new timestamp column — `Account` has no fitting one). The action takes no payload and is idempotent (calling it on an already-cancelled account succeeds without a duplicate write or audit row). It is called BEFORE the termination record is marked `completed` (a `completed` termination is excluded from every re-fetch this job makes, so a failure after marking it complete would have left the termination "done" while the account was never actually cancelled, with no automatic retry). `Account::Termination#completed_at` remains the authoritative WHEN/WHY record for the termination itself. Reviewed for side effects: no `Account` model callback reacts to its own `status` changing (only `after_create_commit` hooks exist, irrelevant to an update); `account.active?` gates login (`Authentication` concern, `Auth::SessionsController`) and AI/discovery processing (several internal controllers/services) — both correctly stop once the account is cancelled, with no destructive or billing-side action triggered automatically. The business extension's `Account` decorator adds associations and export helpers only, no callbacks. Separately, `Account::Termination#handle_status_change` (an `after_update` callback on the TERMINATION record, not `Account`) sets `account.status = "suspended"` the moment a termination transitions TO `grace_period` — this fires on this job's own error-revert path (a failed run reverts the termination to `grace_period` for retry), so a partially-processed account is automatically locked out (login blocked) while the retry is pending, not left fully active.
  - **Account termination — the log used to be wiped on every successful run, and a first fix still stripped some of it.** `process_termination` started from `termination_log = []`, and the PATCH `update` REPLACED the stored jsonb array rather than appending — so a successful run erased whatever history the model itself had written (`requested`, `confirmed`, reminder-sent entries) as well as any prior failed attempt's `error` entry. A first fix had the job seed its local array from the termination's already-fetched `termination_log` and send the whole thing back — but the permitted key list only covered keys the JOB itself writes (`event`/`user_id`/`count`/`error`/`reason`/`at`), so model-authored entries (`confirm!`/`cancel!`/`complete!`/`schedule_reminders`, which write `by`/`days_before`/`scheduled_for`) were silently stripped on every worker write regardless, and a whole-array replace remained a lost-update race against any concurrent writer. The actual fix: `AccountTerminationsController#update` accepts a `termination_log_append` param — ONLY the job's own new entries for this run — and merges it onto the CURRENT stored log server-side, inside a `with_lock` (pessimistic row lock, read-reload-append-write). The whole-array `termination_log` param is removed entirely (no legacy path); the job no longer seeds or re-sends fetched history at all. The permitted key list also dropped `by`/`days_before`/`scheduled_for` (only the model's own writers use them, never the job), and every appended entry's `event` VALUE is checked against the exact set the job builds — key-permitting alone still let a forged event NAME through (`event`/`at` were always permitted keys), so `{event: 'confirmed', at: ...}` would otherwise inject a fabricated model-lifecycle entry into the audit trail unchallenged.
  - **Account termination — the raw status-write endpoint used to accept ANY transition, with no audit trail.** `AccountTerminationsController#update` (the only endpoint `Compliance::AccountTerminationJob` PATCHes) had no transition guard at all: a worker principal could jump a termination straight to `completed` (destructive — cancels the account) without ever having gone through `processing`, or restart an un-expired `grace_period` termination early, with no audit row recording it. Fixed with an explicit guard mirroring the transitions the job actually makes — `grace_period`→`processing` only when `can_start_processing?` holds (the grace period has actually elapsed, mirroring the model's own guard on `start_processing!`), `processing`→`completed`/`grace_period` — checked twice (once fail-fast, once inside the `with_lock` against a freshly-reloaded row) so a concurrent writer can't race past it. A status-less log-only write (the reminder-sent path) is allowed only while the termination is still `grace_period`/`processing`; once `completed`/`cancelled` its history is frozen. Every allowed status transition writes an `account_termination.status_transition` audit row with `from_status`/`to_status`.
  - **Account termination — subscription anonymization**: when the business extension is loaded, subscription data was never anonymized (the job called an unrouted `/subscription/anonymize` endpoint). Core has no generic seam for this today (`Powernode::BillingBridge` registers subscription/payment/plan *models* and a provisioning quota/meter handler, but no anonymize handler) — rather than build a new bridge seam or call an unrouted endpoint, the job now **explicitly skips** this step and records `{event: 'subscription_anonymize_skipped', reason: 'no_billing_extension_provider'}` in the termination log. **This is a real, currently-open gap**: a terminated account's subscription/billing record is not anonymized. Tracked as a follow-up.
  - **Data deletion**: `DataManagement::DeletionRequest` gained a `failed` status value (it previously had none, so the job's own `status: 'failed'` writes were themselves rejected by model validation on top of the params-contract bug). The "anonymize"/"full"/"partial" deletion types now route the `profile`, `audit_logs`, `payments`, and `consents` data types at real, already-routed internal actions (there was never a `/api/v1/internal/data_deletion/:type` route) — those actions now also return the record count the job logs (`delete_consents`/`delete_files` used to be message-only, so that count was always read as 0). A request stuck in `processing` (e.g. the worker crashed mid-run) now **resumes** on retry instead of being silently skipped; an unrecoverable failure now ends in `status: 'failed'` (terminal) instead of a dangling `processing` record with no signal. **`failed` has no retry path and none was added**: `approve_request` requires `pending?` and `execute_request` requires `approved?`, so no admin `action_type` transitions a failed request back to something this job would ever process again — a user whose deletion failed must file a NEW request (`Api::V1::PrivacyController#request_deletion`; its `DataManagement::DeletionRequest.active` guard already excludes `failed`, so the dead request does not block a fresh one). A per-data-type erasure failure now raises a dedicated `Compliance::DataDeletionJob::PartialDeletionFailure` (not a bare string) — the outer rescue recognizes it and skips its own redundant `status: 'failed'` write, since that path already wrote the terminal status (with the full `deletion_log`/`retention_log` detail the outer write doesn't have) before raising, and a second write would now 422 under the transition guard (`failed`→`failed` isn't an allowed transition).
  - **Data deletion — approving a request used to omit its own grace period.** `DataDeletionRequestsController#approve_request` never set `grace_period_ends_at` (the model's own `#approve!` method does, but nothing calls it — this controller action is the only approval path that exists). `Compliance::DataDeletionJob#execute` reads that field unconditionally once a request is approved, and the `Time.zone.parse(...)` call sits BEFORE the job's `begin`/rescue block entirely (deliberately — the grace-period check has to run before the request is ever marked `processing`), so the resulting `Time.zone.parse(nil)` `TypeError` was never caught by anything: no `failed` write happened, no error was recorded anywhere, the request stayed `approved` forever, and every Sidekiq retry hit the exact same `nil` value and crashed the exact same way — a permanent, invisible crash-loop, not a retryable failure, with no terminal state to even alert on. Fixed on both sides: `approve_request` now sets `grace_period_ends_at` (reusing the model's `GRACE_PERIOD_DAYS` constant), and the job independently guards against a missing value regardless — a `nil`/blank `grace_period_ends_at` now writes a terminal `status: 'failed'` and returns cleanly instead of raising (defense in depth against any other path that reaches `approved`/`processing` without the field set).
  - **Data deletion — the generic status-write endpoint used to accept ANY transition, with a lost-update race and an under-scoped status-less write.** The branch `Compliance::DataDeletionJob` PATCHes (no `action_type`) had no transition guard at all: any mTLS-enrolled worker principal could set any valid model status — including `completed` on a request that was never approved — bypassing `complete_request`'s own guard, its audit row, and its user notification, effectively forging a GDPR completion record. Fixed with an explicit allowlist (`approved`→`processing`, `processing`→`processing`/`completed`/`failed`; anything else is rejected with 422 `INVALID_STATUS_TRANSITION`) plus ONE narrow conditional exception — `approved`→`failed` is allowed ONLY when `grace_period_ends_at` is actually blank (the exact data-integrity defect the nil-guard above exists for, not a general escape hatch from `approved`) — checked twice (fail-fast, then again inside a `with_lock` against a freshly-reloaded row so a concurrent writer can't race past it), with its own audit action (`data_deletion.status_transition`, carrying both `from_status` and `to_status`, captured from the freshly-locked row so it can't name a stale status) on every allowed transition. A status-less write (no `status` key) carrying progress fields (`completed_at`/`deletion_log`/`retention_log`/`error_message`/`metadata`/`processing_started_at`) is now permitted only while the request is actively `processing` — previously unrestricted for the first four fields, and `metadata`/`processing_started_at` weren't guarded at all — a request that's `pending`/`approved` has no run in flight to report progress for, and no real caller ever sends these status-less outside `processing` anyway.
  - **Data deletion — unsupported data types**: `DataManagement::DeletionRequest::DELETABLE_DATA_TYPES` names 9 canonical GDPR erasure categories; five of them (`files`, `activity`, `settings`, `communications`, `analytics`) have **no backing data model anywhere in core**. A request naming one of these is recorded as `{action: 'skipped', reason: 'no_backing_data_model'}` in the request's `deletion_log` rather than silently failing or falsely claiming deletion. **This is an honest gap, not a fix**: if your deployment actually collects data under one of those categories, it is not erased by this job today. Tracked as a follow-up.
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
| "Show me kill switch activations" | `Ai::KillSwitchEvent.where(event_type: 'halt')` (or `account.ai_kill_switch_events.halts`) on the `ai_kill_switch_events` table |
| "Prove this user's data was deleted" | `Compliance::AccountTerminationJob` records; `AuditLog.where(action: 'gdpr.account_terminated', user_id: X)` |

## See also

- [incident-response.md](./incident-response.md) — security event response
- [postgres-backup.md](./postgres-backup.md) — backup policy + retention
- [observability.md](./observability.md) — log retention configuration
- `server/app/models/concerns/audit_actions.rb` — canonical action list
- `server/config/initializers/pci_compliance.rb` — PCI parameter filtering

_Last verified: 2026-09-18_
