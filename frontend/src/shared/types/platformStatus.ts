// The component status plane's wire vocabulary (design §4).
//
// This module is the TypeScript half of one contract whose Ruby half is
// `Platform::ComponentStatusSerializer` — the single wire shape shared by the
// REST door (`Api::V1::Platform::ComponentStatusesController`) and the MCP
// tool. Two hand-rolled shapes for the same row is how a page and an agent end
// up disagreeing about whether something is down; two hand-rolled shapes for
// the same row ACROSS LANGUAGES is the same defect with a compiler that cannot
// see the other half. Everything here is annotated with the Ruby name it
// mirrors so the pairing survives a rename on either side.
//
// ── `not_measured` IS THE WIRE NAME ────────────────────────────────────────
//
// The absent-measurement verdict travels as `not_measured` end to end. The
// `unknown` alias the platform-health REST route emits today is a DIFFERENT
// producer, retired with HealthPanel (C4). Nothing here may rename it on the
// way in: a UI that sees `unknown` cannot tell "we did not look" from "the
// value is unknown to you", and those call for different operator actions.

/**
 * The verdict ladder, ASCENDING in severity (design §4.1):
 *
 *   ok < held < progressing < not_measured < degraded < down
 *
 * Declared as a `const` tuple rather than a bare union so the order is data a
 * rollup can compute over, not prose in a comment. `Verdict` is derived from
 * it, which is what makes the two impossible to disagree.
 *
 * - `held` is OPERATOR INTENT — cordoned, paused, drained, on hold. It is
 *   deliberately not a failure, and never renders as one.
 * - `progressing` is an in-flight remediation or provisioning.
 * - `not_measured` is an ABSENT measurement. It ranks below `degraded`
 *   because a missing reading is a gap rather than a failure, but it is never
 *   collapsed into `ok` and never rendered as inert grey. A thing we could
 *   not see is not a thing that is fine.
 * - `degraded` / `down` are observed failures, `down` being total.
 *
 * Mirrors `Platform::ComponentStatus::RANK` (server), whose keys are in this
 * same order.
 */
export const VERDICT_LADDER = [
  'ok',
  'held',
  'progressing',
  'not_measured',
  'degraded',
  'down',
] as const;

/**
 * The CLOSED six-verdict union. Closed on purpose: every consumer switches
 * exhaustively over it, so adding a seventh verdict is a compile error at
 * every rendering site rather than a silent fall-through to a default.
 */
export type Verdict = (typeof VERDICT_LADDER)[number];

/**
 * Severity rank of a verdict — the integer is an ORDERING DEVICE only. Never
 * persist it, never send it over the wire, and never assume the gaps mean
 * anything. Mirrors `Platform::ComponentStatus.rank_of`.
 */
export const VERDICT_RANK: Record<Verdict, number> = {
  ok: 0,
  held: 1,
  progressing: 2,
  not_measured: 3,
  degraded: 4,
  down: 5,
};

/**
 * Verdicts that mean "a person should look at this". `not_measured` is in here
 * on purpose: blindness is actionable. Mirrors
 * `Platform::ComponentStatus::UNHEALTHY_VERDICTS`.
 */
export const UNHEALTHY_VERDICTS: readonly Verdict[] = ['not_measured', 'degraded', 'down'];

/** Narrowing guard for a verdict arriving as a plain string from the wire. */
export function isVerdict(value: unknown): value is Verdict {
  return typeof value === 'string' && (VERDICT_LADDER as readonly string[]).includes(value);
}

// ── Conditions (design §4.2) ────────────────────────────────────────────────

/**
 * A condition's status is THREE-VALUED, and the third value is the string
 * `"unknown"` rather than `null`: in jsonb, null is indistinguishable from an
 * absent key, so "we looked and could not tell" and "nobody wrote this
 * condition" would read identically. Mirrors
 * `Platform::Status::Condition::UNKNOWN`.
 */
export type ConditionStatus = boolean | 'unknown';

