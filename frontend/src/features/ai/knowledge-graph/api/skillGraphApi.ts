import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { apiClient } from '@/shared/services/apiClient';
import type {
  SkillGraphResult,
  SkillGraphEdge,
  SkillCoverageResult,
  SkillRecommendation,
  AgentSkillContext,
  AutoDetectSuggestion,
  SkillDiscoveryResult,
  SkillEdgeRelation,
} from '../types/skillGraph';

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

export function useAgentSkillContext(agentId: string | undefined) {
  return useQuery({
    queryKey: SG_KEYS.agentContext(agentId || ''),
    queryFn: async (): Promise<AgentSkillContext> => {
      const response = await apiClient.get(`/ai/skill_graph/agent_context/${agentId}`);
      return response.data?.data || response.data;
    },
    enabled: !!agentId,
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

export function useUpdateSkillEdge() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (params: {
      id: string;
      weight?: number;
      confidence?: number;
    }): Promise<SkillGraphEdge> => {
      const { id, ...body } = params;
      const response = await apiClient.patch(`/ai/skill_graph/edges/${id}`, body);
      return response.data?.data || response.data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: SG_KEYS.all });
    },
  });
}

export function useDeleteSkillEdge() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (id: string): Promise<void> => {
      await apiClient.delete(`/ai/skill_graph/edges/${id}`);
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

export function useAutoDetect() {
  return useMutation({
    mutationFn: async (skillId: string): Promise<AutoDetectSuggestion[]> => {
      const response = await apiClient.post('/ai/skill_graph/auto_detect', { skill_id: skillId });
      return response.data?.data?.suggestions || response.data?.suggestions || [];
    },
  });
}

export function useSkillDiscovery() {
  return useMutation({
    mutationFn: async (taskContext: string): Promise<SkillDiscoveryResult> => {
      const response = await apiClient.post('/ai/skill_graph/discover', { task_context: taskContext });
      return response.data?.data || response.data;
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
