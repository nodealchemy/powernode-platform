# Phase 6 — Billing Consolidation Findings (0.4.0 DB refactor)

**Date:** 2026-06-22 · **Branch:** `feature/db-refactor-040` · **Companion to:** `schema-audit-2026-06.md` §6a

## Verdict: KEEP SEPARATE — consolidation is a no-op

The Phase 2 audit's preliminary "keep-separate" verdict is **confirmed by consumer analysis**. The
subscription-shaped billing tables model **distinct billing surfaces with distinct actors**, not
duplicates. Merging any of them would couple unrelated billing contexts. There is **no genuine
redundancy to fix**, so the "do not defer payment fixes" directive is satisfied with nothing to do.

### Evidence — distinct actors per subscription surface

All billing tables are already `business_*` (relocated to the business baseline in Phase 4; excluded
from the public `schema.rb`). Within the business extension the surfaces are:

| Table (`business_*`) | Model | Owner / actor (FK evidence) | Domain |
|---|---|---|---|
| `business_subscriptions` | `Billing::Subscription` | `belongs_to :account`, `belongs_to :plan` | Platform's own customer plan billing |
| `business_baas_subscriptions` | `BaaS::Subscription` | `belongs_to :baas_tenant`, `belongs_to :baas_customer` | A BaaS *tenant's* customers (billing-as-a-service — different actor entirely) |
| `business_marketplace_subscriptions` | `Marketplace::Subscription` | per-listing | Marketplace listing billing |
| `business_mcp_server_subscriptions` | hosted-MCP | per-server | Hosted-MCP billing |
| `business_credit_*` (was `ai_credit_*`) | credit pack/purchase/transaction/usage_rate | prepaid-credit ledger | Normalized metering — complements recurring subs, not a duplicate |

The decisive point: `business_subscriptions` is keyed to **`Account`** (the platform's customer), while
`business_baas_subscriptions` is keyed to **`BaaS::Tenant` + `BaaS::Customer`** (a customer *of* a
platform tenant). They are two different billing relationships one level apart in the tenancy hierarchy —
structurally impossible to merge without conflating "who is billed."

`ai_credit_*` (prepaid credit + usage metering: pack=product, purchase=txn, transaction=ledger,
usage_rate=pricing) is **complementary** to recurring subscriptions, not a second implementation of them.

### Core decoupling is already correct

Core never references the `Billing::` namespace. It calls billing through the **`Powernode::BillingBridge`**
seam (`server/app/services/powernode/billing_bridge.rb`):
- Core call sites: `admin/settings_service.rb`, `api/v1/metrics_controller.rb`,
  `api/v1/internal/ai/provisioning_controller.rb`, `admin/maintenance/maintenance_controller.rb` — all
  null-safe (`subscription_model&.count || 0`, `check_provisioning_quota` allows by default).
- The business engine registers the real classes at boot
  (`powernode_business/engine.rb`: `subscription_model = Billing::Subscription`, …).

No code anywhere treats two billing surfaces as interchangeable. **No schema or data change in Phase 6.**

---

## Secondary finding (NOT consolidation): 3 misplaced billing artifacts in core

These are an **extension-isolation / core-purity** concern (see memory
`billing-belongs-in-business-extension`), distinct from the consolidation question. The billing *data*
already lives in the business extension; these are *code* artifacts left behind in core. None is caught by
`core-purity-check.sh` because their constant names (`BaaS`, `Billing`, `BillingExceptions`) are not the
business extension's registered forbidden name.

| Core artifact | Core consumers? | Relocation | Difficulty |
|---|---|---|---|
| `server/app/models/baas.rb` (empty `BaaS` namespace module) | none — the 2 `BaaS::` hits in core are illustrative strings in KB-population prompt text, not code | Move to business ext, or delete (the ext's `baas/` dir auto-vivifies the namespace via Zeitwerk implicit namespacing) | Trivial |
| `server/app/exceptions/billing_exceptions.rb` + `server/spec/exceptions/billing_exceptions_spec.rb` | none in core app — every raiser is in the business ext (worker billing jobs + `paypal_service`); the only `server/` ref is the core spec | Move def + spec to `extensions/private/business/server/app/exceptions/` (+ spec). The business **worker** already has its own copy (`extensions/private/business/worker/app/exceptions/billing_exceptions.rb`) — separate app, necessarily duplicated | Clean |
| `server/app/channels/subscription_channel.rb` | core frontend `usePageWebSocket.ts` `CHANNEL_NAMES` map names it | Requires a **channel-registry seam**: core's map *also* hardcodes business `CustomerChannel` + `AnalyticsChannel`, so the fix is "extensions register their logical→ActionCable channel mappings + page associations," then move `SubscriptionChannel` to the business ext | Bundle into a channel-seam epic |

### Recommended follow-up (tracked separately from Phase 6)

Bundle the three into one **"billing/channel core-purity relocation"** pass so full-mode validation
(Zeitwerk both modes + boot) runs once, not per-file:
1. Build a frontend channel-registry seam (extensions contribute `CHANNEL_NAMES` + `PAGE_CHANNELS`
   entries); strip `subscriptions`, `customers`, and the business `analytics` mapping from core's hardcoded map.
2. Relocate `SubscriptionChannel` → business ext; business registers the `subscriptions`/`customers` mappings.
3. Relocate `BillingExceptions` (def + spec) → business server ext.
4. Relocate/delete `baas.rb` namespace.

This is core-purity work, not a billing fix — there is **no payment redundancy to remediate**, so deferring
it to its own focused pass is consistent with the "don't defer payment fixes" directive.
