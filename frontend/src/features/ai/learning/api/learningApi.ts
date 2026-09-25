import { apiClient } from '@/shared/services/apiClient';
import type {
  AgentScoreTrend,
  EvaluationResult,
  PerformanceBenchmark,
} from '@/features/ai/evaluation/types/evaluation';

// The one client for the /ai/learning endpoint family: compound learnings,
// improvement recommendations, evaluation results, benchmarks, and the
// prompt-cache/agent-trend insights. Every method unwraps the server's
// { success, data } envelope, so callers never read .data.data.

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

export type SortField = 'created_at' | 'importance_score' | 'effectiveness_score' | 'injection_count' | 'confidence_score';
export type SortDir = 'asc' | 'desc';

export interface LearningFilters {
  status?: string;
  category?: string;
  scope?: string;
  min_importance?: number;
  team_id?: string;
  query?: string;
  limit?: number;
  offset?: number;
  sort_by?: SortField;
  sort_dir?: SortDir;
}

export interface LearningsPage {
  learnings: CompoundLearning[];
  meta: { total_count: number; offset: number; limit: number };
}

export interface Recommendation {
  id: string;
  recommendation_type: string;
  target_type: string;
  target_id: string;
  current_config: Record<string, unknown>;
  recommended_config: Record<string, unknown>;
  evidence: Record<string, unknown>;
  confidence_score: number;
  status: string;
  created_at: string;
}

export interface CacheMetrics {
  hits: number;
  misses: number;
  hit_rate: number;
  estimated_savings_usd: number;
}

const buildLearningQuery = (filters: LearningFilters): string => {
  const params = new URLSearchParams();
  if (filters.status) params.set('status', filters.status);
  if (filters.category) params.set('category', filters.category);
  if (filters.scope) params.set('scope', filters.scope);
  if (filters.min_importance) params.set('min_importance', filters.min_importance.toString());
  if (filters.team_id) params.set('team_id', filters.team_id);
  if (filters.query) params.set('query', filters.query);
  if (filters.limit) params.set('limit', filters.limit.toString());
  if (filters.offset) params.set('offset', filters.offset.toString());
  if (filters.sort_by) params.set('sort_by', filters.sort_by);
  if (filters.sort_dir) params.set('sort_dir', filters.sort_dir);
  return params.toString();
};

export const learningApi = {
  async getRecommendations(): Promise<Recommendation[]> {
    const response = await apiClient.get('/ai/learning/recommendations');
    return response.data?.data?.recommendations || [];
  },

  async applyRecommendation(id: string): Promise<Recommendation> {
    const response = await apiClient.post(`/ai/learning/recommendations/${id}/apply`);
    return response.data?.data?.recommendation;
  },

  async dismissRecommendation(id: string): Promise<Recommendation> {
    const response = await apiClient.post(`/ai/learning/recommendations/${id}/dismiss`);
    return response.data?.data?.recommendation;
  },

  async getAgentTrends(): Promise<AgentScoreTrend[]> {
    const response = await apiClient.get('/ai/learning/agent_trends');
    return response.data?.data?.trends || [];
  },

  async getCacheMetrics(): Promise<CacheMetrics | null> {
    const response = await apiClient.get('/ai/learning/cache_metrics');
    return response.data?.data?.metrics || null;
  },

  async getCompoundMetrics(): Promise<CompoundMetrics> {
    const response = await apiClient.get('/ai/learning/compound_metrics');
    return response.data?.data?.metrics;
  },

  async getLearnings(filters: LearningFilters = {}): Promise<LearningsPage> {
    const response = await apiClient.get(`/ai/learning/learnings?${buildLearningQuery(filters)}`);
    const data = response.data?.data || {};
    return {
      learnings: data.learnings || [],
      meta: response.data?.meta || { total_count: 0, offset: 0, limit: 50 },
    };
  },

  async reinforceLearning(id: string): Promise<CompoundLearning> {
    const response = await apiClient.post(`/ai/learning/reinforce/${id}`);
    return response.data?.data?.learning;
  },

  async promoteCrossTeam(): Promise<number> {
    const response = await apiClient.post('/ai/learning/promote');
    return response.data?.data?.promoted_count || 0;
  },

  async getEvaluationResults(params?: {
    agent_id?: string;
    from?: string;
    to?: string;
    limit?: number;
  }): Promise<EvaluationResult[]> {
    const response = await apiClient.get('/ai/learning/evaluation_results', { params });
    return response.data?.data?.results || [];
  },

  async getBenchmarks(params?: {
    status?: string;
    agent_id?: string;
    limit?: number;
  }): Promise<PerformanceBenchmark[]> {
    const response = await apiClient.get('/ai/learning/benchmarks', { params });
    return response.data?.data?.benchmarks || [];
  },

  async createBenchmark(data: {
    name: string;
    agent_id?: string;
    workflow_id?: string;
    thresholds?: Record<string, number>;
  }): Promise<PerformanceBenchmark> {
    const response = await apiClient.post('/ai/learning/benchmarks', data);
    return response.data?.data?.benchmark;
  },

  async runBenchmark(id: string): Promise<{
    benchmark: PerformanceBenchmark;
    results: Record<string, unknown>;
  }> {
    const response = await apiClient.post(`/ai/learning/benchmarks/${id}/run`);
    return response.data?.data;
  },
};
