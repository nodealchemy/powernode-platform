export type CampaignStatus = 'created' | 'active' | 'paused' | 'completed' | 'archived';
export type DecisionAuthority = 'supervised' | 'monitored' | 'trusted' | 'autonomous';
export type ParkedQuestionStatus = 'open' | 'answered' | 'dismissed';

// Mirrors Ai::Campaign#driver_lease_info — the active single-driver lease, or null when free
export interface DriverLease {
  holder: string;
  expires_at: string;
}

// Mirrors Ai::Campaign#summary
export interface CampaignSummary {
  id: string;
  name: string;
  status: CampaignStatus;
  decision_authority: DecisionAuthority;
  loop_count: number;
  total_tasks: number;
  completed_tasks: number;
  failed_tasks: number;
  blocked_tasks: number;
  open_questions: number;
  completion_pct: number;
  started_at: string | null;
  completed_at: string | null;
  last_activity_at: string | null;
  driver_lease: DriverLease | null;
}

// Mirrors one entry of Ai::Campaign#activity_feed
export interface ActivityEvent {
  kind: 'decision' | 'parked_question' | 'task';
  status: string;
  title: string | null;
  at: string;
}

// Mirrors Ai::ParkedQuestion#summary
export interface ParkedQuestion {
  id: string;
  question: string;
  context: string | null;
  status: ParkedQuestionStatus;
  answer: string | null;
  ralph_task_id: string | null;
  asked_at: string;
  answered_at: string | null;
}

// Mirrors Ai::CampaignDecision#summary
export interface CampaignDecision {
  id: string;
  decision_type: string;
  title: string;
  rationale: string | null;
  ralph_task_id: string | null;
  decided_by: string | null;
  decided_at: string;
}

// Mirrors Ai::ProgressEntry#summary
export interface ProgressEntry {
  recorded_at: string;
  total_tasks: number;
  completed_tasks: number;
  failed_tasks: number;
  blocked_tasks: number;
  completion_pct: number;
  per_loop_summary: Record<string, unknown>;
  improvement_metrics: Record<string, unknown>;
}

// Who drives a campaign loop's task queue (delegation control plane).
export type DriverKind = 'claude_code' | 'platform_agent' | 'platform_team' | 'platform_mission';

export interface CampaignLoop {
  id: string;
  name: string;
  branch: string | null;
  status: string;
  driver_kind: DriverKind | null;
  driver_target: Record<string, unknown>;
  total_tasks: number;
}

// ----- Discovery/delegation control plane: the campaign-proposal queue -----
export type ProposalStatus = 'proposed' | 'queued' | 'approved' | 'rejected' | 'spawned';
export type ProposalSource = 'discovery' | 'trajectory' | 'improvement' | 'manual';

// Mirrors Ai::CampaignProposal#summary
export interface CampaignProposal {
  id: string;
  title: string;
  objective: string;
  source: ProposalSource;
  scope: string | null;
  status: ProposalStatus;
  suggested_workload: string;
  suggested_driver: DriverKind | null;
  decision_authority: DecisionAuthority;
  fingerprint: string;
  spawned_campaign_id: string | null;
  reviewed_by_id: string | null;
  reviewed_at: string | null;
  rejection_reason: string | null;
  created_at: string;
  updated_at: string;
}

// Mirrors CampaignsController#serialize_detail (summary + nested collections)
export interface CampaignDetail extends CampaignSummary {
  description: string | null;
  configuration: Record<string, unknown>;
  stop_conditions: Record<string, unknown>;
  open_questions_list: ParkedQuestion[];
  recent_decisions: CampaignDecision[];
  activity: ActivityEvent[];
  progress: ProgressEntry[];
  loops: CampaignLoop[];
}

export interface CreateCampaignParams {
  name: string;
  description?: string;
  decision_authority?: DecisionAuthority;
  configuration?: Record<string, unknown>;
  stop_conditions?: Record<string, unknown>;
}

export interface CreateProposalParams {
  title: string;
  objective: string;
  source?: ProposalSource;
  scope?: string;
  suggested_workload?: string;
  suggested_driver?: DriverKind;
  decision_authority?: DecisionAuthority;
  configuration?: Record<string, unknown>;
}

export interface DelegateParams {
  driver_kind: DriverKind;
  target?: Record<string, unknown>;
  holder?: string;
}

// Mirrors CampaignDriver#delegate's return
export interface DelegateResult {
  campaign_id: string;
  driver_kind: DriverKind;
  target: Record<string, unknown>;
  lease: DriverLease | null;
  loops: Array<{ id: string; driver_kind: DriverKind | null; scheduling_mode: string; status: string }>;
}
