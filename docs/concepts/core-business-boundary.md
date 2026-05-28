# Core ↔ Business Boundary

**Status:** Draft for sign-off (2026-05-28). Supersedes the ad-hoc "X is also business"
decisions made during the billing-extraction session. Once approved, this is both the
architectural reference for what belongs in core vs the private `business` extension and
the migration plan for getting there.

## Governing principle

**Core is the minimal, open-source control plane that runs fully in *core mode*** — i.e.
with the public extensions (`system`, `supply-chain`, `marketing`) loaded but the **private**
extensions (`business`, `trading`) absent.

The dividing line is **strictly commercial monetization**, not "advanced feature." The
`business` extension owns *only* billing/subscription/revenue machinery: billing,
subscriptions, payments, invoices, plans, **usage metering/quotas**, marketplace *features*
(publish/browse/subscribe/payments/transactions), BaaS, AI credits, outcome/SLA **billing**,
reseller revenue, revenue intelligence/analytics.

**Everything else stays core — including approvals, governance, compliance, autonomy, and
security.** These are platform-operation capabilities a single-operator self-hosted install
needs; they are *not* billing features and must work in core mode. (This corrects a prior
over-extraction that moved governance/compliance/approval models into `business`; see open
question 2 — those models should return to core.)

Corollaries (verified this session):
- "Core mode" ≠ "zero extensions." `FeatureGateService.core_mode?` (which means
  `ExtensionRegistry.slugs.empty?`) is a **misnomer**; the correct predicate for "is this a
  paid/billing deployment?" is `FeatureGateService.billing_enabled?`. Registry confirms core
  mode here loads `["marketing","supply-chain","system"]`, `billing_enabled? == false`.
- A **public** extension may depend on **core** but never on the **private** business
  extension (Extension Isolation). This decides the marketplace-traits question below.
- Core must work with business absent: every business hook degrades to a safe default
  (unlimited entitlements, no-op billing, empty aggregates) via the `BillingBridge` façade
  and `billing_enabled?` guards.

## Decisions locked this session

| # | Decision |
|---|----------|
| 1 | Namespaces stay **domain-top-level** (`Billing::`, `BaaS::`, `Marketplace::`), never `Business::`-prefixed (matches `System::`/`Sdwan::`/`Trading::`; business augments core `Ai::`/`Mcp::`). |
| 2 | Entitlement guard fixed: `core_mode?` → `billing_enabled?` in `Entitlements::{UsageLimitService,FeaturePlanService}`. Core mode = unlimited users + all features. |
| 3 | Billing/subscription worker + server already extracted to business; remaining core orphan specs deleted. |
| 4 | Marketplace **traits stay core**, marketplace **features → business**. |
| 5 | Usage metering → business (full extract — see detail). |
| 6 | Webhook delivery is **core infrastructure**; its internal-controller breakage is a core bug to fix, not a business move. |

## Completed (this session)

- `Entitlements::{UsageLimitService,FeaturePlanService}` guard fix (10 call sites) + core-mode spec rewrite — passing.
- Deleted **29** orphaned billing specs (models/controllers moved to business).
- Deleted the dead **AI-marketplace cluster** (core `ai/marketplace_controller`, `ai/agent_marketplace_controller`, 4 `Ai::Marketplace*` services) + 30 orphan specs + 14 orphan factories (BaaS, governance, credits, reseller, analytics, marketplace).
- Phase-A marketplace dedup (dead core `Marketplace::SubscriptionOrchestrator` + controllers + model).
- Pattern-B spec fixes (users/api_keys/webhooks/files no longer create `:subscription`).
- Model-spec fixes (`account`, `usage_summary` drop business-decorated association assertions).
- `zeitwerk:check` clean.

## Classification matrix

