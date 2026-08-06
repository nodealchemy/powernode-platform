# System Frontend & Dashboard Gap Analysis — 2026-08-06

Audit of the frontend against the platform vision (governed autonomy, by-intent
fleet operations, self-optimizing compute): what the operator can currently see
and steer, what exists but is unreachable, and what is missing. Companion to the
strategy memo's §6 self-optimizing-loop analysis and the 2026-08-05 by-intent MCP
improvement batch (IMP queue, fingerprints `*|system_fleet_tool.rb|*`).

**Method**: two survey passes (core `frontend/`, extension
`extensions/system/frontend/`) + direct spot-verification of load-bearing claims.
Baselines: core @ `27e95a2bb`, extensions/system @ `64241a87`. Report only — no
code changed.

**Companion design concept**: "Fleet Command" dashboard mock (artifact,
2026-08-06) — each widget annotated with the existing API it binds to.

---

## 1. Verdict in three sentences

The platform's governance machinery is far better covered by UI than its landing
surfaces admit — a full autonomy suite (approval queue, trust cards, intervention
policy editor, proposals, kill switch) exists but is buried three levels deep,
while the operator's first screen is a starter template with a hardcoded
checklist. The infrastructure itself has almost no graphical representation: two
React Flow topologies exist (one mature, one weak, both hidden), the Template
Composer discards a dependency graph the backend already computes, and compute
(nodes/instances/modules/volumes) is tables only. The seams to fix all of this —
React Flow ×16 files + dagre, recharts, entityRegistry (37 types), featureRegistry
componentSlots, runtime channel merging — already exist and are simply not joined.

## 2. What exists (verified inventory)

### Graph/chart substrate
- **React Flow (@xyflow/react 12)** in 16 core files + 2 extension components:
  `TeamExecutionDiagram`, `AgentConnectionsGraph`, `KnowledgeGraphVisualization`,
  `SkillGraphVisualization`, `StackTopologyPreview` (provisioning plan review),
  `MissionTaskGraph` (+`ApprovalGateNode`, `RalphTaskNode`), shared
  `workflowLayout.ts`, dagre layout lib. Extension: `SystemTopology.tsx` (443
  lines, server-computed layered layout, custom edge fan-out — mature) and
  `SdwanTopology.tsx` (147 lines — naive radial layout, hub-ness guessed from
  edge counts, IPv6-fragment labels).
- **recharts 3.8** installed; imported by exactly 7 files (6 agent-teams, 1
  aiops). Everything else hand-rolled: raw-SVG `CostTrendChart`, `AuditLogChart`;
  div-grid heatmaps. `shared/components/ui/` has **zero** chart primitives.
  The de-facto chart kit (CHART_COLORS, tooltipStyle) lives inside
  `features/ai/agent-teams/components/teamAnalyticsHelpers.tsx:6` and aiops
  imports across features; the intended seam `useChartColors`
  (`shared/hooks/useThemeColors.ts:92`) has **zero consumers** (dead).
- Reusable pattern worth lifting: `ChartFrame` (`AiOpsCharts.tsx:27-33`).

### Governance UI (exists, buried)
All inside `AutonomyDashboardPage` — a 13-item sidebar that is a *tab of a tab*
(`AIAgentsPage.tsx:26` → Autonomy tab → sidebar): ApprovalQueuePanel,
TrustScoreCard (5-dimension bars, promote/demote), InterventionPoliciesPanel
(400+ lines), ProposalsPanel, KillSwitchPanel + status banner, GoalsPanel,
EscalationsPanel, CircuitBreakerStatusPanel, AgentLineageTree,
CapabilityMatrixViewer, DelegationPolicyPanel, TelemetryEventStream,
BudgetAllocationPanel. Plus `GovernancePage` (8 path tabs) and the mission
surface (`PhaseTimeline`, `MissionTaskGraph` with approval-gate nodes).

### Economy UI (exists, 3 clicks deep)
`ModelRouterPage` (5 tabs incl. **Escalations** wired to
`/api/v1/ai/model_router/escalations{,/rollup,/benefit}` —
`ModelRouterApiService.ts:535-553`), CostPage hub (Overview/Credits/FinOps/ROI +
extension slot `ai.cost.outcome-billing`), FinOpsPage, BudgetRegimeIndicator
(NORMAL/CAUTIOUS/CRITICAL/EXHAUSTED), provider/model catalog pages. Model Router
is tab 4 of 7 in InfrastructurePage with no nav entry.

