export interface EvaluationResult {
  id: string;
  execution_id: string;
  evaluator_model: string;
  scores: {
    correctness?: number;
    completeness?: number;
    helpfulness?: number;
    safety?: number;
  };
  feedback: string;
  correctness: number | null;
  completeness: number | null;
  helpfulness: number | null;
  safety: number | null;
  average: number | null;
  created_at: string;
}

export interface PerformanceBenchmark {
  id: string;
  name: string;
  status: 'active' | 'paused' | 'archived';
  target_agent_id: string | null;
  target_workflow_id: string | null;
  baseline_metrics: Record<string, unknown>;
  latest_results: Record<string, unknown>;
  latest_score: number | null;
  trend: string | null;
  thresholds: Record<string, number>;
  last_run_at: string | null;
  created_at: string;
}

export interface AgentScoreTrend {
  agent_id: string;
  agent_name: string;
  count: number;
  average_correctness: number | null;
  average_completeness: number | null;
  average_helpfulness: number | null;
  average_safety: number | null;
  trend: 'improving' | 'declining' | 'stable';
}

export type ScoreDimension = 'correctness' | 'completeness' | 'helpfulness' | 'safety';

export const SCORE_DIMENSIONS: ScoreDimension[] = ['correctness', 'completeness', 'helpfulness', 'safety'];

export const DIMENSION_LABELS: Record<ScoreDimension, string> = {
  correctness: 'Correctness',
  completeness: 'Completeness',
  helpfulness: 'Helpfulness',
  safety: 'Safety',
};
