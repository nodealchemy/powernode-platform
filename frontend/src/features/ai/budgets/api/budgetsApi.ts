import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { apiClient } from '@/shared/services/apiClient';
import { agentsApi } from '@/shared/services/ai/AgentsApiService';
import { autonomyStatsQueryKey } from '@/features/ai/autonomy/api/autonomyApi';
import type { AgentBudget, PaginatedTransactions } from '../types';

/**
 * The ONE client for agent budgets (Ai::AgentBudget), all through
 * /ai/autonomy/budgets: the list, create / edit / delete, allocate_child and
 * per-budget transactions. Every write also invalidates the autonomy stats,
 * because the budget regime is computed from them.
 */
const BUDGET_KEYS = {
  all: ['autonomy', 'budgets'] as const,
  list: () => [...BUDGET_KEYS.all, 'list'] as const,
  transactions: (budgetId: string) => [...BUDGET_KEYS.all, 'transactions', budgetId] as const,
  agentOptions: () => [...BUDGET_KEYS.all, 'agent-options'] as const,
};

export function useAgentBudgets() {
  return useQuery({
    queryKey: BUDGET_KEYS.list(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/autonomy/budgets');
      return (response.data?.data ?? []) as AgentBudget[];
    },
  });
}

export function useBudgetTransactions(budgetId: string, page = 1, perPage = 25) {
  return useQuery({
    queryKey: [...BUDGET_KEYS.transactions(budgetId), page, perPage],
    queryFn: async () => {
      const response = await apiClient.get(`/ai/autonomy/budgets/${budgetId}/transactions`, {
        params: { page, per_page: perPage },
      });
      return (response.data?.data ?? {
        transactions: [],
        pagination: { page: 1, per_page: perPage, total: 0, total_pages: 0 },
      }) as PaginatedTransactions;
    },
    enabled: !!budgetId,
  });
}

/** Agents a budget can be created or allocated for (the account's and global ones). */
export function useBudgetAgentOptions(enabled = true) {
  return useQuery({
    queryKey: BUDGET_KEYS.agentOptions(),
    queryFn: async () => {
      const { items } = await agentsApi.getAgents({ per_page: 100 });
      return (items ?? []).map((agent) => ({ id: agent.id, name: agent.name }));
    },
    enabled,
  });
}

function useInvalidateBudgets() {
  const queryClient = useQueryClient();
  return () => {
    queryClient.invalidateQueries({ queryKey: BUDGET_KEYS.all });
    queryClient.invalidateQueries({ queryKey: autonomyStatsQueryKey() });
  };
}

export function useCreateBudget() {
  const invalidate = useInvalidateBudgets();
  return useMutation({
    mutationFn: async (params: {
      agent_id: string; total_budget_cents: number; period_type?: string; currency?: string;
      period_start?: string; period_end?: string;
    }) => {
      const response = await apiClient.post('/ai/autonomy/budgets', params);
      return response.data?.data;
    },
    onSuccess: invalidate,
  });
}

export function useUpdateBudget() {
  const invalidate = useInvalidateBudgets();
  return useMutation({
    mutationFn: async ({ id, ...params }: {
      id: string; total_budget_cents?: number; period_type?: string; currency?: string; period_end?: string;
    }) => {
      const response = await apiClient.put(`/ai/autonomy/budgets/${id}`, params);
      return response.data?.data;
    },
    onSuccess: invalidate,
  });
}

export function useDeleteBudget() {
  const invalidate = useInvalidateBudgets();
  return useMutation({
    mutationFn: async (id: string) => {
      const response = await apiClient.delete(`/ai/autonomy/budgets/${id}`);
      return response.data?.data;
    },
    onSuccess: invalidate,
  });
}

/** Carves `amountCents` out of a budget's remaining balance into a new child budget for another agent. */
export function useAllocateChildBudget() {
  const invalidate = useInvalidateBudgets();
  return useMutation({
    mutationFn: async ({ budgetId, agentId, amountCents }: { budgetId: string; agentId: string; amountCents: number }) => {
      const response = await apiClient.post(`/ai/autonomy/budgets/${budgetId}/allocate_child`, {
        agent_id: agentId,
        amount_cents: amountCents,
      });
      return response.data?.data as AgentBudget;
    },
    onSuccess: invalidate,
  });
}