/**
 * How bad a FALSE condition is. A false condition is `degraded` unless the
 * contributor asks for `down`; the default must not silently escalate.
 * Mirrors `Platform::Status::Condition::SEVERITIES`.
 */
export type ConditionSeverity = 'degraded' | 'down';

/**
 * One observed fact about a component, shaped like a Kubernetes condition
 * (design §4.2, KEP-1623).
 *
 * `type` and `reason` are UpperCamelCase tokens — stable, greppable, and
 * enforced at construction server-side. They must NEVER be passed to a
 * status-variant lookup: those lowercase their input and would fall through to
 * a default variant, rendering a real error as "unknown" with nothing to show
 * for it. Render `message` to a human; key alerts and runbooks on `reason`.
 */
export interface StatusCondition {
  type: string;
  status: ConditionStatus;
  reason: string;
  /** Human-facing sentence. Null when the reason token says it all. */
  message: string | null;
  /** Only meaningful when `status` is false. */
  severity: ConditionSeverity | null;
  /** The raw numbers the reason was derived from. Never empty-checked as truthy. */
  evidence: Record<string, unknown>;
  observed_generation: string | null;
  observed_at: string | null;
  /**
   * When this condition last CHANGED — not when it was last observed. A sweep
   * runs every 60 s and inherits this verbatim while the status holds, which
   * is what makes "down for three hours" distinguishable from "down for three
   * seconds" and what the root-cause ranking orders by.
   */
  last_transition_at: string | null;
}

// ── Edges, links, actions, presentation ─────────────────────────────────────

/**
 * The five relations design §4.3 names. Use this where you mean "one of the
 * documented five" — a lookup table of labels or icons, say.
 */
export const KNOWN_DEPENDENCY_RELATIONS = [
  'requires',
  'serves',
  'hosts',
  'backs',
  'routes',
] as const;

export type KnownDependencyRelation = (typeof KNOWN_DEPENDENCY_RELATIONS)[number];

/**
 * How a component depends on its neighbour, AS IT ARRIVES ON THE WIRE.
 *
 * Deliberately open, unlike `Verdict` (C1 review F3). The difference is which
 * side of the wire owns the closure. `verdict` is a validated column: the model
 * rejects a value outside `VERDICTS`, so a closed union here is a true
 * statement about what can arrive. `relation` is not validated anywhere —
 * `ComponentStatus` checks only that `dependencies` is an array, `Contributor`
 * documents the five in a comment, and `Rollup.edge_key` reads `kind`/`ref` and
 * never looks at `relation` at all. A contributor emitting `relation: "peers"`
 * is accepted today and arrives here.
 *
 * A closed union would therefore have been a claim the server does not back,
 * and its cost lands on the drawer (C3): TypeScript would believe a `switch`
 * over the five is exhaustive, so an unknown relation would fall through a
 * `default` branch that narrowing said could not happen — or, with no default,
 * render nothing at all. `(string & {})` keeps the five as autocomplete
 * suggestions while letting an unknown one through as a string.
 *
 * C3: render an unrecognized relation as its own text rather than dropping the
 * edge. An edge whose label you do not know is still an edge.
 *
 * The real fix is server-side and is NOT this file's to make: validate
 * `relation` at construction the way `Platform::Status::Condition` already
 * validates its type and reason tokens. Until that lands, this type tells the
 * truth about the wire and the closed union above tells the truth about the
 * design.
 */
export type DependencyRelation = KnownDependencyRelation | (string & {});

/**
 * One dependency edge. The `{kind, ref}` pair is the neighbour's registry key,
 * NOT a row id: an edge may name a component whose row has not been swept yet,
 * and dangling by design beats a foreign key the sweep would have to order
 * around.
 */
export interface ComponentDependency {
  kind: string;
  ref: string;
  relation: DependencyRelation;
}

/** A navigation target the drawer renders. Paths are in-app, not absolute URLs. */
export interface ComponentLink {
  label: string;
  path: string;
}

/**
 * A confirmation the page must collect before issuing an action.
 * `requires_reason` means the operator types a reason that travels with the
 * request — not a checkbox.
 */
export interface ComponentActionConfirm {
  prompt: string;
  requires_reason: boolean;
}

