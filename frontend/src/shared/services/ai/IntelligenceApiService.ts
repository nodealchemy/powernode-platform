/**
 * Intelligence API Service
 * Phase 1-4: Agent Learning, Self-Improvement, and Emergent Coordination
 *
 * Covers:
 * - Experience Replays (agent learning from past executions)
 * - Self-Challenges (agent self-improvement through adversarial tasks)
 * - Stigmergic Signals (ant-colony-inspired team coordination)
 * - Pressure Fields (gradient-based team coordination)
 * - Team Restructure Events (dynamic team evolution)
 * - Goal Plans (decomposed goal execution)
 */

import { BaseApiService, PaginatedResponse, QueryFilters } from '@/shared/services/ai/BaseApiService';

// ==========================================
// Experience Replay Types
// ==========================================
export interface ExperienceReplay {
  id: string;
  compressed_example: string;
  status: 'active' | 'archived' | 'expired';
  quality_score: number | null;
  effectiveness_score: number | null;
  injection_count: number;
  positive_outcome_count: number;
  negative_outcome_count: number;
  last_injected_at: string | null;
  source_execution_id: string | null;
  created_at: string;
}

// ==========================================
// Self-Challenge Types
// ==========================================
export type ChallengeStatus = 'pending' | 'generating' | 'executing' | 'validating' | 'completed' | 'failed' | 'abandoned';
export type ChallengeDifficulty = 'easy' | 'medium' | 'hard' | 'expert';

export interface SelfChallenge {
  id: string;
  challenge_id: string;
  status: ChallengeStatus;
  difficulty: ChallengeDifficulty;
  challenge_prompt: string | null;
  expected_criteria: Record<string, unknown>;
  response: string | null;
  quality_score: number | null;
  validation_result: Record<string, unknown>;
  skill: { id: string; name: string } | null;
  executor_agent: { id: string; name: string } | null;
  validator_agent: { id: string; name: string } | null;
  created_at: string;
}

export interface IntelligenceSummary {
  experience_replays: {
    total: number;
    active: number;
    avg_quality: number;
    avg_effectiveness: number;
  };
  self_challenges: {
    total: number;
    active: number;
    completed: number;
    pass_rate: number;
  };
}

// ==========================================
// Coordination Types
// ==========================================
export type SignalType = 'pheromone' | 'pressure' | 'beacon' | 'warning' | 'discovery';

export interface StigmergicSignal {
  id: string;
  signal_type: SignalType;
  signal_key: string;
  strength: number;
  decay_rate: number;
  reinforce_count: number;
  perceive_count: number;
  payload: Record<string, unknown>;
  emitter_agent: { id: string; name: string } | null;
  expires_at: string | null;
  created_at: string;
}

export type PressureFieldType = 'code_quality' | 'test_coverage' | 'doc_readability' | 'security_posture' | 'performance' | 'dependency_health';

export interface PressureField {
  id: string;
  field_type: PressureFieldType;
  artifact_ref: string;
  pressure_value: number;
  threshold: number;
  decay_rate: number;
  dimensions: Record<string, unknown>;
  actionable: boolean;
  address_count: number;
  last_measured_at: string | null;
  last_addressed_at: string | null;
  created_at: string;
}

export type TeamEventType = 'role_change' | 'member_recruited' | 'member_released' | 'leader_emerged' | 'capability_gap';

export interface TeamRestructureEvent {
  id: string;
  event_type: TeamEventType;
  team: { id: string; name: string } | null;
  agent: { id: string; name: string } | null;
  previous_state: Record<string, unknown>;
  new_state: Record<string, unknown>;
  rationale: Record<string, unknown>;
  metrics_snapshot: Record<string, unknown>;
  created_at: string;
}

export interface CoordinationSummary {
  signals: {
    total: number;
    active: number;
    fading: number;
    by_type: Record<string, number>;
  };
  pressure_fields: {
    total: number;
    actionable: number;
    by_type: Record<string, number>;
    avg_pressure: number;
  };
  team_events: {
    total: number;
    recent_24h: number;
    by_type: Record<string, number>;
  };
}

