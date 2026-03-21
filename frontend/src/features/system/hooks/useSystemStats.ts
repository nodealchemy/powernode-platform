import { useState, useEffect, useCallback, useRef } from 'react';
import { systemApi } from '@/features/system/services/systemApi';
import type { SystemOverviewStats, SystemRecentActivity } from '@/features/system/types/system.types';

interface UseSystemStatsOptions {
  /** Whether to fetch stats on mount (default: true) */
  autoFetch?: boolean;
  /** Polling interval in milliseconds (0 = no polling, default: 0) */
  pollInterval?: number;
  /** Number of recent activities to fetch (default: 10) */
  activityLimit?: number;
}

interface UseSystemStatsReturn {
  /** Overview statistics */
  stats: SystemOverviewStats | null;
  /** Recent activity items */
  recentActivity: SystemRecentActivity[];
  /** Whether currently loading */
  loading: boolean;
  /** Whether stats have been loaded at least once */
  initialized: boolean;
  /** Any error that occurred */
  error: Error | null;
  /** Manually refresh stats */
  refresh: () => Promise<void>;
  /** Refresh only stats (not activity) */
  refreshStats: () => Promise<void>;
  /** Refresh only activity */
  refreshActivity: () => Promise<void>;
}

/**
 * useSystemStats - Hook for fetching system overview statistics
 *
 * Provides aggregated stats for the System dashboard including
 * counts for nodes, instances, templates, providers, modules, etc.
 *
 * @example
 * ```tsx
 * const { stats, recentActivity, loading, refresh } = useSystemStats({
 *   autoFetch: true,
 *   pollInterval: 60000, // Refresh every minute
 *   activityLimit: 5
 * });
 *
 * if (loading && !stats) return <LoadingSpinner />;
 *
 * return (
 *   <div>
 *     <MetricCard title="Nodes" value={stats?.nodes.total} />
 *     <MetricCard title="Running" value={stats?.instances.running} />
 *   </div>
 * );
 * ```
 */
export function useSystemStats(options: UseSystemStatsOptions = {}): UseSystemStatsReturn {
  const {
    autoFetch = true,
    pollInterval = 0,
    activityLimit = 10
  } = options;

  const [stats, setStats] = useState<SystemOverviewStats | null>(null);
  const [recentActivity, setRecentActivity] = useState<SystemRecentActivity[]>([]);
  const [loading, setLoading] = useState(false);
  const [initialized, setInitialized] = useState(false);
  const [error, setError] = useState<Error | null>(null);

  const intervalRef = useRef<NodeJS.Timeout | null>(null);
  const isMountedRef = useRef(true);

  // Fetch stats only
  const refreshStats = useCallback(async () => {
    if (!isMountedRef.current) return;

    try {
      const newStats = await systemApi.getOverviewStats();
      if (isMountedRef.current) {
        setStats(newStats);
        setError(null);
      }
    } catch (err) {
      if (isMountedRef.current) {
        setError(err instanceof Error ? err : new Error('Failed to fetch stats'));
      }
    }
  }, []);

  // Fetch activity only
  const refreshActivity = useCallback(async () => {
    if (!isMountedRef.current) return;

    try {
      const activity = await systemApi.getRecentActivity(activityLimit);
      if (isMountedRef.current) {
        setRecentActivity(activity);
      }
    } catch (err) {
      // Activity fetch errors are non-critical, don't set error state
      if (process.env.NODE_ENV === 'development') {
        console.warn('Failed to fetch recent activity:', err);
      }
    }
  }, [activityLimit]);

  // Fetch both stats and activity
  const refresh = useCallback(async () => {
    if (!isMountedRef.current) return;

    setLoading(true);

    try {
      await Promise.all([refreshStats(), refreshActivity()]);
    } finally {
      if (isMountedRef.current) {
        setLoading(false);
        setInitialized(true);
      }
    }
  }, [refreshStats, refreshActivity]);

  // Initial fetch
  useEffect(() => {
    isMountedRef.current = true;

    if (autoFetch) {
      refresh();
    }

    return () => {
      isMountedRef.current = false;
    };
  }, [autoFetch, refresh]);

  // Setup polling
  useEffect(() => {
    if (pollInterval > 0) {
      intervalRef.current = setInterval(refresh, pollInterval);

      return () => {
        if (intervalRef.current) {
          clearInterval(intervalRef.current);
          intervalRef.current = null;
        }
      };
    }
  }, [pollInterval, refresh]);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
      }
    };
  }, []);

  return {
    stats,
    recentActivity,
    loading,
    initialized,
    error,
    refresh,
    refreshStats,
    refreshActivity
  };
}

/**
 * useSystemResourceCounts - Simplified hook for just resource counts
 *
 * Lighter weight alternative when you only need counts, not full stats.
 */
export function useSystemResourceCounts() {
  const { stats, loading, error, refresh } = useSystemStats({ autoFetch: true });

  return {
    nodes: stats?.nodes.total ?? 0,
    instances: stats?.instances.total ?? 0,
    templates: stats?.templates.total ?? 0,
    providers: stats?.providers.total ?? 0,
    modules: stats?.modules.total ?? 0,
    operations: stats?.operations.total ?? 0,
    activeOperations: (stats?.operations.pending ?? 0) + (stats?.operations.running ?? 0),
    loading,
    error,
    refresh
  };
}

/**
 * Default empty stats object for loading states
 */
export const emptyStats: SystemOverviewStats = {
  nodes: { total: 0, enabled: 0, disabled: 0 },
  instances: { total: 0, running: 0, stopped: 0, pending: 0 },
  templates: { total: 0, public: 0, private: 0 },
  platforms: { total: 0, enabled: 0 },
  providers: { total: 0, enabled: 0, types: [] },
  regions: { total: 0 },
  modules: { total: 0, enabled: 0, by_variety: { config: 0, instance: 0, subscription: 0 } },
  operations: { total: 0, pending: 0, running: 0, completed: 0, failed: 0 },
  puppet: { modules: 0, resources: 0, assignments: 0 },
  volumes: { total: 0, total_size_gb: 0 },
  networks: { total: 0 }
};
