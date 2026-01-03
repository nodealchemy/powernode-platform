import { useState, useEffect, useCallback } from 'react';
import { gitProvidersApi } from '@/features/git-providers/services/gitProvidersApi';
import type {
  GitPipeline,
  PipelineStats,
} from '../types';
import type { GitRepository } from '@/features/git-providers/types';

// Extended pipeline type that includes repository_id for navigation
interface PipelineWithRepo extends GitPipeline {
  repository_id: string;
}

interface CICDDashboardData {
  repositories: GitRepository[];
  recentPipelines: PipelineWithRepo[];
  globalStats: PipelineStats | null;
  loading: boolean;
  error: string | null;
  refresh: () => Promise<void>;
}

export function useCICDDashboard(): CICDDashboardData {
  const [repositories, setRepositories] = useState<GitRepository[]>([]);
  const [recentPipelines, setRecentPipelines] = useState<PipelineWithRepo[]>([]);
  const [globalStats, setGlobalStats] = useState<PipelineStats | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchDashboardData = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);

      // Fetch repositories
      const reposData = await gitProvidersApi.getRepositories({ per_page: 20 });
      const repos = reposData.repositories || [];
      setRepositories(repos);

      if (repos.length === 0) {
        setRecentPipelines([]);
        setGlobalStats(null);
        return;
      }

      // Fetch pipelines from repositories (limit to first 5 for performance)
      const reposToFetch = repos.slice(0, 5);
      const pipelinePromises = reposToFetch.map((repo) =>
        gitProvidersApi
          .getPipelines(repo.id, { per_page: 5 })
          .catch(() => ({ pipelines: [], stats: null, pagination: null }))
      );

      const results = await Promise.all(pipelinePromises);

      // Aggregate pipelines and sort by created_at, add repository_id
      const allPipelines: PipelineWithRepo[] = results.flatMap((r, index) =>
        (r.pipelines || []).map((p) => ({
          ...p,
          repository_id: reposToFetch[index].id,
        }))
      );
      allPipelines.sort(
        (a, b) =>
          new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
      );
      setRecentPipelines(allPipelines.slice(0, 15));

      // Aggregate stats
      const validStats = results.filter((r) => r.stats).map((r) => r.stats!);
      if (validStats.length > 0) {
        const aggregatedStats = validStats.reduce(
          (acc, stats) => ({
            total_runs: acc.total_runs + stats.total_runs,
            success_count: acc.success_count + stats.success_count,
            failed_count: acc.failed_count + stats.failed_count,
            cancelled_count: acc.cancelled_count + stats.cancelled_count,
            success_rate: 0,
            avg_duration_seconds: 0,
            runs_today: acc.runs_today + stats.runs_today,
            runs_this_week: acc.runs_this_week + stats.runs_this_week,
            active_runs: acc.active_runs + stats.active_runs,
          }),
          {
            total_runs: 0,
            success_count: 0,
            failed_count: 0,
            cancelled_count: 0,
            success_rate: 0,
            avg_duration_seconds: 0,
            runs_today: 0,
            runs_this_week: 0,
            active_runs: 0,
          }
        );

        // Calculate success rate
        if (aggregatedStats.total_runs > 0) {
          aggregatedStats.success_rate = Math.round(
            (aggregatedStats.success_count / aggregatedStats.total_runs) * 100
          );
        }

        // Calculate average duration
        const totalDuration = validStats.reduce(
          (sum, s) => sum + s.avg_duration_seconds * s.total_runs,
          0
        );
        if (aggregatedStats.total_runs > 0) {
          aggregatedStats.avg_duration_seconds = Math.round(
            totalDuration / aggregatedStats.total_runs
          );
        }

        setGlobalStats(aggregatedStats);
      } else {
        setGlobalStats(null);
      }
    } catch (err) {
      setError(
        err instanceof Error ? err.message : 'Failed to fetch dashboard data'
      );
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchDashboardData();
  }, [fetchDashboardData]);

  return {
    repositories,
    recentPipelines,
    globalStats,
    loading,
    error,
    refresh: fetchDashboardData,
  };
}

export default useCICDDashboard;
