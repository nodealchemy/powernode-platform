import { useState, useEffect, useCallback, useRef } from 'react';
import { devopsRepositoriesApi } from '@/services/devopsPipelinesApi';
import type { DevopsRepository, DevopsRepositoryFormData } from '@/types/devops-pipelines';
import { useNotifications } from '@/shared/hooks/useNotifications';

interface UseRepositoriesParams {
  provider_id?: string;
  is_active?: boolean;
}

export function useRepositories(params: UseRepositoriesParams = {}) {
  const [repositories, setRepositories] = useState<DevopsRepository[]>([]);
  const [meta, setMeta] = useState<{
    total: number;
    active_count: number;
    by_provider: Record<string, number>;
  } | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const { showNotification } = useNotifications();
  const hasLoadedRef = useRef(false);
  const currentParamsRef = useRef<string>('');

  const fetchRepositories = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const data = await devopsRepositoriesApi.getAll(params);
      setRepositories(data.repositories);
      setMeta(data.meta);
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to fetch repositories';
      setError(message);
    } finally {
      setLoading(false);
    }
  }, [params]);

  useEffect(() => {
    const paramsKey = JSON.stringify(params);
    if (!hasLoadedRef.current || currentParamsRef.current !== paramsKey) {
      hasLoadedRef.current = true;
      currentParamsRef.current = paramsKey;
      fetchRepositories();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [params.provider_id, params.is_active]);

  const createRepository = async (data: DevopsRepositoryFormData) => {
    try {
      const repository = await devopsRepositoriesApi.create(data);
      showNotification('Repository created successfully', 'success');
      await fetchRepositories();
      return repository;
    } catch (err) {
      showNotification('Failed to create repository', 'error');
      return null;
    }
  };

  const updateRepository = async (id: string, data: Partial<DevopsRepositoryFormData>) => {
    try {
      const repository = await devopsRepositoriesApi.update(id, data);
      showNotification('Repository updated successfully', 'success');
      await fetchRepositories();
      return repository;
    } catch (err) {
      showNotification('Failed to update repository', 'error');
      return null;
    }
  };

  const deleteRepository = async (id: string) => {
    try {
      await devopsRepositoriesApi.delete(id);
      showNotification('Repository deleted successfully', 'success');
      await fetchRepositories();
      return true;
    } catch (err) {
      showNotification('Failed to delete repository', 'error');
      return false;
    }
  };

  const syncRepository = async (id: string) => {
    try {
      const result = await devopsRepositoriesApi.sync(id);
      showNotification(result.message || 'Repository synced', 'success');
      await fetchRepositories();
      return result;
    } catch (err) {
      showNotification('Failed to sync repository', 'error');
      return null;
    }
  };

  const attachPipeline = async (id: string, pipelineId: string, overrides?: Record<string, unknown>) => {
    try {
      const repository = await devopsRepositoriesApi.attachPipeline(id, pipelineId, overrides);
      showNotification('Pipeline attached successfully', 'success');
      await fetchRepositories();
      return repository;
    } catch (err) {
      showNotification('Failed to attach pipeline', 'error');
      return null;
    }
  };

  const detachPipeline = async (id: string, pipelineId: string) => {
    try {
      const repository = await devopsRepositoriesApi.detachPipeline(id, pipelineId);
      showNotification('Pipeline detached successfully', 'success');
      await fetchRepositories();
      return repository;
    } catch (err) {
      showNotification('Failed to detach pipeline', 'error');
      return null;
    }
  };

  return {
    repositories,
    meta,
    loading,
    error,
    refresh: fetchRepositories,
    createRepository,
    updateRepository,
    deleteRepository,
    syncRepository,
    attachPipeline,
    detachPipeline,
  };
}

export function useRepository(id: string | null) {
  const [repository, setRepository] = useState<DevopsRepository | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const { showNotification } = useNotifications();
  const hasLoadedRef = useRef<string | null>(null);

  const fetchRepository = useCallback(async () => {
    if (!id) return;

    try {
      setLoading(true);
      setError(null);
      const data = await devopsRepositoriesApi.getById(id, true);
      setRepository(data);
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to fetch repository';
      setError(message);
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => {
    if (id && hasLoadedRef.current !== id) {
      hasLoadedRef.current = id;
      fetchRepository();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id]);

  const updateRepository = async (data: Partial<DevopsRepositoryFormData>) => {
    if (!id) return null;

    try {
      const updated = await devopsRepositoriesApi.update(id, data);
      showNotification('Repository updated successfully', 'success');
      setRepository(updated);
      return updated;
    } catch (err) {
      showNotification('Failed to update repository', 'error');
      return null;
    }
  };

  return {
    repository,
    loading,
    error,
    refresh: fetchRepository,
    updateRepository,
  };
}
