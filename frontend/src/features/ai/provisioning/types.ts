/**
 * Shared types for the AI provisioning UX (M1).
 *
 * Mirrors the backend contract emitted by `Ai::Provisioning::PlanComposerService`
 * and surfaced to the concierge via the provisioning tool registry.
 */

export interface ScaleProfile {
  initial?: number;
  target?: number;
  growth_profile?: string;
}

export type RuntimeHint = 'node' | 'python' | 'ruby' | 'go' | 'docker' | 'java' | 'none';

export interface ProjectBrief {
  intent?: string | null;
  use_case?: string | null;
  scale?: ScaleProfile | null;
  regions?: string[] | null;
  compliance?: string[] | null;
  budget_cap_usd_monthly?: number | null;
  latency_targets_ms?: { p99?: number } | null;
  data_residency?: string[] | null;
  preferred_provider?: string | null;
  /** M3 — "Run My Code": user-supplied Git repository URL. */
  repo_url?: string | null;
  /** M3 — branch override; defaults to the repo's HEAD when null. */
  branch?: string | null;
  /** M3 — runtime entrypoint command. */
  start_command?: string | null;
  /** M3 — runtime detection hint, used by the planner to pick a base image. */
  runtime_hint?: RuntimeHint | null;
}

/**
 * Required brief fields — mirror of `IntentCaptureService::REQUIRED_FIELDS`.
 * Brief is "ready to plan" when none of these are listed in `missing_fields`.
 */
export const REQUIRED_BRIEF_FIELDS = [
  'intent',
  'use_case',
  'scale',
  'regions',
  'budget_cap_usd_monthly'
] as const;

/**
 * Ai::GoalPlanStep::STATUSES, which Ai::Provisioning::PlanSnapshotService serves
 * RAW as each DAG node's `status` — plus `running`, a client-side alias for the
 * server's `executing` that predates this type and is still emitted locally.
 *
 * `awaiting_approval` is a step parked by SkillCompositionRunner on an autonomy
 * gate: neither started-and-running nor terminal. Any member missing here falls
 * through `stepIcon`'s `default` and renders as the pending circle, so a blocked
 * or in-flight step reads as "not started yet" — which is how both
 * `awaiting_approval` and `executing` were rendering.
 */
export type PlanStepStatus =
  | 'pending'
  | 'executing'
  | 'running'
  | 'completed'
  | 'failed'
  | 'skipped'
  | 'awaiting_approval';

export interface PlanStep {
  id: string;
  name?: string;
  description?: string;
  action?: string;
  skill?: string;
  status?: PlanStepStatus;
  inputs?: Record<string, unknown>;
}

export interface PlanEdge {
  source: string;
  target: string;
}

export type CostConfidence = 'high' | 'med' | 'low';
export type RiskSeverity = 'low' | 'med' | 'high';

export interface CostByResource {
  resource_type: string;
  name: string;
  monthly_usd: number;
  count: number;
}

export interface CostEstimate {
  monthly_usd: number;
  one_time_usd: number;
  confidence: CostConfidence;
  by_resource: CostByResource[];
  /** ISO timestamp surfaced as a hover hint on the confidence pill. */
  last_priced_at?: string | null;
}

export type TopologyNodeType =
  | 'compute'
  | 'volume'
  | 'database'
  | 'cache'
  | 'network'
  | 'gateway'
  | 'user_device'
  | 'external_provider';

export interface TopologyNode {
  id: string;
  type: TopologyNodeType;
  label: string;
  region_id?: string;
  parent_id?: string;
}

export interface TopologyEdge {
  source: string;
  target: string;
  label?: string;
}

export interface TopologyRegion {
  id: string;
  name: string;
}

export interface TopologyPreview {
  nodes: TopologyNode[];
  edges: TopologyEdge[];
  regions: TopologyRegion[];
}

export interface RiskFactor {
  name: string;
  weight: number;
  severity: string;
  explanation: string;
}

export interface RiskAssessment {
  /** 0–100 — higher means riskier. */
  score: number;
  severity: RiskSeverity;
  factors: RiskFactor[];
}

export interface ProvisioningPlan {
  plan_id: string;
  dag: { nodes: PlanStep[]; edges: PlanEdge[] };
  cost_estimate: CostEstimate;
  topology_preview: TopologyPreview;
  risk: RiskAssessment;
}
