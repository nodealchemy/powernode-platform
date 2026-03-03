import { useState, useEffect, useCallback } from 'react';
import { monitoringApi, MonitoringDashboard } from '@/shared/services/ai/MonitoringApiService';
import { repositoriesApi } from '@/features/devops/git/services/git/repositoriesApi';
import { logger } from '@/shared/utils/logger';

export interface DashboardStats {
  systemHealth: {
    status: 'healthy' | 'degraded' | 'down';
    score: number;
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
  workflows: {
    total: number;
    active: number;
    running: number;
    completedToday: number;
    failedToday: number;
  };
  repositories: number;
  alerts: MonitoringDashboard['alerts'];
}

const DEFAULT_STATS: DashboardStats = {
  systemHealth: { status: 'healthy', score: 100 },
  overview: { totalExecutionsToday: 0, successRate: 0, avgResponseTime: 0, totalCostToday: 0 },
  agents: { total: 0, active: 0, paused: 0, errored: 0 },
  workflows: { total: 0, active: 0, running: 0, completedToday: 0, failedToday: 0 },
  repositories: 0,
  alerts: [],
};

export function useDashboardStats() {
  const [stats, setStats] = useState<DashboardStats>(DEFAULT_STATS);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

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
      next.workflows = {
        total: d.workflows.total,
        active: d.workflows.active,
        running: d.workflows.running,
        completedToday: d.workflows.completed_today,
        failedToday: d.workflows.failed_today,
      };
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

    setStats(next);
    setLoading(false);
  }, []);

  useEffect(() => {
    fetchStats();
  }, [fetchStats]);

  return { stats, loading, error, refresh: fetchStats };
}
