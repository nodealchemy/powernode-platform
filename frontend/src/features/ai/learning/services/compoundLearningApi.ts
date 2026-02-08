import { apiClient } from '@/shared/services/apiClient';

export interface CompoundLearning {
  id: string;
  category: string;
  title: string | null;
  content: string;
  importance_score: number;
  confidence_score: number;
  effectiveness_score: number | null;
  effective_importance: number;
  injection_count: number;
  positive_outcome_count: number;
  negative_outcome_count: number;
  access_count: number;
  status: string;
  scope: string;
  tags: string[];
  extraction_method: string;
  source_execution_successful: boolean | null;
  ai_agent_team_id: string | null;
  source_agent_id: string | null;
  promoted_at: string | null;
  last_injected_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface CompoundMetrics {
  total_learnings: number;
  active_learnings: number;
  by_category: Record<string, number>;
  by_scope: Record<string, number>;
  avg_importance: number;
  avg_effectiveness: number | null;
  most_effective: CompoundLearning[];
  recently_added: CompoundLearning[];
  compound_score: number;
}

export interface LearningFilters {
  status?: string;
  category?: string;
  scope?: string;
  min_importance?: number;
  team_id?: string;
  query?: string;
  limit?: number;
}

export const fetchCompoundMetrics = async (): Promise<CompoundMetrics> => {
  const response = await apiClient.get('/api/v1/ai/learning/compound_metrics');
  return response.data?.metrics;
};

export const fetchLearnings = async (filters: LearningFilters = {}): Promise<CompoundLearning[]> => {
  const params = new URLSearchParams();
  if (filters.status) params.set('status', filters.status);
  if (filters.category) params.set('category', filters.category);
  if (filters.scope) params.set('scope', filters.scope);
  if (filters.min_importance) params.set('min_importance', filters.min_importance.toString());
  if (filters.team_id) params.set('team_id', filters.team_id);
  if (filters.query) params.set('query', filters.query);
  if (filters.limit) params.set('limit', filters.limit.toString());

  const response = await apiClient.get(`/api/v1/ai/learning/learnings?${params.toString()}`);
  return response.data?.learnings || [];
};

export const reinforceLearning = async (id: string): Promise<CompoundLearning> => {
  const response = await apiClient.post(`/api/v1/ai/learning/reinforce/${id}`);
  return response.data?.learning;
};

export const promoteCrossTeam = async (): Promise<number> => {
  const response = await apiClient.post('/api/v1/ai/learning/promote');
  return response.data?.promoted_count || 0;
};