### Extension pages
12 route targets (overview, compute×6, catalog×8, operations×8, sdwan×8,
federation, service-delivery, acme, ingress, instance-pools, template composer),
16 legacy redirects. Live updates: `SystemFleetChannel` ×5 subscribers,
`SystemChannel` ×4, `MissionChannel` ×0. Fleet Dashboard = live event feed +
counter tiles + correlation viewer + boot replay.

## 3. Gap inventory

Severity: **P1** blocks the vision story · **P2** major usability/visibility ·
**P3** polish. Every gap names its fix seam.

### Landing & story
| # | Gap | Evidence | Fix seam | Sev |
|---|---|---|---|---|
| G1 | Core landing dashboard is a starter template: hardcoded "Account created ✓" checklist (`DashboardPage.tsx:142`), static "Platform Ready" banner (`:333-343`), four scalar tiles. Nothing shows the agent fleet, approvals, budget regime, or kill-switch state — all live APIs 1-3 clicks away | fe-core survey §C | Replace `DashboardOverview` with mission-control overview; zero backend needed | P1 |
| G2 | Extension overview (`SystemOverview.tsx`, 499 lines) is count cards + lists; no fleet picture, no time dimension; metric-card links go to pre-redirect paths (`:134-187`) | fe-ext §A/G1 | Rebuild as Fleet Command (see concept); fix links | P1 |
| G3 | **No fleet topology exists anywhere** — no node/instance/module containment view, no provider/region map. Compute = 5 independent tables | fe-ext §D | New React Flow fleet graph reusing `SystemTopology` patterns + entityRegistry links; feeds from existing list APIs + `SystemFleetChannel` | P1 |
| G4 | Kill-switch banner renders only on the autonomy page itself (`AutonomyDashboardPage.tsx:70-84`) — the most safety-critical indicator is invisible everywhere else | fe-core §H3 | Mount `KillSwitchStatusBar` in `DashboardLayout.tsx` beside the 4 global modal hosts | P1 |

### Wasted/buried graph substrate
| # | Gap | Evidence | Fix seam | Sev |
|---|---|---|---|---|
| G5 | Template Composer fetches, types, and **discards** `dependency_graph` (`templatesApi.ts:165-168`; backend populates via `template_composition_analysis.rb:106`); renders composition as an ordered list + 3 bare footprint numbers; copy says drag-and-drop but it's an Add button (`TemplateComposerPage.tsx:124`) | fe-ext §C | Render the graph with React Flow + dagre (own header comment already plans it, `:24-26`) | P2 |
| G6 | Composer page is **URL-only** — route registered, no nav entry, no in-app link (`register.ts` grep) | fe-ext §A | Add nav entry + "Compose" button on templates tab | P2 |
| G7 | Per-network `SdwanTopology` reachable only inside `NetworkDetailModal.tsx:245`; naive radial layout; hub-ness inferred from edge-count symmetry instead of `publicly_reachable` (`SdwanTopology.tsx:121-129`); labels are IPv6 fragments | fe-ext §B/D | Promote to Networks tab; reuse `SystemTopology`'s server-layout + custom-node approach | P2 |
| G8 | Correlation chains (a DAG) render as flat sorted list (`FleetDashboardPage.tsx:363-372`); boot replay timeline has no proportional time axis (`BootReplayTimeline.tsx:75-86`) | fe-ext §G3 | MissionTaskGraph pattern for chains; time-scaled axis for replay | P3 |
| G9 | Both topology graphs are fetch-once with manual refresh — neither subscribes to `SystemFleetChannel` (5 other components do) | fe-ext §F | Subscribe + patch node/edge state on `system.instance_*` / drift events | P2 |

