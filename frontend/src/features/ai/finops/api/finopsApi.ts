import { useQuery } from '@tanstack/react-query';
import { apiClient } from '@/shared/services/apiClient';
import type { FinOpsOverview, CostTrends, CostTrendPoint, TokenAnalytics, OptimizationScore, CostBreakdownParams, TrendParams } from '../types/finops';

const FINOPS_KEYS = {
  all: ['finops'] as const,
  overview: () => [...FINOPS_KEYS.all, 'overview'] as const,
  costBreakdown: (params?: CostBreakdownParams) => [...FINOPS_KEYS.all, 'cost-breakdown', params] as const,
  trends: (params?: TrendParams) => [...FINOPS_KEYS.all, 'trends', params] as const,
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