/**
 * A button the page renders FROM DATA. Core learns nothing about the kind: the
 * contributor names the method, path and permission, and the page issues the
 * request.
 *
 * `permission` is the action's OWN permission, checked twice — once here to
 * decide whether to render the button, and again by the door the action names.
 * Holding `platform.status.read` is authority to see the picture, never to run
 * any of these.
 */
export interface ComponentAction {
  key: string;
  label: string;
  method: 'POST' | 'PUT' | 'PATCH' | 'DELETE';
  path: string;
  permission: string;
  destructive: boolean;
  confirm?: ComponentActionConfirm | null;
}

/**
 * How a card draws itself without the page knowing the kind. `icon` is a
 * Lucide icon NAME resolved at render time — the same string convention
 * `FeatureSettingsTab` uses, so an extension never imports a core icon
 * component.
 */
export interface ComponentPresentation {
  icon?: string;
  label?: string;
  group_order?: number;
}

// ── Remediation (design §4.3) ───────────────────────────────────────────────

/**
 * Derived server-side from `SignalState`, `RemediationOutcome`,
 * `ApprovalRequest` and the lane binding — NEVER hand-written by a
 * contributor. Mirrors `Platform::ComponentStatus::REMEDIATION_STATES`.
 *
 * `not_actuatable` is an honest answer, not an error: no lane is bound to this
 * signal kind, so nothing is going to happen without a person.
 */
export type RemediationState =
  | 'none'
  | 'auto_in_progress'
  | 'awaiting_operator'
  | 'stuck'
  | 'remediated'
  | 'not_actuatable';

/** The remediation payload a drawer renders. Every field may be absent. */
export interface ComponentRemediation {
  state?: RemediationState;
  signal_kind?: string | null;
  fingerprint?: string | null;
  approval_request_id?: string | null;
  last_outcome?: string | null;
  stuck?: boolean;
  runbook?: string | null;
  [key: string]: unknown;
}

// ── The row itself ──────────────────────────────────────────────────────────

/**
 * Which half of a plane-filtered list a row came from (design §4.6). The
 * environment filter is THREE-valued, so a card must be able to say whether it
 * sits IN the named plane or is plane-less and riding along. Mirrors
 * `Platform::Status::Query.plane_label`.
 */
export type PlaneLabel = 'in' | 'none';

/**
 * Whether the row belongs to this tenant or to process-wide infrastructure.
 * A `shared` row is written by a contributor whose `account_scoped?` is false,
 * renders in its own section, and NEVER enters a per-account rollup — folding
 * one shared breaker into every tenant's verdict would turn it into every
 * tenant's outage.
 */
export type ComponentScope = 'shared' | 'account';

/**
 * The compact row a list renders. Small on purpose: a client listing 150
 * components pays for every key, and the drawer's payloads are one `get` away.
 * Mirrors `Platform::ComponentStatusSerializer#summary`.
 */
export interface ComponentStatusSummary {
  id: string;
  component_kind: string;
  component_ref: string;
  display_name: string | null;
  verdict: Verdict;
  /**
   * TWO different questions, and the page needs both. `held` is the derived
   * verdict being exactly `held` — nothing else is wrong with it.
   * `held_by_intent` is whether the operator has cordoned, paused or drained
   * it WHATEVER its verdict; that is the half the dual rollup counts and
   * excludes. A cordoned node that is also down reads verdict `down`, `held`
   * false, `held_by_intent` true. Collapsing the two hides either the drain or
   * the outage.
   */
  held: boolean;
  held_by_intent: boolean;
  unhealthy: boolean;
  shared: boolean;
  scope: ComponentScope;
  environment_id: string | null;
  /**
   * The plane's NAMES beside its id (A4b), so a card can label itself without a
   * second fetch. Both null for a plane-less row, which is the ordinary case
   * for most core kinds — render the absence, do not fall back to the id.
   *
   * Optional because a client may be talking to a server that predates A4b.
   */
  environment_slug?: string | null;
  environment_name?: string | null;
  plane: PlaneLabel;
  presentation: ComponentPresentation;
  condition_count: number;
  /**
   * The reason token of the WORST failing condition, so a list row can say why
   * without carrying every condition. Null when nothing is false. CamelCase —
   * never feed it to a status-variant lookup.
   */
  reason: string | null;
  /**
   * The human sentence from the SAME condition the token came from — "no
   * heartbeat for 7m 12s" beside `HeartbeatStale` (A4b). Null when nothing is
   * failing, or when that condition carried no message. Render this to a
   * person; key alerts and runbooks on `reason`.
   *
   * Optional because a client may be talking to a server that predates A4b.
   */
  reason_message?: string | null;
  remediation_state: RemediationState;
  observed_at: string | null;
  last_seen_sweep_at: string | null;
  last_transition_at: string | null;
}

