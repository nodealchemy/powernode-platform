# AI Navigation Information Architecture

The map of the **AI** sidebar category: what each item is and how nesting works. This is
the reference a frontend change to the AI category should update.

## Principles

1. **Flat sidebar, sub-nav inside pages.** The left sidebar stays flat (no submenus).
   Where a hub has leaves that themselves have sub-views, the hub uses an **in-page
   vertical sub-rail** (`SubNavRail`) — never a second row of horizontal tabs. Net depth
   never exceeds *sidebar item → sub-rail → one `PathTabs` row*.
2. **Path-based tabs that drive URL + breadcrumbs.** Every tab/sub-nav selection changes
   a URL segment (deep-linkable) and updates the `PageContainer` breadcrumb trail. No
   `?tab=` query params, no component-state tabs. Hubs compute breadcrumbs from
   `useLocation` via `aiCrumbs()` (`shared/utils/breadcrumbs.ts`).
3. **Permissions only** (never roles) gate every item, tab, and rail entry.

## Building blocks

| Primitive | File | Use |
|---|---|---|
| `PathTabs` / `firstAccessibleTabPath` | `shared/components/navigation/PathTabs.tsx` | canonical horizontal, path-based tab row |
| `SubNavRail` | `shared/components/navigation/SubNavRail.tsx` | canonical vertical in-page sub-navigation for deep hubs |
| `aiCrumbs(...trail)` | `shared/utils/breadcrumbs.ts` | prepend `Dashboard ▸ AI` to a hub/leaf breadcrumb trail |
| `PageContainer` | `shared/components/layout/PageContainer.tsx` | page shell: title, breadcrumbs, actions |

## AI sidebar items

Defined in `shared/utils/navigation.tsx` (`defaultNavigationConfig`); routed in
`pages/app/DashboardPage.tsx`.

| Item | Route | Structure | Gate |
|---|---|---|---|
| Overview | `/app/ai` | single page | — |
| Agents / Teams / Missions / Execution / Knowledge / Infrastructure | `/app/ai/*` | per-feature | per-feature |
| **Observability** | `/app/ai/observability` | `PathTabs`: System Health · Systems · Circuit Breakers · Alerts · Conversations · Execution Traces · Evaluation | one permission per tab — see `MONITORING_TABS` |
| **Cost** | `/app/ai/cost` | `SubNavRail`: Overview · Credits · FinOps · ROI · Outcome Billing | `ai.finops.view` / `ai.roi.read` / `ai.analytics.read` |
| **Control** | `/app/ai/control` | `SubNavRail`: Approvals · Policies · Budgets · Safety · Trust & Lineage · Goals · Compliance Audit | any permission a leaf is gated on (`CONTROL_PERMISSIONS`) |

The **Developer Portal** lives in the **DevOps** section (`/app/developer`,
`api.manage_keys`). The former orphan **Cost** and **Developer** sidebar sections were
removed; their contents were absorbed above.

## Control hub (`ControlPage`, sub-rail)

`features/ai/control/pages/ControlPage.tsx` — replaces the Autonomy dashboard, the
Governance page, the Approval Chains page and the standalone Budgets page. One
`SubNavRail` over seven leaves; a leaf with sub-views renders one `PathTabs` row, and
every leaf and tab is gated on the permission its endpoints check:

- **Approvals** — queue (`?request=<id>` opens one) · proposals · escalations · approval chains.
- **Policies** — intervention · compliance (compliance policies with toggle and create, their
  violations with resolve, and the account's security events).
- **Budgets** — `BudgetsPanel` (single view).
- **Safety** — kill switch · identities & quarantine · shadow mode · autonomy telemetry.
  Circuit breakers are not here: their one home is Observability → Circuit Breakers.
- **Trust & Lineage** — trust · lineage (with delegation policies) · behavior · feedback.
- **Goals** — single view.
- **Compliance Audit** — audit log · reports · collusion · ASI compliance.

Team coordination (signals, pressure fields, restructure events) moved to the Teams
page's Coordination tab (`/app/ai/teams/coordination`).

## Cost hub (`CostPage`, sub-rail)

`pages/app/ai/CostPage.tsx` — one `SubNavRail` over five leaves; each leaf that has
sub-views renders a single `PathTabs` row:

- **Overview** — cross-cutting snapshot (reuses FinOps panels).
- **Credits** — `CreditsContent` → tabs: overview · purchase · transactions · transfers · reseller.
- **FinOps** — `FinOpsContent` (single view: the cost explorer, at `/app/ai/cost/finops`; agent budgets live on the Budgets page, `/app/ai/control/budgets`).
- **ROI** — `RoiDashboardContent` (single view).
- **Outcome Billing** — `OutcomeBillingContent` → tabs: definitions · contracts · records · violations · performance · summary.

## Backend note

Backend API scopes are **unchanged** by this IA work (frontend routes ≠ API paths).
The one backend-contract fix was the ROI service: calculation endpoints
(`metrics`, `projections`, `recommendations`, `compare`, `calculate`, `aggregate`) are
served under `/api/v1/ai/roi/calculations/*` (RoiCalculationsController); the frontend
`RoiApiService` now calls them there (previously it hit `/ai/roi/*` → 404).
