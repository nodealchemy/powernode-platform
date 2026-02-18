import { useState, useEffect, useCallback } from 'react';
import { gitProvidersApi } from '../services/gitProvidersApi';
import type { GitRunner, GitRunnerDetail, RunnerStats, PaginationInfo } from '../types';

interface UseRunnersParams {
  page?: number;
  perPage?: number;
  search?: string;
  status?: string;
  scope?: string;
  credentialId?: string;
  repositoryId?: string;
}

export function useRunners(params: UseRunnersParams = {}) {
  const [runners, setRunners] = useState<GitRunner[]>([]);
  const [stats, setStats] = useState<RunnerStats | null>(null);
  const [pagination, setPagination] = useState<PaginationInfo | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchRunners = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const data = await gitProvidersApi.getRunners({
        page: params.page,
        per_page: params.perPage,
        search: params.search,
        status: params.status,
        scope: params.scope,
        credential_id: params.credentialId,
        repository_id: params.repositoryId,
      });
      setRunners(data.runners);
      setStats(data.stats);
      setPagination(data.pagination);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch runners');
    } finally {
      setLoading(false);
    }
  }, [
    params.page,
    params.perPage,
    params.search,
    params.status,
    params.scope,
    params.credentialId,
    params.repositoryId,
  ]);

  useEffect(() => {
    fetchRunners();
  }, [fetchRunners]);

  const syncRunners = useCallback(
    async (credentialId?: string, repositoryId?: string) => {
      const result = await gitProvidersApi.syncRunners({
        credential_id: credentialId,
        repository_id: repositoryId,
      });
      await fetchRunners();
      return result;
    },
    [fetchRunners]
  );

  const deleteRunner = useCallback(
    async (id: string) => {
      await gitProvidersApi.deleteRunner(id);
      await fetchRunners();
    },
    [fetchRunners]
  );

  return {
    runners,
    stats,
    pagination,
    loading,
    error,
    refresh: fetchRunners,
    syncRunners,
    deleteRunner,
  };
}

export function useRunner(id: string | null) {
  const [runner, setRunner] = useState<GitRunnerDetail | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchRunner = useCallback(async () => {
    if (!id) return;

    try {
      setLoading(true);
      setError(null);
      const data = await gitProvidersApi.getRunner(id);
      setRunner(data);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch runner');
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => {
    fetchRunner();
  }, [fetchRunner]);

  const updateLabels = useCallback(
    async (labels: string[]) => {
      if (!id) return;
      const updated = await gitProvidersApi.updateRunnerLabels(id, labels);
      setRunner(updated);
      return updated;
    },
    [id]
  );

  return {
    runner,
    loading,
    error,
    refresh: fetchRunner,
    updateLabels,
  };
}
