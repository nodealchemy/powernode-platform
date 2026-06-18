# AI Navigation Information Architecture

The map of the **AI** sidebar category: what each item is, how nesting works, and the
route/redirect table. This is the reference a frontend change to the AI category should
update.

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
| **Observability** | `/app/ai/observability` | `PathTabs`: Health · Systems · Conversations · Evaluation | `ai.analytics.read` |
| **Operations** | `/app/ai/operations` | `PathTabs`: AIOps · Alerts · Execution Traces | `ai.aiops.read` / `ai_monitoring.read` |
| **Cost** | `/app/ai/cost` | `SubNavRail`: Overview · Credits · FinOps · ROI · Outcome Billing | `ai.finops.view` / `ai.roi.read` / `ai.analytics.read` |
| Governance | `/app/ai/governance` | per-feature | `ai.governance.read` |

The **Developer Portal** lives in the **DevOps** section (`/app/developer`,
`api.manage_keys`). The former orphan **Cost** and **Developer** sidebar sections were
removed; their contents were absorbed above.

## Cost hub (`CostPage`, sub-rail)

`pages/app/ai/CostPage.tsx` — one `SubNavRail` over five leaves; each leaf that has
sub-views renders a single `PathTabs` row:

- **Overview** — cross-cutting snapshot (reuses FinOps panels).
- **Credits** — `CreditsContent` → tabs: overview · purchase · transactions · transfers · reseller.
- **FinOps** — `FinOpsContent` → tabs: overview · cost-explorer · budget.
- **ROI** — `RoiDashboardContent` (single view).
- **Outcome Billing** — `OutcomeBillingContent` → tabs: definitions · contracts · records · violations · performance · summary.

## Redirect / route table (legacy → current)

| Old path | Now |
|---|---|
| `/app/ai/observability/credits*` | `/app/ai/cost/credits` |
| `/app/ai/billing/*` | `/app/ai/cost/credits` |
| `/app/ai/observability/operations` | `/app/ai/operations` |
| `/app/ai/observability/alerts` | `/app/ai/operations/alerts` |
| `/app/developer/traces` | `/app/ai/operations/traces` |
| `/app/ai/monitoring/*` | `/app/ai/observability` |

## Backend note

Backend API scopes are **unchanged** by this IA work (frontend routes ≠ API paths).
The one backend-contract fix was the ROI service: calculation endpoints
(`metrics`, `projections`, `recommendations`, `compare`, `calculate`, `aggregate`) are
served under `/api/v1/ai/roi/calculations/*` (RoiCalculationsController); the frontend
`RoiApiService` now calls them there (previously it hit `/ai/roi/*` → 404).
