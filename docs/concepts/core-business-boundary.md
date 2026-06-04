# Core ↔ Business Boundary

> What belongs in the open-source core vs. the private `business` extension, and why.

> Status: active

## Table of Contents

- [Governing principle](#governing-principle)
- [What belongs where](#what-belongs-where)
- [Core-mode contract](#core-mode-contract)
- [Corollaries](#corollaries)
- [Related concepts](#related-concepts)

## Governing principle

**Core is the minimal, open-source control plane that runs fully in *core mode*** — with the
public extensions (`system`, `supply-chain`, `marketing`) loaded but the **private** extensions
(`business`, `trading`) absent.

The dividing line is **strictly commercial monetization**, not "advanced feature." The `business`
extension owns *only* billing/subscription/revenue machinery. **Everything else stays core** —
including approvals, governance, compliance, autonomy, and security. Those are platform-operation
capabilities a single-operator self-hosted install needs; they are *not* billing features and must
work in core mode.

The split is by **capability ownership**, not by where a file happens to sit at any moment. When in
doubt, ask: "is this strictly billing/revenue?" If no, it belongs to core.

## What belongs where

**`business` extension (private — billing & revenue only):**

- Billing, subscriptions, payments, invoices, plans, reconciliation
- Usage metering & quotas
- Marketplace **features** (publish / browse / subscribe / payments / transactions)
- BaaS, AI credits, outcome / SLA **billing**
- Reseller revenue, revenue intelligence / analytics

**Core (open-source — everything else):**

- Approvals, governance, compliance, autonomy, security — platform operation, not billing
- Marketplace **traits** (the `MarketplacePublishable` / `MarketplaceReviewable` column concerns) —
  consumed by the **public** `supply-chain` extension (`SupplyChain::ScanTemplate`), which cannot
  depend on the private `business` extension
- Webhook delivery infrastructure (endpoint / event based)
- Entitlement guards (`Entitlements::UsageLimitService`, `Entitlements::FeaturePlanService`) —
  unlimited when `!billing_enabled?`
- The `Powernode::BillingBridge` façade that `business` registers into

## Core-mode contract

Core must run with `business` absent. Every business hook degrades to a safe default — unlimited
entitlements, no-op billing, empty aggregates — via the `Powernode::BillingBridge` façade and
`Shared::FeatureGateService.billing_enabled?` guards.

## Corollaries

- **"Core mode" ≠ "zero extensions."** `Shared::FeatureGateService.core_mode?` (which means
  `ExtensionRegistry.slugs.empty?`) is *not* the predicate for billing state. The predicate for
  "is this a paid/billing deployment?" is `Shared::FeatureGateService.billing_enabled?`. A typical
  open-source install loads `["marketing", "supply-chain", "system"]` with `billing_enabled? == false`.
- **A public extension may depend on core, never on the private `business` extension** (Extension
  Isolation). This is why marketplace *traits* stay core — the public `supply-chain` extension
  consumes them.
- **Namespaces stay domain-top-level** (`Billing::`, `BaaS::`, `Marketplace::`), never
  `Business::`-prefixed — matching `System::` / `Sdwan::` / `Trading::`. The `business` extension
  augments core `Ai::` / `Mcp::` rather than introducing a `Business::` namespace.

## Related concepts

- [architecture.md](architecture.md) — platform architecture and the extension model
- [data-model.md](data-model.md) — core models, namespaces, and foreign-key conventions

_Last verified: 2026-06-04_