| Subsystem / artifact | Disposition | Notes |
|----------------------|-------------|-------|
| Billing models/services/jobs (subscription, payment, invoice, plan, reconciliation) | **BUSINESS (done)** | Worker + server already in `extensions/business`. Core orphan specs deleted. |
| `Entitlements::UsageLimitService`, `FeaturePlanService` | **CORE (keep)** | Gate core resources; unlimited when `!billing_enabled?`. Callers: users/api_keys/webhooks/workers controllers. |
| `Powernode::BillingBridge` | **CORE (keep)** | Façade business registers into; nil/zero defaults in core mode. |
| **Usage metering** (`UsageEvent/Meter/Quota/Summary`, `UsageTrackingService`, `UsageController`, routes) | **BUSINESS (extract)** | No core emitter; all consumers billing-gated; business has parallel `BaaS::UsageRecord`. Full extract. |
| Marketplace **traits** (`MarketplacePublishable`, `MarketplaceReviewable`, `MarketplaceReview`, `Marketplace::` ns) | **CORE (keep)** | Consumed by **public** supply-chain `ScanTemplate`; public can't depend on business. Lightweight column traits, degrade via `billing_enabled?`. |
| Marketplace **features** (publish/browse/subscribe/reviews UI/payments/transactions/publisher) | **BUSINESS (done)** | Core dead duplicates deleted; business owns + routes. |
| AI marketplace (`Ai::Marketplace*`, agent marketplace) | **BUSINESS (done)** | Dead core cluster deleted; `Ai::WorkflowTemplate` was removed upstream. |
| BaaS (`BaaS::*`) | **BUSINESS (done)** | Models in business; core orphan specs/factories deleted. |
| AI credits / outcome / SLA billing (`Ai::AccountCredit`, `CreditTransaction`, `OutcomeDefinition`, `SlaContract`, …) | **BUSINESS (done)** | Models in business (augment `Ai::`); core orphan specs deleted. |
| Reseller (`Reseller`, `ResellerReferral`) | **BUSINESS (done)** | Orphan specs/factories deleted. |
| Revenue intelligence / analytics (`RevenueSnapshot/Forecast`, `ChurnPrediction`, `CustomerHealthScore`, `AnalyticsAlert`) | **BUSINESS (done)** | Models in business; core orphan specs deleted. |
| Governance / compliance / approvals (`Ai::CompliancePolicy`, `PolicyViolation`, `ApprovalChain`, `ApprovalRequest`, `DataClassification`, `ComplianceReport`, `InterventionPolicy`) | **CORE (restore)** | NOT billing → core. Prior session mis-moved the **models** into business; they should return to core so the gate/security services work in core mode. Glue (controllers/gate/notifier/security services) **stays core**. |
| Webhook delivery (`WebhookDelivery`, `WebhookDeliveryStat`, `WebhooksController`) | **CORE (keep)** | Core event-webhook infra (endpoint/event based). |
| `internal/webhook_deliveries_controller` | **CORE (FIX — bug)** | References removed `Marketplace::WebhookDelivery` + fields `app_webhook/payload/attempts` not on core model. Worker depends on it. Reconcile to core `WebhookDelivery` (or add `payload`/endpoint mapping). |
| `AuditActions` concern | **CORE (keep)** | Shared audit taxonomy (constants only). |

## Live extractions — detail

### A. Usage metering → business (full extract)
**Move** (core → `extensions/business/server`): `app/models/usage_{event,meter,quota,summary}.rb`,
`app/services/usage_tracking_service.rb`, `app/controllers/api/v1/usage_controller.rb`, the
`usage`/`usage_events` routes (`server/config/routes.rb`), and the existing usage decorators
already in business. **Core decoupling:** remove `has_many :usage_events/:usage_summaries/:usage_quotas`
from `Account`; the `account.subscription` reference in `UsageSummary.aggregate_for_period` goes
away with the model. **Specs:** core usage specs become orphans → delete (business covers in its suite).
**Permission note:** the `track_event`/`batch` ingest endpoints are currently unguarded — when moved,
gate them under the business usage scope. No core feature emits usage, so nothing in core needs a
replacement primitive.

### B. Governance / approvals / compliance → CORE (restore models, keep glue)
Decision: approvals + governance + compliance are **core** functionality (not billing). The glue
already lives in core and **stays** there:
- `controllers/api/v1/ai/approval_chains_controller.rb`, `controllers/concerns/ai/autonomy_approval_actions.rb`,
  `services/ai/approval_request_notifier.rb`, `Ai::AutonomyGate`, `Ai::DeferredOperation` → **keep core**.
- `Ai::Security::{PiiRedactionService,AgentAnomalyDetectionService}` → **keep core**. They still carry 12
  `ExtensionRegistry.loaded?("business")` guards around `ComplianceAuditEntry`/`PolicyViolation`/`DataClassification`
  writes. **FOLLOW-UP (deferred):** now that those models are core, remove the guards so core logs governance
  unconditionally. Deferred because they sit in security-critical files in mixed patterns (7 `return unless`
  early-returns, 5 `if/else` blocks) and the governance *capability* (models/API/service/approvals/gate) is
  already fully core — these guards only gate security-service *auto-logging*, a no-op-safe refinement.
- `Ai::InterventionPolicy` → core; its `STATIC_CATEGORIES` may keep approval/proposal/escalation but should
  let *extensions* register their own categories (`trading.*` via trading, `project.*` via the owning extension).

