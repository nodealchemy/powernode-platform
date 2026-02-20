import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { apiClient } from '@/shared/services/apiClient';
import type {
  TrustScore,
  AgentLineageNode,
  AgentBudget,
  AutonomyStats,
  CircuitBreaker,
  CapabilityMatrix,
  AgentCapabilities,
  ApprovalRequest,
  BehavioralFingerprint,
  ShadowExecution,
  TelemetryEvent,
  DelegationPolicy,
  BudgetCheckResponse,
  BudgetAlertItem,
  PaginatedTransactions,
} from '../types/autonomy';

const AUTONOMY_KEYS = {
  all: ['autonomy'] as const,
  trustScores: () => [...AUTONOMY_KEYS.all, 'trust-scores'] as const,
  trustScore: (agentId: string) => [...AUTONOMY_KEYS.all, 'trust-score', agentId] as const,
  lineage: (agentId: string) => [...AUTONOMY_KEYS.all, 'lineage', agentId] as const,
  lineageForest: () => [...AUTONOMY_KEYS.all, 'lineage-forest'] as const,
  budgets: () => [...AUTONOMY_KEYS.all, 'budgets'] as const,
  stats: () => [...AUTONOMY_KEYS.all, 'stats'] as const,
  capabilityMatrix: () => [...AUTONOMY_KEYS.all, 'capability-matrix'] as const,
  agentCapabilities: (agentId: string) => [...AUTONOMY_KEYS.all, 'capabilities', agentId] as const,
  circuitBreakers: () => [...AUTONOMY_KEYS.all, 'circuit-breakers'] as const,
  agentCircuitBreakers: (agentId: string) => [...AUTONOMY_KEYS.all, 'circuit-breakers', agentId] as const,
  approvals: () => [...AUTONOMY_KEYS.all, 'approvals'] as const,
  shadowExecutions: () => [...AUTONOMY_KEYS.all, 'shadow-executions'] as const,
  agentShadowExecutions: (agentId: string) => [...AUTONOMY_KEYS.all, 'shadow-executions', agentId] as const,
  telemetry: () => [...AUTONOMY_KEYS.all, 'telemetry'] as const,
  agentTelemetry: (agentId: string) => [...AUTONOMY_KEYS.all, 'telemetry', agentId] as const,
  delegationPolicies: () => [...AUTONOMY_KEYS.all, 'delegation-policies'] as const,
  agentDelegationPolicy: (agentId: string) => [...AUTONOMY_KEYS.all, 'delegation-policy', agentId] as const,
  behavioralFingerprints: (agentId: string) => [...AUTONOMY_KEYS.all, 'fingerprints', agentId] as const,
  budgetTransactions: (budgetId: string) => [...AUTONOMY_KEYS.all, 'budget-transactions', budgetId] as const,
  budgetCheck: (budgetId: string) => [...AUTONOMY_KEYS.all, 'budget-check', budgetId] as const,
  budgetAlerts: () => [...AUTONOMY_KEYS.all, 'budget-alerts'] as const,
  pricing: () => [...AUTONOMY_KEYS.all, 'pricing'] as const,
};

// ===== Read Queries =====

export function useTrustScores() {
  return useQuery({
    queryKey: AUTONOMY_KEYS.trustScores(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/autonomy/trust_scores');
      return (response.data?.data ?? []) as TrustScore[];
    },
  });
}

export function useTrustScore(agentId: string) {
  return useQuery({
    queryKey: AUTONOMY_KEYS.trustScore(agentId),
    queryFn: async () => {
      const response = await apiClient.get(`/ai/autonomy/trust_scores/${agentId}`);
      return (response.data?.data ?? null) as TrustScore;
    },
    enabled: !!agentId,
  });
}

export function useAgentLineage(agentId: string) {
  return useQuery({
    queryKey: AUTONOMY_KEYS.lineage(agentId),
    queryFn: async () => {
      const response = await apiClient.get(`/ai/autonomy/lineage/${agentId}`);
      return (response.data?.data ?? null) as AgentLineageNode;
    },
    enabled: !!agentId,
  });
}

export function useAgentLineageForest() {
  return useQuery({
    queryKey: AUTONOMY_KEYS.lineageForest(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/autonomy/lineage');
      return (response.data?.data ?? { trees: [], orphans: [] }) as {
        trees: AgentLineageNode[];
        orphans: AgentLineageNode[];
      };
    },
  });
}

export function useAgentBudgets() {
  return useQuery({
    queryKey: AUTONOMY_KEYS.budgets(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/autonomy/budgets');
      return (response.data?.data ?? []) as AgentBudget[];
    },
  });
}

export function useAutonomyStats() {
  return useQuery({
    queryKey: AUTONOMY_KEYS.stats(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/autonomy/stats');
      return (response.data?.data ?? {}) as AutonomyStats;
    },
  });
}

