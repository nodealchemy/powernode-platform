import { useQuery } from '@tanstack/react-query';
import { apiClient } from '@/shared/services/apiClient';
import type {
  FinOpsOverview,
  CostBreakdown,
  CostTrends,
  CostTrendPoint,
  BudgetUtilization,
  TokenAnalytics,
  OptimizationScore,
  CostBreakdownParams,
  TrendParams,
  BudgetParams,
} from '../types/finops';

const FINOPS_KEYS = {
  all: ['finops'] as const,
  overview: () => [...FINOPS_KEYS.all, 'overview'] as const,
  costBreakdown: (params?: CostBreakdownParams) => [...FINOPS_KEYS.all, 'cost-breakdown', params] as const,
  trends: (params?: TrendParams) => [...FINOPS_KEYS.all, 'trends', params] as const,
  budgetUtilization: (params?: BudgetParams) => [...FINOPS_KEYS.all, 'budget-utilization', params] as const,
  tokenAnalytics: () => [...FINOPS_KEYS.all, 'token-analytics'] as const,
  optimizationScore: () => [...FINOPS_KEYS.all, 'optimization-score'] as const,
};

export function useFinOpsOverview() {
  return useQuery({
    queryKey: FINOPS_KEYS.overview(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/finops');
      return response.data?.data as FinOpsOverview;
    },
  });
}

export function useCostBreakdown(params?: CostBreakdownParams) {
  return useQuery({
    queryKey: FINOPS_KEYS.costBreakdown(params),
    queryFn: async () => {
      const response = await apiClient.get('/ai/finops/cost_breakdown', { params });
      return response.data?.data as CostBreakdown;
    },
  });
}

export function useCostTrends(params?: TrendParams) {
  return useQuery({
    queryKey: FINOPS_KEYS.trends(params),
    queryFn: async () => {
      const response = await apiClient.get('/ai/finops/trends', { params });
      // Backend (finops#trends) returns { trends: { daily_costs: {date->cost}, ... }, time_range };
      // the chart consumes a flat { data: [{ date, cost, ... }], total_cost, avg_daily_cost }.
      // Normalize the daily_costs series into that shape so the contract lives in one place.
      const dailyCosts: Record<string, number> = response.data?.data?.trends?.daily_costs ?? {};
      const data: CostTrendPoint[] = Object.entries(dailyCosts)
        .map(([date, cost]) => ({ date, cost: Number(cost) || 0, tokens: 0, requests: 0 }))
        .sort((a, b) => a.date.localeCompare(b.date));
      const total_cost = data.reduce((sum, point) => sum + point.cost, 0);
      return {
        data,
        period: params?.period ?? '30d',
        total_cost,
        avg_daily_cost: data.length ? total_cost / data.length : 0,
      } satisfies CostTrends;
    },
  });
}

// Raw per-agent budget row as returned by finops#budget_utilization
// (agent_budget_summary). The backend only emits agent-scoped budgets and
// reports cents + a 0–100 utilization percentage (Ai::AgentBudget#utilization_percentage).
interface RawAgentBudget {
  agent_id: string;
  agent_name?: string | null;
  total_budget_cents?: number | null;
  spent_cents?: number | null;
  utilization?: number | null;
  period_type?: string | null;
  exceeded?: boolean | null;
}

export function useBudgetUtilization(params?: BudgetParams) {
  return useQuery({
    queryKey: FINOPS_KEYS.budgetUtilization(params),
    queryFn: async () => {
      const response = await apiClient.get('/ai/finops/budget_utilization', { params });
      // Backend (finops#budget_utilization) returns an OBJECT
      // { budget, enforcement, agent_budgets, time_range } — the budget rows live
      // under `agent_budgets`, not at the top level. Map them into BudgetUtilization[]
      // here so the panel can consume a flat array (contract lives in one place).
      const rawBudgets: RawAgentBudget[] = response.data?.data?.agent_budgets ?? [];
      const mapped: BudgetUtilization[] = rawBudgets.map((b) => ({
        id: b.agent_id,
        name: b.agent_name ?? b.agent_id,
        entity_type: 'agent', // backend only provides agent budgets
        budget_limit: (b.total_budget_cents ?? 0) / 100, // cents → dollars (panel formats dollars)
        current_spend: (b.spent_cents ?? 0) / 100, // cents → dollars
        utilization_pct: b.utilization ?? 0, // already a 0–100 percentage
        period: b.period_type ?? '',
        alert_threshold: 80, // sensible default; backend provides none
        is_over_budget: Boolean(b.exceeded),
        // projected_spend intentionally omitted — backend computes no projections
      }));

      // Client-side filter to the requested entity_type. The backend only has
      // agent budgets, so requesting team/account yields [] (honest empty state).
      const wanted = params?.entity_type;
      return mapped.filter((b) => !wanted || b.entity_type === wanted);
    },
  });
}

export function useTokenAnalytics() {
  return useQuery({
    queryKey: FINOPS_KEYS.tokenAnalytics(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/finops/token_analytics');
      return response.data?.data as TokenAnalytics;
    },
  });
}

export function useOptimizationScore() {
  return useQuery({
    queryKey: FINOPS_KEYS.optimizationScore(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/finops/optimization_score');
      return response.data?.data as OptimizationScore;
    },
  });
}
