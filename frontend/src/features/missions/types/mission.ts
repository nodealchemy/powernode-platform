export type MissionType = 'development' | 'research' | 'operations' | 'custom';
export type MissionStatus = 'draft' | 'active' | 'paused' | 'completed' | 'failed' | 'cancelled';

export type MissionPhase = string;

export type ApprovalGate = 'feature_selection' | 'prd_review' | 'code_review' | 'merge_approval';
export type ApprovalDecision = 'approved' | 'rejected';

export interface FeatureSuggestion {
  title: string;
  description: string;
  complexity: string;
  files_affected: string[];
}

export interface RepoAnalysis {
  tech_stack: Record<string, unknown>;
  structure: Record<string, unknown>;
  recent_activity: Record<string, unknown>;
  feature_suggestions: FeatureSuggestion[];
}

export interface PhaseEntry {
  phase: string;
  entered_at: string;
  exited_at?: string;
  result?: Record<string, unknown>;
}

export interface MissionApproval {
  id: string;
  gate: ApprovalGate;
  decision: ApprovalDecision;
  comment: string | null;
  user: string | null;
  created_at: string;
}

export interface Mission {
  id: string;
  account_id: string;
  name: string;
  description: string | null;
  mission_type: MissionType;
  status: MissionStatus;
  objective: string | null;
  current_phase: MissionPhase | null;
  phase_progress: number;
  phases: string[];
  phase_config: Record<string, unknown>;
  analysis_result: Record<string, unknown>;
  feature_suggestions: FeatureSuggestion[];
  selected_feature: Record<string, unknown>;
  prd_json: Record<string, unknown>;
  test_result: Record<string, unknown>;
  review_result: Record<string, unknown>;
  phase_history: PhaseEntry[];
  configuration: Record<string, unknown>;
  metadata: Record<string, unknown>;
  branch_name: string | null;
  base_branch: string;
  pr_number: number | null;
  pr_url: string | null;
  deployed_port: number | null;
  deployed_url: string | null;
  deployed_container_id: string | null;
  error_message: string | null;
  error_details: Record<string, unknown>;
  repository_id: string | null;
  team_id: string | null;
  conversation_id: string | null;
  ralph_loop_id: string | null;
  risk_contract_id: string | null;
  review_state_id: string | null;
  mission_template_id: string | null;
  custom_phases: PhaseDefinition[] | null;
  approval_gate_phases: string[];
  repository?: { id: string; name: string; full_name: string };
  team?: { id: string; name: string };
  created_by?: { id: string; name: string; email: string };
  approvals?: MissionApproval[];
  started_at: string | null;
  completed_at: string | null;
  duration_ms: number | null;
  created_at: string;
  updated_at: string;
}

export interface CreateMissionParams {
  name: string;
  description?: string;
  mission_type: MissionType;
  objective?: string;
  repository_id?: string;
  team_id?: string;
  base_branch?: string;
  phase_config?: Record<string, unknown>;
  configuration?: Record<string, unknown>;
  mission_template_id?: string;
  custom_phases?: PhaseDefinition[];
}

export interface MissionWebSocketEvent {
  event: string;
  payload: Record<string, unknown>;
  timestamp: string;
}


// Task Graph types
export type RalphTaskStatus = 'pending' | 'in_progress' | 'passed' | 'failed' | 'blocked' | 'skipped';
export type ExecutionType = 'agent' | 'workflow' | 'pipeline' | 'a2a_task' | 'container' | 'human' | 'community';

export interface TaskGraphNode {
  id: string;
  task_key: string;
  description: string | null;
  status: RalphTaskStatus;
  execution_type: ExecutionType;
  priority: number | null;
  position: number;
  dependencies: string[];
  executor_type: string | null;
  executor_name: string | null;
  phase: string | null;
  metadata: Record<string, unknown>;
}

export interface TaskGraphEdge {
  id: string;
  source: string;
  target: string;
}

export interface TaskGraph {
  nodes: TaskGraphNode[];
  edges: TaskGraphEdge[];
}

// Phase definitions for templates
export interface PhaseDefinition {
  key: string;
  label: string;
  description?: string;
  requires_approval?: boolean;
  job_class?: string;
  estimated_duration_minutes?: number;
  skip_allowed?: boolean;
  order: number;
}

export interface MissionTemplate {
  id: string;
  name: string;
  description: string | null;
  template_type: 'system' | 'account' | 'community';
  mission_type: MissionType;
  phase_count: number;
  phase_keys: string[];
  phases?: PhaseDefinition[];
  approval_gates: string[];
  rejection_mappings?: Record<string, string>;
  skill_compositions?: Record<string, unknown>;
  default_configuration?: Record<string, unknown>;
  is_default: boolean;
  version: number;
  status: string;
  account_id: string | null;
  created_at?: string;
  updated_at?: string;
}

export function isApprovalGate(phase: MissionPhase | null, approvalGatePhases?: string[]): boolean {
  if (!phase || !approvalGatePhases) return false;
  return approvalGatePhases.includes(phase);
}

export function phaseLabel(phase: string): string {
  return phase.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
}
