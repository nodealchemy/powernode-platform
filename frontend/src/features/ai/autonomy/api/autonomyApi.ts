import { useQuery } from '@tanstack/react-query';
import { apiClient } from '@/shared/services/apiClient';
import type { TrustScore, AgentLineageNode, AgentBudget, AutonomyStats } from '../types/autonomy';

const AUTONOMY_KEYS = {
  all: ['autonomy'] as const,
  trustScores: () => [...AUTONOMY_KEYS.all, 'trust-scores'] as const,
  trustScore: (agentId: string) => [...AUTONOMY_KEYS.all, 'trust-score', agentId] as const,
  lineage: (agentId: string) => [...AUTONOMY_KEYS.all, 'lineage', agentId] as const,
  budgets: () => [...AUTONOMY_KEYS.all, 'budgets'] as const,
  stats: () => [...AUTONOMY_KEYS.all, 'stats'] as const,
};

export function useTrustScores() {
  return useQuery({
    queryKey: AUTONOMY_KEYS.trustScores(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/autonomy/trust_scores');
      return response.data?.data as TrustScore[];
    },
  });
}

export function useTrustScore(agentId: string) {
  return useQuery({
    queryKey: AUTONOMY_KEYS.trustScore(agentId),
    queryFn: async () => {
      const response = await apiClient.get(`/ai/autonomy/trust_scores/${agentId}`);
      return response.data?.data as TrustScore;
    },
    enabled: !!agentId,
  });
}

export function useAgentLineage(agentId: string) {
  return useQuery({
    queryKey: AUTONOMY_KEYS.lineage(agentId),
    queryFn: async () => {
      const response = await apiClient.get(`/ai/autonomy/lineage/${agentId}`);
      return response.data?.data as AgentLineageNode;
    },
    enabled: !!agentId,
  });
}

export function useAgentBudgets() {
  return useQuery({
    queryKey: AUTONOMY_KEYS.budgets(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/autonomy/budgets');
      return response.data?.data as AgentBudget[];
    },
  });
}

export function useAutonomyStats() {
  return useQuery({
    queryKey: AUTONOMY_KEYS.stats(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/autonomy/stats');
      return response.data?.data as AutonomyStats;
    },
  });
}
