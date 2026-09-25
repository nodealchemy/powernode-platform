import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { apiClient } from '@/shared/services/apiClient';
import type { SkillGraphResult, SkillGraphEdge, SkillCoverageResult, SkillRecommendation, SkillEdgeRelation } from '@/features/ai/knowledge-graph/types/skillGraph';
import type {
  ResearchRequest,
  ProposalsListResponse,
  ProposalResponse,
  ResearchResponse,
  ConflictsListResponse,
  HealthResponse,
  SkillMetricsResponse,
  VersionsListResponse,
  OptimizationResponse,
} from '@/features/ai/skills/types/lifecycle';

// The one client for the /ai/skill_graph endpoint family: the graph itself
// (subgraph, edges, coverage, discovery) as react-query hooks, and the skill
// lifecycle (research, proposals, conflicts, health, evolution, optimization)
// as skillGraphApi.

const SG_KEYS = {
  all: ['skill-graph'] as const,
  graph: () => [...SG_KEYS.all, 'subgraph'] as const,
  coverage: (teamId: string) => [...SG_KEYS.all, 'coverage', teamId] as const,
  agentContext: (agentId: string) => [...SG_KEYS.all, 'agent-context', agentId] as const,
};

export function useSkillGraph() {
  return useQuery({
    queryKey: SG_KEYS.graph(),
    queryFn: async (): Promise<SkillGraphResult> => {
      const response = await apiClient.get('/ai/skill_graph/subgraph');
      const payload = response.data?.data || response.data;
      return {
        nodes: payload?.nodes || [],
        edges: payload?.edges || [],
      };
    },
  });
}

export function useSkillCoverage(teamId: string | undefined) {
  return useQuery({
    queryKey: SG_KEYS.coverage(teamId || ''),
    queryFn: async (): Promise<SkillCoverageResult> => {
      const response = await apiClient.get(`/ai/skill_graph/team_coverage/${teamId}`);
      return response.data?.data || response.data;
    },
    enabled: !!teamId,
  });
}

export function useCreateSkillEdge() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (params: {
      source_skill_id: string;
      target_skill_id: string;
      relation_type: SkillEdgeRelation;
      weight?: number;
      confidence?: number;
    }): Promise<SkillGraphEdge> => {
      const response = await apiClient.post('/ai/skill_graph/edges', params);
      return response.data?.data || response.data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: SG_KEYS.all });
    },
  });
}

export function useSyncSkills() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (): Promise<{ synced_count: number }> => {
      const response = await apiClient.post('/ai/skill_graph/sync');
      return response.data?.data || response.data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: SG_KEYS.all });
    },
  });
}

export function useSkillRecommendations() {
  return useMutation({
    mutationFn: async ({ teamId, taskContext }: { teamId: string; taskContext?: string }): Promise<SkillRecommendation[]> => {
      const response = await apiClient.post(`/ai/skill_graph/suggest_agents/${teamId}`, {
        task_context: taskContext || 'Fill uncovered skill gaps for this team',
      });
      return response.data?.data?.recommendations || response.data?.recommendations || [];
    },
  });
}

const handleApiError = (error: unknown, defaultMessage: string): string => {
  if (error && typeof error === 'object' && 'response' in error) {
    return (error as { response?: { data?: { error?: string } } }).response?.data?.error || defaultMessage;
  }
  return defaultMessage;
};