export function useCapabilityMatrix() {
  return useQuery({
    queryKey: AUTONOMY_KEYS.capabilityMatrix(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/autonomy/capability_matrix');
      return (response.data?.data ?? {}) as CapabilityMatrix;
    },
  });
}

export function useAgentCapabilities(agentId: string) {
  return useQuery({
    queryKey: AUTONOMY_KEYS.agentCapabilities(agentId),
    queryFn: async () => {
      const response = await apiClient.get(`/ai/autonomy/capability_matrix/${agentId}`);
      return (response.data?.data ?? null) as AgentCapabilities;
    },
    enabled: !!agentId,
  });
}

export function useCircuitBreakers() {
  return useQuery({
    queryKey: AUTONOMY_KEYS.circuitBreakers(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/autonomy/circuit_breakers');
      return (response.data?.data ?? []) as CircuitBreaker[];
    },
  });
}

export function useAgentCircuitBreakers(agentId: string) {
  return useQuery({
    queryKey: AUTONOMY_KEYS.agentCircuitBreakers(agentId),
    queryFn: async () => {
      const response = await apiClient.get(`/ai/autonomy/circuit_breakers/${agentId}`);
      return (response.data?.data ?? []) as CircuitBreaker[];
    },
    enabled: !!agentId,
  });
}

export function useApprovalQueue() {
  return useQuery({
    queryKey: AUTONOMY_KEYS.approvals(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/autonomy/approvals');
      return (response.data?.data ?? []) as ApprovalRequest[];
    },
  });
}

export function useShadowExecutions() {
  return useQuery({
    queryKey: AUTONOMY_KEYS.shadowExecutions(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/autonomy/shadow_executions');
      return (response.data?.data ?? []) as ShadowExecution[];
    },
  });
}

export function useAgentShadowExecutions(agentId: string) {
  return useQuery({
    queryKey: AUTONOMY_KEYS.agentShadowExecutions(agentId),
    queryFn: async () => {
      const response = await apiClient.get(`/ai/autonomy/shadow_executions/${agentId}`);
      return (response.data?.data ?? []) as ShadowExecution[];
    },
    enabled: !!agentId,
  });
}

export function useTelemetryEvents() {
  return useQuery({
    queryKey: AUTONOMY_KEYS.telemetry(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/autonomy/telemetry');
      return (response.data?.data ?? []) as TelemetryEvent[];
    },
  });
}

export function useAgentTelemetry(agentId: string) {
  return useQuery({
    queryKey: AUTONOMY_KEYS.agentTelemetry(agentId),
    queryFn: async () => {
      const response = await apiClient.get(`/ai/autonomy/telemetry/${agentId}`);
      return (response.data?.data ?? []) as TelemetryEvent[];
    },
    enabled: !!agentId,
  });
}

export function useDelegationPolicies() {
  return useQuery({
    queryKey: AUTONOMY_KEYS.delegationPolicies(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/autonomy/delegation_policies');
      return (response.data?.data ?? []) as DelegationPolicy[];
    },
  });
}

export function useAgentDelegationPolicy(agentId: string) {
  return useQuery({
    queryKey: AUTONOMY_KEYS.agentDelegationPolicy(agentId),
    queryFn: async () => {
      const response = await apiClient.get(`/ai/autonomy/delegation_policies/${agentId}`);
      return (response.data?.data ?? null) as DelegationPolicy;
    },
    enabled: !!agentId,
  });
}

export function useBehavioralFingerprints(agentId: string) {
  return useQuery({
    queryKey: AUTONOMY_KEYS.behavioralFingerprints(agentId),
    queryFn: async () => {
      const response = await apiClient.get(`/ai/autonomy/behavioral_fingerprints/${agentId}`);
      return (response.data?.data ?? []) as BehavioralFingerprint[];
    },
    enabled: !!agentId,
  });
}

export function useBudgetTransactions(budgetId: string, page = 1, perPage = 25) {
  return useQuery({
    queryKey: [...AUTONOMY_KEYS.budgetTransactions(budgetId), page, perPage],
    queryFn: async () => {
      const response = await apiClient.get(`/ai/autonomy/budgets/${budgetId}/transactions`, {
        params: { page, per_page: perPage },
      });
      return (response.data?.data ?? { transactions: [], pagination: { page: 1, per_page: perPage, total: 0, total_pages: 0 } }) as PaginatedTransactions;
    },
    enabled: !!budgetId,
  });
}

export function useBudgetCheck(budgetId: string) {
  return useQuery({
    queryKey: AUTONOMY_KEYS.budgetCheck(budgetId),
    queryFn: async () => {
      const response = await apiClient.get(`/ai/autonomy/budgets/${budgetId}/check`);
      return (response.data?.data ?? null) as BudgetCheckResponse;
    },
    enabled: !!budgetId,
  });
}