/**
 * Everything the drawer needs. Conditions and dependencies pass through as the
 * contributor wrote them — core does not reshape a kind's evidence.
 * Mirrors `Platform::ComponentStatusSerializer#detail`.
 */
export interface ComponentStatusDetail extends ComponentStatusSummary {
  conditions: StatusCondition[];
  dependencies: ComponentDependency[];
  remediation: ComponentRemediation;
  links: ComponentLink[];
  actions: ComponentAction[];
  observed_generation: string | null;
  last_notified_at: string | null;
}

// ── Rollup and impact ───────────────────────────────────────────────────────

/**
 * The DUAL rollup (design §4.1). `verdict` is the operational verdict over the
 * NON-held children; `held_count` is carried beside it rather than folded in,
 * so a planned drain never turns a header amber while the drained node's own
 * card still tells the truth.
 *
 * `held_count` and `counts_by_verdict` therefore disagree on purpose: a
 * cordoned-and-down node counts once under `down` and once in `held_count`.
 * Mirrors `Platform::Status::Rollup.rollup`.
 */
export interface StatusRollup {
  verdict: Verdict;
  held_count: number;
  counts_by_verdict: Record<Verdict, number>;
  total: number;
}

/**
 * Who is affected downstream. Mirrors `Platform::Status::Rollup.impact`, which
 * reverse-walks the dependency edges to depth 4 from one preloaded set.
 */
export interface StatusImpact {
  count: number;
  worst_verdict: Verdict;
  components: ComponentStatusSummary[];
}

/** The filter as the server echoes it back, so an empty page can name its cause. */
export interface StatusFilters {
  kind?: string;
  verdict?: string;
  environment?: string;
  environment_id?: string;
}

/**
 * `GET /api/v1/platform/component_statuses` — the `data` object.
 *
 * `unknown_environment` distinguishes an empty page under a plane NOBODY HAS
 * from an empty plane. Both render zero rows; only one is a mistake, and the
 * client cannot tell them apart from the count.
 */
export interface ComponentStatusIndexData {
  component_statuses: ComponentStatusSummary[];
  filters: StatusFilters;
  unknown_environment: boolean;
}

/** `GET /api/v1/platform/component_statuses/:id` — the `data` object. */
export interface ComponentStatusShowData {
  component_status: ComponentStatusDetail;
  impact: StatusImpact;
}

/**
 * `GET /api/v1/platform/component_statuses/rollup` — the `data` object.
 *
 * Account rows and shared rows are rolled up SEPARATELY and neither is summed
 * into the other; see `ComponentScope`.
 */
export interface ComponentStatusRollupData {
  rollup: StatusRollup;
  shared: StatusRollup;
  by_kind: Record<string, StatusRollup>;
  shared_by_kind: Record<string, StatusRollup>;
  filters: StatusFilters;
  unknown_environment: boolean;
  observed_at: string;
}

/**
 * `GET /api/v1/platform/component_statuses/:id/impact` — the `data` object.
 *
 * `heuristic` is always true and `heuristic_basis` says why. The ranking is
 * correlation over the dependency graph, NOT proof of causation, and the page
 * must render that label beside it: an unlabelled ranking gets read as an
 * answer.
 */
