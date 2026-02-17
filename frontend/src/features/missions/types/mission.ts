export type MissionType = 'development' | 'research' | 'operations';
export type MissionStatus = 'draft' | 'active' | 'paused' | 'completed' | 'failed' | 'cancelled';

export type DevelopmentPhase =
  | 'analyzing' | 'awaiting_feature_approval' | 'planning' | 'awaiting_prd_approval'
  | 'executing' | 'testing' | 'reviewing' | 'awaiting_code_approval'
  | 'deploying' | 'previewing' | 'merging' | 'completed';

export type ResearchPhase = 'researching' | 'analyzing' | 'reporting' | 'completed';
export type OperationsPhase = 'configuring' | 'executing' | 'verifying' | 'completed';
export type MissionPhase = DevelopmentPhase | ResearchPhase | OperationsPhase;

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
}

export interface MissionWebSocketEvent {
  event: string;
  payload: Record<string, unknown>;
  timestamp: string;
}

export const DEVELOPMENT_PHASES: DevelopmentPhase[] = [
  'analyzing', 'awaiting_feature_approval', 'planning', 'awaiting_prd_approval',
  'executing', 'testing', 'reviewing', 'awaiting_code_approval',
  'deploying', 'previewing', 'merging', 'completed'
];

export const RESEARCH_PHASES: ResearchPhase[] = ['researching', 'analyzing', 'reporting', 'completed'];
export const OPERATIONS_PHASES: OperationsPhase[] = ['configuring', 'executing', 'verifying', 'completed'];

export const APPROVAL_GATES: MissionPhase[] = [
  'awaiting_feature_approval', 'awaiting_prd_approval', 'awaiting_code_approval', 'previewing'
];

export function phasesForType(type: MissionType): MissionPhase[] {
  switch (type) {
    case 'development': return DEVELOPMENT_PHASES;
    case 'research': return RESEARCH_PHASES;
    case 'operations': return OPERATIONS_PHASES;
  }
}

export function isApprovalGate(phase: MissionPhase | null): boolean {
  return phase !== null && APPROVAL_GATES.includes(phase);
}

export function phaseLabel(phase: string): string {
  return phase.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
}