export function useBudgetAlerts() {
  return useQuery({
    queryKey: AUTONOMY_KEYS.budgetAlerts(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/autonomy/budgets/alerts');
      return (response.data?.data ?? []) as BudgetAlertItem[];
    },
  });
}

// ===== Write Mutations =====

export function useEvaluateTrustScore() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (agentId: string) => {
      const response = await apiClient.post(`/ai/autonomy/trust_scores/${agentId}/evaluate`);
      return response.data?.data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: AUTONOMY_KEYS.trustScores() });
      queryClient.invalidateQueries({ queryKey: AUTONOMY_KEYS.stats() });
    },
  });
}

export function useOverrideTrustScore() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ agentId, tier, reason }: { agentId: string; tier: string; reason: string }) => {
      const response = await apiClient.put(`/ai/autonomy/trust_scores/${agentId}/override`, { tier, reason });
      return response.data?.data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: AUTONOMY_KEYS.trustScores() });
      queryClient.invalidateQueries({ queryKey: AUTONOMY_KEYS.stats() });
    },
  });
}

export function useEmergencyDemote() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ agentId, reason }: { agentId: string; reason: string }) => {
      const response = await apiClient.post(`/ai/autonomy/trust_scores/${agentId}/emergency_demote`, { reason });
      return response.data?.data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: AUTONOMY_KEYS.trustScores() });
      queryClient.invalidateQueries({ queryKey: AUTONOMY_KEYS.stats() });
    },
  });
}

export function useCreateBudget() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (params: { agent_id: string; total_budget_cents: number; period_type?: string; currency?: string; period_start?: string; period_end?: string }) => {
      const response = await apiClient.post('/ai/autonomy/budgets', params);
      return response.data?.data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: AUTONOMY_KEYS.budgets() });
      queryClient.invalidateQueries({ queryKey: AUTONOMY_KEYS.stats() });
    },
  });
}

export function useUpdateBudget() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, ...params }: { id: string; total_budget_cents?: number; period_type?: string; currency?: string; period_end?: string }) => {
      const response = await apiClient.put(`/ai/autonomy/budgets/${id}`, params);
      return response.data?.data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: AUTONOMY_KEYS.budgets() });
      queryClient.invalidateQueries({ queryKey: AUTONOMY_KEYS.stats() });
    },
  });
}

export function useDeleteBudget() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (id: string) => {
      const response = await apiClient.delete(`/ai/autonomy/budgets/${id}`);
      return response.data?.data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: AUTONOMY_KEYS.budgets() });
      queryClient.invalidateQueries({ queryKey: AUTONOMY_KEYS.stats() });
    },
  });
}

export function useAllocateChildBudget() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ budgetId, agentId, amountCents }: { budgetId: string; agentId: string; amountCents: number }) => {
      const response = await apiClient.post(`/ai/autonomy/budgets/${budgetId}/allocate_child`, {
        agent_id: agentId,
        amount_cents: amountCents,
      });
      return response.data?.data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: AUTONOMY_KEYS.budgets() });
      queryClient.invalidateQueries({ queryKey: AUTONOMY_KEYS.stats() });
    },
  });
}

export function useApproveAction() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, comments }: { id: string; comments?: string }) => {
      const response = await apiClient.post(`/ai/autonomy/approvals/${id}/approve`, { comments });
      return response.data?.data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: AUTONOMY_KEYS.approvals() });
    },
  });
}

export function useRejectAction() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, comments }: { id: string; comments?: string }) => {
      const response = await apiClient.post(`/ai/autonomy/approvals/${id}/reject`, { comments });
      return response.data?.data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: AUTONOMY_KEYS.approvals() });
    },
  });
}

export function useResetCircuitBreaker() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (id: string) => {
      const response = await apiClient.post(`/ai/autonomy/circuit_breakers/${id}/reset`);
      return response.data?.data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: AUTONOMY_KEYS.circuitBreakers() });
    },
  });
}

export function useCreateDelegationPolicy() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (params: Partial<DelegationPolicy> & { agent_id: string }) => {
      const response = await apiClient.post('/ai/autonomy/delegation_policies', params);
      return response.data?.data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: AUTONOMY_KEYS.delegationPolicies() });
    },
  });
}

export function useUpdateDelegationPolicy() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, ...params }: Partial<DelegationPolicy> & { id: string }) => {
      const response = await apiClient.put(`/ai/autonomy/delegation_policies/${id}`, params);
      return response.data?.data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: AUTONOMY_KEYS.delegationPolicies() });
    },
  });
}

export function useDeleteDelegationPolicy() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (id: string) => {
      const response = await apiClient.delete(`/ai/autonomy/delegation_policies/${id}`);
      return response.data?.data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: AUTONOMY_KEYS.delegationPolicies() });
    },
  });
}