// ==========================================
// Goal Plan Types
// ==========================================
export type GoalPlanStatus = 'draft' | 'validated' | 'approved' | 'executing' | 'completed' | 'failed' | 'rejected';
export type GoalPlanStepStatus = 'pending' | 'executing' | 'completed' | 'failed' | 'skipped';
export type GoalPlanStepType = 'agent_execution' | 'workflow_run' | 'observation' | 'human_review' | 'sub_goal';

export interface GoalPlanStep {
  id: string;
  step_number: number;
  step_type: GoalPlanStepType;
  description: string | null;
  status: GoalPlanStepStatus;
  dependencies: number[];
  execution_config: Record<string, unknown>;
  result_summary: string | null;
  started_at: string | null;
  completed_at: string | null;
}

export interface GoalPlan {
  id: string;
  status: GoalPlanStatus;
  version: number;
  plan_data: Record<string, unknown>;
  validation_result: Record<string, unknown>;
  risk_assessment: Record<string, unknown>;
  progress_percentage: number;
  agent: { id: string; name: string } | null;
  approved_by_id: string | null;
  approved_at: string | null;
  completed_at: string | null;
  created_at: string;
  steps?: GoalPlanStep[];
}

// ==========================================
// Service
// ==========================================
class IntelligenceApiService extends BaseApiService {
  // ---- Agent Intelligence ----

  async getIntelligenceSummary(agentId: string): Promise<{ summary: IntelligenceSummary }> {
    return this.get(`/ai/agents/${agentId}/intelligence/summary`);
  }

  async getExperienceReplays(agentId: string, filters: QueryFilters & {
    status?: string;
    few_shot?: string;
  } = {}): Promise<PaginatedResponse<ExperienceReplay>> {
    const queryString = this.buildQueryString(filters);
    return this.get<PaginatedResponse<ExperienceReplay>>(`/ai/agents/${agentId}/intelligence/experience_replays${queryString}`);
  }

  async getSelfChallenges(agentId: string, filters: QueryFilters & {
    status?: string;
    difficulty?: string;
  } = {}): Promise<PaginatedResponse<SelfChallenge>> {
    const queryString = this.buildQueryString(filters);
    return this.get<PaginatedResponse<SelfChallenge>>(`/ai/agents/${agentId}/intelligence/self_challenges${queryString}`);
  }

  // ---- Coordination Dashboard ----

  async getCoordinationSummary(): Promise<{ summary: CoordinationSummary }> {
    return this.get('/ai/coordination/summary');
  }

  async getSignals(filters: QueryFilters & {
    active?: string;
    signal_type?: string;
  } = {}): Promise<PaginatedResponse<StigmergicSignal>> {
    const queryString = this.buildQueryString(filters);
    return this.get<PaginatedResponse<StigmergicSignal>>(`/ai/coordination/signals${queryString}`);
  }

  async getPressureFields(filters: QueryFilters & {
    actionable?: string;
    field_type?: string;
  } = {}): Promise<PaginatedResponse<PressureField>> {
    const queryString = this.buildQueryString(filters);
    return this.get<PaginatedResponse<PressureField>>(`/ai/coordination/pressure_fields${queryString}`);
  }

  async getTeamEvents(filters: QueryFilters & {
    event_type?: string;
    team_id?: string;
  } = {}): Promise<PaginatedResponse<TeamRestructureEvent>> {
    const queryString = this.buildQueryString(filters);
    return this.get<PaginatedResponse<TeamRestructureEvent>>(`/ai/coordination/team_events${queryString}`);
  }

  // ---- Goal Plans ----

  async getGoalPlans(goalId: string): Promise<{ plans: GoalPlan[] }> {
    return this.get(`/ai/goals/${goalId}/plans`);
  }

  async getGoalPlan(goalId: string, planId: string): Promise<{ plan: GoalPlan }> {
    return this.get(`/ai/goals/${goalId}/plans/${planId}`);
  }
}

export const intelligenceApi = new IntelligenceApiService();