export interface ComponentStatusImpactData {
  component_status: ComponentStatusSummary;
  impact: StatusImpact;
  root_cause_candidates: ComponentStatusSummary[];
  heuristic: boolean;
  heuristic_basis: string;
}

// ── A9: runbook, remediation route, events, investigations ──────────────────
//
// Five endpoints hang off one component (`:id/runbook`, `:id/remediation_route`,
// `:id/events`, `GET`+`POST :id/investigations`). Every shape below is taken
// from lane 6's A9 report §4, which took them from passing examples rather than
// from intent.

/**
 * How a runbook is provided, and what else the object carries.
 *
 * `none` is not an error: it is the answer when nothing routed the component, or
 * when a kind routed and no runbook is registered for it. Those are DIFFERENT
 * situations and `reason` distinguishes them — see `RunbookReason`.
 */
export type RunbookKind = 'doc' | 'generator' | 'none';

/**
 * Why there is no runbook.
 *
 * - `NoRoutedSignal` — nothing routed this component at all. `signal_kind` is
 *   also null. There is no document because there is no lane.
 * - `NotRegistered` / `NotDocumented` — a kind WAS routed and no runbook exists
 *   for it. There is a lane, and its document is missing.
 *
 * Collapsing the two sends an operator looking for a document that was never
 * supposed to exist.
 */
export type RunbookReason = 'NoRoutedSignal' | 'NotRegistered' | 'NotDocumented' | (string & {});

export interface ComponentRunbook {
  kind: RunbookKind;
  /** `doc` only: the display string, e.g. "docs/runbooks/silent.md#triage". */
  doc?: string;
  /**
   * `doc` only. EXTENSION-RELATIVE and deliberately not absolute — core does not
   * know which checkout it belongs to. Never render it as a filesystem link.
   */
  path?: string;
  /** `doc` only; may be null. */
  anchor?: string | null;
  /** `generator` only. */
  generator?: string;
  args?: Record<string, unknown>;
  /** `none` only: whether the signal kind itself is known. */
  known?: boolean;
  /** `none` only. */
  reason?: RunbookReason;
}

/** `GET :id/runbook` — the `data` object. */
export interface ComponentRunbookData {
  component_status_id: string;
  /** Null when nothing routed this component. */
  signal_kind: string | null;
  runbook: ComponentRunbook;
}

/** The lane's report, present only when `routed` is true. */
export interface RemediationRoute {
  state: RemediationState;
  lane_key: string;
  policy: string | null;
  consent: string | null;
  disruption: string | null;
  environment_ceiling: string | null;
  blast_radius: number | null;
  /**
   * `false` with `state: "awaiting_operator"` is the NORMAL combination — a
   * remediation parked at an approval is not an error.
   */
  can_proceed: boolean;
  /**
   * A core token (`NoLaneForSignal`, `LaneError`, `LaneReportedUnknownState`) OR
   * a lane's own sentence. Render as prose; switch only on those three tokens.
   */
  reason: string | null;
  /**
   * Non-null ONLY when a lane returned a state core rejected. When it is present
   * the lane is misbehaving AND its sentence is still the only explanation of
   * the component's situation, so both must be shown. Optional and never
   * defaulted: a fabricated placeholder here would invent a reason.
   */
  lane_reason?: string | null;
  runbook?: ComponentRunbook;
}

/**
 * `GET :id/remediation_route` — the `data` object.
 *
 * BRANCH ON `routed`, never on `route.state`: the `route` key is absent
 * entirely when nothing routed the component.
 */
export interface RemediationRouteData {
  component_status_id: string;
  signal_kind: string | null;
  routed: boolean;
  route?: RemediationRoute;
  reason?: string;
  runbook?: ComponentRunbook;
}

/**
 * One status transition. BOTH nulls are meaningful: a null `from_verdict` is a
 * first sighting, a null `to_verdict` is a removal (the component was reaped).
 * Neither is a missing field.
 */
export interface ComponentStatusEvent {
  id: string;
  kind: 'platform.component_status_changed' | 'platform.component_down' | (string & {});
  from_verdict: Verdict | null;
  to_verdict: Verdict | null;
  occurred_at: string;
  payload: Record<string, unknown>;
}