**Open work (reverse-extraction):** the governance/compliance/approval **models** currently reside in
`extensions/business/server/app/models/ai/*` (compliance_policy, policy_violation, approval_chain,
approval_request, data_classification, compliance_report, intervention_policy, …) and their Account
associations in the business `account_decorator`. To make governance work in core mode, these models +
associations move **business → core**. This is the inverse of the other extractions and touches the private
business repo (remove there, add to core). Scope/verify before doing — see open question 2.

### C. Marketplace feature/trait boundary (mostly done)
Traits stay core (above). Confirm no remaining core controller/service implements a marketplace
*feature*; the dead cluster is already deleted. `MarketplaceReviewable` is currently included by
nothing — keep as a core trait for symmetry or remove (low priority).

### D. Webhook internal-controller bug (core fix)
`internal/webhook_deliveries_controller` must target core `WebhookDelivery` (fields: `webhook_endpoint`,
`attempt_number`, `response_status`, …) and the worker contract in
`worker/app/jobs/webhooks/webhook_delivery_job.rb` / `webhook_retry_job.rb`. Decide whether core
`WebhookDelivery` needs a `payload` column or the worker reads payload from `webhook_event`. Pre-existing
bug; fix independently of the business work.

## Remaining surviving-core spec fixes (core mode)
Guard-or-trim business-mode examples (pattern: `skip unless defined?(Billing::X)` or drop business-only
assertions): `accounts_spec` (subscription-data example), `auth/registrations_spec` (trial subscription),
`audit_log_spec` (`log_payment`/`log_subscription_change` — methods no longer exist → delete those examples;
`log_action` → use a core resource), `usage_quota_spec`/`webhook_event_spec` (drop decorated assoc matchers),
`users_controller_spec` (drop `:subscription` setup), `mcp_agent_executor_spec` (drop dead `account.subscription`
stub), `internal/accounts_spec` (subscription-status example). `internal/data_exports_spec` + `provisioning_tool_spec`
already self-guard. `plan_composer_service_spec` `let(:plan)` is `Ai::GoalPlan` (not billing — no change).

## Proposed execution sequence
1. **Commit the completed billing/cleanup slice** as a stable checkpoint (business-first, then core; no pointer bump until stable).
2. Finish the surviving-core spec fixes → run affected specs green in core mode.
3. **Usage-metering extraction** (its own commit, both repos) + verify.
4. **Governance hybrid** move + InterventionPolicy categories + security-service hook cleanup.
5. **Webhook internal-controller fix** (independent core bug).
6. Full core-mode spec run to confirm green; then bump the business submodule pointer.

## Sign-off status
1. **Usage metering — RESOLVED: full extract** to business (no core emitter found).
2. **Governance/approvals/compliance — CORE.** Implies a **reverse-extraction** (business→core) of 9 models
   (`Ai::{CompliancePolicy,PolicyViolation,ApprovalChain,ApprovalRequest,DataClassification,ComplianceReport,ComplianceAuditEntry,DataDetection,ApprovalDecision}`)
   + their Account associations (from business `account_decorator` → core `account.rb`) + their migrations,
   and removing ~16 `ExtensionRegistry.loaded?("business")`/`defined?` guards in core glue
   (autonomy_gate, security services, approval controllers/services). **NEEDS sign-off — it reverses prior
   work and edits the private business repo.** Alternative: leave models in business, keep glue core but
   guarded (governance stays a no-op in core mode) — does NOT satisfy "governance is core functionality."
3. **Sequence — RESOLVED: one combined landing** (no intermediate billing-only commit).
4. Webhook internal controller (core bug) — **DEFERRED this landing.** `internal/webhook_deliveries_controller`
   targets a removed `Marketplace::WebhookDelivery` schema (`app_webhook`, `payload`, `attempts`, `response_code`,
   `response_time_ms`, `started_at`/`delivered_at`/`failed_at`, statuses `in_progress`/`delivered`) that core
   `WebhookDelivery` does NOT have (it uses `webhook_endpoint`, `webhook_event.payload`, `attempt_number`,
   `response_status`, `attempted_at`, statuses `pending`/`success`/`failed`/`timeout`). The worker
   (`webhook_delivery_job`/`webhook_retry_job`) depends on the endpoint, so this needs a worker-contract +
   schema reconciliation pass (status vocab map + missing-column decisions), separate from the boundary work.
   Pre-existing bug; not regressed by this session.

## Deferred in this landing (follow-ups)
- **Security-service governance guards** (§B): 12 `ExtensionRegistry.loaded?("business")` guards in
  `pii_redaction_service`/`agent_anomaly_detection_service` to remove (governance models are core now).
- **Webhook internal controller** (above): reconcile to core `WebhookDelivery` + worker contract.
- **Usage migration/schema purity:** `usage_tracking_system` migration + tables remain in core schema (harmless
  empty tables in core mode); the usage *code* is fully in business. Optionally move the migration to business later.
