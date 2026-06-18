import { useQuery } from '@tanstack/react-query';
import { aiOpsApi } from '@/shared/services/ai/AiOpsApiService';
import type {
  AiOpsDashboard,
  RealTimeMetrics,
  AiOpsTrends,
  RecentError,
} from '@/shared/services/ai/AiOpsApiService';

/**
 * React-Query hooks for the AIOps operational dashboard.
 *
 * Mirrors the standard data-fetch pattern (`features/ai/audit/api/auditApi.ts`):
 * a query-key factory plus thin `useQuery` wrappers around the `aiOpsApi`
 * service. The dashboard/real-time queries back the live operational surface;
 * the trends/recent-errors queries target additive endpoints that may not exist
 * on every backend, so they do NOT retry and consumers render them only when
 * data is present.
 */

export const AIOPS_KEYS = {
  all: ['aiops'] as const,
  dashboard: (timeRange?: string) => [...AIOPS_KEYS.all, 'dashboard', timeRange ?? null] as const,
  realTime: () => [...AIOPS_KEYS.all, 'real-time'] as const,
  trends: (timeRange?: string) => [...AIOPS_KEYS.all, 'trends', timeRange ?? null] as const,
  recentErrors: (limit?: number) => [...AIOPS_KEYS.all, 'recent-errors', limit ?? null] as const,
};

/** Main dashboard payload. `select` unwraps the `{ dashboard, time_range }` envelope. */
export function useAiOpsDashboard(timeRange?: string) {
  return useQuery<{ dashboard: AiOpsDashboard }, Error, AiOpsDashboard>({
    queryKey: AIOPS_KEYS.dashboard(timeRange),
    queryFn: () => aiOpsApi.getDashboard(timeRange),
    select: (response) => response.dashboard,
  });
}

/** Real-time ticker. Polls every 15s and is always considered stale. */
export function useAiOpsRealTime() {
  return useQuery<RealTimeMetrics, Error>({
    queryKey: AIOPS_KEYS.realTime(),
    queryFn: () => aiOpsApi.getRealTimeMetrics(),
    refetchInterval: 15000,
    staleTime: 0,
  });
}

/** Hourly trend buckets. Additive endpoint — no retry; absent until backend lands it. */
export function useAiOpsTrends(timeRange?: string, enabled = true) {
  return useQuery<{ trends: AiOpsTrends }, Error, AiOpsTrends>({
    queryKey: AIOPS_KEYS.trends(timeRange),
    queryFn: () => aiOpsApi.getTrends(timeRange),
    select: (response) => response.trends,
    retry: false,
    enabled,
  });
}

/** Recent execution failures. Additive endpoint — no retry; absent until backend lands it. */
export function useAiOpsRecentErrors(limit = 20, enabled = true) {
  return useQuery<{ recent_errors: RecentError[] }, Error, RecentError[]>({
    queryKey: AIOPS_KEYS.recentErrors(limit),
    queryFn: () => aiOpsApi.getRecentErrors(limit),
    select: (response) => response.recent_errors,
    retry: false,
    enabled,
  });
}