/** `GET :id/events` — the `data` object. Pagination rides in `meta`, not here. */
export interface ComponentEventsData {
  component_status_id: string;
  events: ComponentStatusEvent[];
}

/**
 * Whether a confidence was MEASURED at all.
 *
 * `not_measured` means the evidence set was empty — a different answer from a
 * confidence of 0. `confidence ?? 0` reports certainty about nothing, which is
 * the exact defect this distinction exists to prevent.
 */
export type ConfidenceState = 'measured' | 'not_measured';

export interface HypothesisConfidenceDetail {
  state: ConfidenceState;
  value: number | null;
  share?: number | null;
  candidates?: number | null;
  evidence_classes?: number | null;
  ceiling?: number | null;
}

export interface InvestigationHypothesis {
  cause: string;
  evidence_refs: string[];
  /** NULL whenever `confidence_state` is `not_measured`. Never coalesce it to 0. */
  confidence: number | null;
  confidence_state: ConfidenceState;
  confidence_detail?: HypothesisConfidenceDetail;
  recommended_action_category?: string | null;
  runbook?: ComponentRunbook | null;
}

export type InvestigationStatus = 'open' | 'completed' | 'failed' | 'abandoned';
export type InvestigationTrigger = 'operator' | 'stuck' | 'down' | (string & {});

/**
 * The evidence an open investigation assembled. One key per evidence class, and
 * EXTENSIONS ADD THEIR OWN — render unknown keys generically rather than
 * allow-listing, or an extension's evidence is invisible.
 *
 * A class present but empty was checked and found nothing. A class named under
 * `errors` could NOT be checked at all, which is a gap rather than an absence
 * and must be shown as one.
 */
/** Stable ranking-outcome tokens (A6). Switch on these; `message` is prose. */
export type InvestigationRankingReason =
  | 'AutomaticSpendNeedsGrant'
  | 'SecurityGateRefused'
  | 'RankerUnusable'
  | 'ProviderError'
  | 'NoPrincipal'
  | (string & {});

/**
 * Why an investigation has no AGENT ranking (A6 G2). ABSENT means ranking has
 * not reported yet — only then is an open investigation still waiting on the
 * worker. Ranking is not an evidence class, so it lives beside `errors`, never
 * inside it: `errors` means only "an evidence source failed".
 */
export interface InvestigationRanking {
  state: 'not_run' | 'refused' | 'failed' | (string & {});
  reason: InvestigationRankingReason;
  message: string;
  /** false: it will NOT be retried. Nothing may promise hypotheses are coming. */
  retryable: boolean;
  attempts: number;
  recorded_at: string;
}

export interface InvestigationEvidence {
  assembled_at?: string;
  window_seconds?: number;
  errors?: Record<string, string>;
  ranking?: InvestigationRanking;
  [evidenceClass: string]: unknown;
}

export interface Investigation {
  id: string;
  component_kind: string;
  component_ref: string;
  trigger: InvestigationTrigger;
  status: InvestigationStatus;
  open: boolean;
  /**
   * STORED ALREADY RANKED. Render in order and never re-sort, or the list will
   * disagree with `conclusion`. An open investigation normally has `[]` here:
   * ranking runs in the worker, so "open with evidence and no hypotheses" is the
   * correct state, not a half-loaded one.
   */
  hypotheses: InvestigationHypothesis[];
  conclusion: string | null;
  agent_id: string | null;
  started_at: string;
  completed_at: string | null;
  /** Present on the OPEN row only; concluded rows ship without it, by design. */
  evidence?: InvestigationEvidence;
}

/** `GET :id/investigations` — the `data` object. `open` holds at most one. */
export interface InvestigationsData {
  component_status_id: string;
  open: Investigation[];
  recent: Investigation[];
  daily_cap: number;
}

/** Why a `POST :id/investigations` was refused. Switch on the token, not the message. */
export type InvestigationRefusal = 'AlreadyOpen' | 'DailyCapReached' | (string & {});
