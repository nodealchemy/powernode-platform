import { useState, useEffect, useCallback } from 'react';
import { gitProvidersApi } from '../services/gitProvidersApi';
import { GitRepository, GitRepositoryDetail, PaginationInfo } from '../types';

interface UseRepositoriesParams {
  page?: number;
  perPage?: number;
  search?: string;
  providerId?: string;
  credentialId?: string;
  isPrivate?: boolean;
  webhookConfigured?: boolean;
  language?: string;
  sortBy?: string;
  sortOrder?: 'asc' | 'desc';
}

export function useRepositories(params: UseRepositoriesParams = {}) {
  const [repositories, setRepositories] = useState<GitRepository[]>([]);
  const [pagination, setPagination] = useState<PaginationInfo | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchRepositories = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const data = await gitProvidersApi.getRepositories({
        page: params.page,
        per_page: params.perPage,
        search: params.search,
        provider_id: params.providerId,
        credential_id: params.credentialId,
        is_private: params.isPrivate,
        webhook_configured: params.webhookConfigured,
        language: params.language,
        sort_by: params.sortBy,
        sort_order: params.sortOrder,
      });
      setRepositories(data.repositories);
      setPagination(data.pagination);
    } catch (err) {
      setError(
        err instanceof Error ? err.message : 'Failed to fetch repositories'
      );
    } finally {
      setLoading(false);
    }
  }, [
    params.page,
    params.perPage,
    params.search,
    params.providerId,
    params.credentialId,
    params.isPrivate,
    params.webhookConfigured,
    params.language,
    params.sortBy,
    params.sortOrder,
  ]);

  useEffect(() => {
    fetchRepositories();
  }, [fetchRepositories]);

  const deleteRepository = useCallback(
    async (id: string) => {
      await gitProvidersApi.deleteRepository(id);
      await fetchRepositories();
    },
    [fetchRepositories]
  );

  const configureWebhook = useCallback(
    async (id: string) => {
      const result = await gitProvidersApi.configureWebhook(id);
      await fetchRepositories();
      return result;
    },
    [fetchRepositories]
  );

  const removeWebhook = useCallback(
    async (id: string) => {
      const result = await gitProvidersApi.removeWebhook(id);
      await fetchRepositories();
      return result;
    },
    [fetchRepositories]
  );

  const syncPipelines = useCallback(async (id: string) => {
    return gitProvidersApi.syncPipelines(id);
  }, []);

  return {
    repositories,
    pagination,
    loading,
    error,
    refresh: fetchRepositories,
    deleteRepository,
    configureWebhook,
    removeWebhook,
    syncPipelines,
  };
}

export function useRepository(id: string | null) {
  const [repository, setRepository] = useState<GitRepositoryDetail | null>(
    null
  );
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchRepository = useCallback(async () => {
    if (!id) return;

    try {
      setLoading(true);
      setError(null);
      const data = await gitProvidersApi.getRepository(id);
      setRepository(data);
    } catch (err) {
      setError(
        err instanceof Error ? err.message : 'Failed to fetch repository'
      );
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => {
    fetchRepository();
  }, [fetchRepository]);

  return {
    repository,
    loading,
    error,
    refresh: fetchRepository,
  };
}