export const skillGraphApi = {
  // === Research ===

  async startResearch(request: ResearchRequest): Promise<ResearchResponse> {
    try {
      const response = await apiClient.post('/ai/skill_graph/research', request);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to start research') };
    }
  },

  // === Proposals ===

  async getProposals(page = 1, status?: string): Promise<ProposalsListResponse> {
    try {
      const params = new URLSearchParams({ page: page.toString(), per_page: '20' });
      if (status) params.append('status', status);
      const response = await apiClient.get(`/ai/skill_graph/proposals?${params}`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch proposals') };
    }
  },

  async getProposal(id: string): Promise<ProposalResponse> {
    try {
      const response = await apiClient.get(`/ai/skill_graph/proposals/${id}`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch proposal') };
    }
  },

  async createProposal(data: Record<string, unknown>): Promise<ProposalResponse> {
    try {
      const response = await apiClient.post('/ai/skill_graph/proposals', { proposal: data });
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to create proposal') };
    }
  },

  async submitProposal(id: string): Promise<ProposalResponse> {
    try {
      const response = await apiClient.post(`/ai/skill_graph/proposals/${id}/submit`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to submit proposal') };
    }
  },

  async approveProposal(id: string): Promise<ProposalResponse> {
    try {
      const response = await apiClient.post(`/ai/skill_graph/proposals/${id}/approve`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to approve proposal') };
    }
  },

  async rejectProposal(id: string, reason: string): Promise<ProposalResponse> {
    try {
      const response = await apiClient.post(`/ai/skill_graph/proposals/${id}/reject`, { reason });
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to reject proposal') };
    }
  },

  async createSkillFromProposal(id: string): Promise<ProposalResponse> {
    try {
      const response = await apiClient.post(`/ai/skill_graph/proposals/${id}/create_skill`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to create skill from proposal') };
    }
  },

  // === Conflicts ===

  async getConflicts(): Promise<ConflictsListResponse> {
    try {
      const response = await apiClient.get('/ai/skill_graph/conflicts');
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch conflicts') };
    }
  },

  async resolveConflict(id: string, strategy?: string): Promise<{ success: boolean; error?: string }> {
    try {
      const response = await apiClient.post(`/ai/skill_graph/conflicts/${id}/resolve`, { strategy });
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to resolve conflict') };
    }
  },

  async dismissConflict(id: string): Promise<{ success: boolean; error?: string }> {
    try {
      const response = await apiClient.post(`/ai/skill_graph/conflicts/${id}/dismiss`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to dismiss conflict') };
    }
  },

  async scanConflicts(): Promise<{ success: boolean; data?: { summary: Record<string, number> }; error?: string }> {
    try {
      const response = await apiClient.post('/ai/skill_graph/scan');
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to scan for conflicts') };
    }
  },

  // === Health ===

  async getHealth(): Promise<HealthResponse> {
    try {
      const response = await apiClient.get('/ai/skill_graph/health');
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch health score') };
    }
  },

  // === Evolution ===

  async getSkillMetrics(skillId: string): Promise<SkillMetricsResponse> {
    try {
      const response = await apiClient.get(`/ai/skill_graph/skills/${skillId}/metrics`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch skill metrics') };
    }
  },

  async getVersionHistory(skillId: string): Promise<VersionsListResponse> {
    try {
      const response = await apiClient.get(`/ai/skill_graph/skills/${skillId}/versions`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch version history') };
    }
  },

  async proposeEvolution(skillId: string): Promise<{ success: boolean; data?: { version: Record<string, unknown> }; error?: string }> {
    try {
      const response = await apiClient.post(`/ai/skill_graph/skills/${skillId}/evolve`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to propose evolution') };
    }
  },

  async activateVersion(versionId: string): Promise<{ success: boolean; error?: string }> {
    try {
      const response = await apiClient.post(`/ai/skill_graph/versions/${versionId}/activate`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to activate version') };
    }
  },

  async startAbTest(skillId: string, variantVersionId: string, trafficPct: number): Promise<{ success: boolean; error?: string }> {
    try {
      const response = await apiClient.post(`/ai/skill_graph/skills/${skillId}/ab_test`, {
        variant_version_id: variantVersionId,
        traffic_pct: trafficPct,
      });
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to start A/B test') };
    }
  },

  async endAbTest(skillId: string): Promise<{ success: boolean; error?: string }> {
    try {
      const response = await apiClient.post(`/ai/skill_graph/skills/${skillId}/end_ab_test`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to end A/B test') };
    }
  },

  async recordOutcome(skillId: string, successful: boolean): Promise<{ success: boolean; error?: string }> {
    try {
      const response = await apiClient.post('/ai/skill_graph/record_outcome', {
        skill_id: skillId,
        successful,
      });
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to record outcome') };
    }
  },

  // === Optimization ===

  async runOptimization(operation = 'full'): Promise<OptimizationResponse> {
    try {
      const response = await apiClient.post('/ai/skill_graph/optimize', { operation });
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to run optimization') };
    }
  },
};