### Governance visibility
| # | Gap | Evidence | Fix seam | Sev |
|---|---|---|---|---|
| G10 | Autonomy suite buried: sidebar-in-tab-in-tab (`/app/ai/agents` → Autonomy → 13 sections) | fe-core §H3 | Top-level nav entry + landing-page summary tiles deep-linking to sections | P1 |
| G11 | **Orphaned built surfaces**: `ShadowModeResultsPanel` exported, never rendered; `ApprovalChainList`/`Editor` have no core route (only host-api export) despite `approval_chain` being a registered entity type; `useChartColors` dead | fe-core §D/H4 | Mount shadow panel as autonomy section; route the chain editor; adopt or delete the hook | P2 |
| G12 | Consent budgets: extension has a bare number editor (`ConsentBudgetEditor.tsx` — used/remaining as plain text, no meter/history); core has zero representation. The §6 "one spend ledger" gap starts here | both surveys | Meter component in the fleet dashboard + budget strip on Fleet Command; unify with BudgetAllocationPanel vocabulary | P2 |
| G13 | Extension's ~51 intervention policies (Fleet Autonomy + SDWAN Manager) have no surface in the extension's own pages; approval appears only in Concierge chat + one ingress panel; no missions/agent roster page extension-side; `MissionChannel` has zero extension subscribers | fe-ext §E/F | componentSlots: core autonomy panels slotted into extension operations hub; MissionChannel subscription on fleet page | P2 |
| G14 | Nothing correlates governance to infrastructure: no fleet nav in core; can't see which node an escalated decision ran on, what a mission phase cost, which agent drew a module's budget — despite entityRegistry having all 37 types registered | fe-core §H5 | EntityLink joins in event feed/approval cards/topology side panel | P1 |

### Economy visibility
| # | Gap | Evidence | Fix seam | Sev |
|---|---|---|---|---|
| G15 | `Ai::AgentModelPerformance` — the measurement the platform *routes by* — is unsurfaced (only nested team data). The bandit's learning is invisible | fe-core §E(c) | Model-performance panel on ModelRouterPage; per-agent chart on agent detail | P2 |
| G16 | Trust scores are point-in-time; no history/trend despite decay being a core mechanic | fe-core §D(b) | Sparkline on TrustScoreCard from trust events | P3 |
| G17 | Model Router + Escalations (the governed-routing story) is 3 clicks deep with no nav entry | fe-core §E | Nav entry + Fleet Command tile (escalated-spend share) | P2 |
| G18 | **The MCP improvement queue has no UI at all** — list/approve/dismiss/revert exist only as MCP actions; the 23 pending offers are invisible in the browser | fe-core §F | New improvements page (campaigns' ProposalsQueuePanel is the pattern); entity type + approve/dismiss actions | P2 |

### Foundation
| # | Gap | Evidence | Fix seam | Sev |
|---|---|---|---|---|
| G19 | No shared chart kit: recharts confined to 2 folders, palette misplaced in agent-teams, hand-rolled SVG variants drifting, zero chart primitives in `shared/components/ui/` | fe-core §B/H2 | Promote ChartFrame + a sparkline/stat-tile/meter set into `shared/components/charts/`; wire `useChartColors` as the palette seam (theme-aware) | P1 (prereq for G1/G2) |

## 4. Priority build plan

**Phase 1 — tell the story with what exists (no backend):**
G19 chart kit → G1 core landing replacement → G4 global kill-switch banner →
G10 nav promotion → G6/G17 nav entries → G11 mount orphans.

**Phase 2 — draw the fleet:** G3 fleet topology graph (the Fleet Command
centerpiece) → G2 extension overview rebuild → G5 composer dependency graph →
G7 SdwanTopology promotion/upgrade → G9 live topology.

**Phase 3 — join governance to infrastructure:** G14 EntityLink joins →
G12 consent-budget meters → G13 slotted governance panels + MissionChannel →
G18 improvements UI.

**Phase 4 — polish:** G8 DAG/timeline forms, G15/G16 performance + trust trends.

## 5. Notes

- Backend health verified same day: all-green signal feed, autonomous
  pool→provision→enroll→build→sign→publish loop demonstrably running (see
  session log 2026-08-06). The UI gaps are presentation, not data availability —
  every widget in the companion concept binds to an API that already exists.
- The 2026-08-05 improvement offers (13, `powernode/powernode-system`) cover the
  MCP-side by-intent holes; this report is the UI-side counterpart. Both feed
  the same vision: §6 of the strategy memo.
