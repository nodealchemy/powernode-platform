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

export interface CampaignLoop {
  id: string;
  name: string;
  branch: string | null;
  status: string;
  total_tasks: number;
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
