import { useState, useEffect, useCallback } from 'react';
import { monitoringApi, MonitoringDashboard } from '@/shared/services/ai/MonitoringApiService';
import { repositoriesApi } from '@/features/devops/git/services/git/repositoriesApi';
import { logger } from '@/shared/utils/logger';
import type { Verdict } from '@/shared/types/platformStatus';

export interface DashboardStats {
  systemHealth: {
    status: Verdict;
    score: number | null;
  };
  overview: {
    totalExecutionsToday: number;
    successRate: number;
    avgResponseTime: number;
    totalCostToday: number;
  };
  agents: {
    total: number;
    active: number;
    paused: number;
    errored: number;
  };
  repositories: number;
  alerts: MonitoringDashboard['alerts'];
}

const DEFAULT_STATS: DashboardStats = {
  // NOT MEASURED until the monitoring fetch answers (E7 review M1). The old
  // default, healthy at 100, is also what a FAILED fetch left on screen, so an
  // unreachable monitoring endpoint read as "All systems operational".
  systemHealth: { status: 'not_measured', score: null },
  overview: { totalExecutionsToday: 0, successRate: 0, avgResponseTime: 0, totalCostToday: 0 },
  agents: { total: 0, active: 0, paused: 0, errored: 0 },
  repositories: 0,
  alerts: [],
};

/**
 * A rejected monitoring request, as operator-facing text. A failed READ is a
 * different fact from `not_measured` (M1 review F4): not_measured means the
 * server answered and had no measurement; this means the dashboard never got
 * an answer. The two must never render the same, so the failure is carried
 * separately instead of being folded into DEFAULT_STATS.
 */
function describeFailure(reason: unknown): string {
  if (reason instanceof Error && reason.message) return reason.message;
  if (typeof reason === 'string' && reason) return reason;
  return 'Monitoring request failed';
}

export function useDashboardStats() {
  const [stats, setStats] = useState<DashboardStats>(DEFAULT_STATS);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  // Set only when the MONITORING fetch rejected. `error` below is set only
  // when both fetches fail, so a monitoring-only failure was invisible.
  const [monitoringError, setMonitoringError] = useState<string | null>(null);

  const fetchStats = useCallback(async () => {
    setLoading(true);
    setError(null);

    const [monitoringResult, reposResult] = await Promise.allSettled([
      monitoringApi.getDashboard(),
      repositoriesApi.getRepositories({ page: 1, per_page: 1 }),
    ]);

    const next: DashboardStats = { ...DEFAULT_STATS };

    if (monitoringResult.status === 'fulfilled') {
      const d = monitoringResult.value;
      next.systemHealth = {
        status: d.system_health.status,
        score: d.system_health.uptime_percentage,
      };
      next.overview = {
        totalExecutionsToday: d.overview.total_executions_today,
        successRate: d.overview.success_rate,
        avgResponseTime: d.overview.avg_response_time,
        totalCostToday: d.overview.total_cost_today,
      };
      next.agents = d.agents;
      next.alerts = d.alerts;
    } else {
      logger.warn('Dashboard monitoring fetch failed', monitoringResult.reason);
    }

    if (reposResult.status === 'fulfilled') {
      next.repositories = reposResult.value.pagination?.total_count ?? 0;
    } else {
      logger.warn('Dashboard repositories fetch failed', reposResult.reason);
    }

    if (monitoringResult.status === 'rejected' && reposResult.status === 'rejected') {
      setError('Failed to load dashboard data');
    }

    setMonitoringError(monitoringResult.status === 'rejected' ? describeFailure(monitoringResult.reason) : null);
    setStats(next);
    setLoading(false);
  }, []);

  useEffect(() => {
    fetchStats();
  }, [fetchStats]);

  return { stats, loading, error, monitoringError, refresh: fetchStats };
}
