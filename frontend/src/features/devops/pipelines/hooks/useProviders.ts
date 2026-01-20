import { useState, useEffect, useCallback, useRef } from 'react';
import { devopsProvidersApi } from '@/services/devopsPipelinesApi';
import type { DevopsProvider, DevopsProviderFormData, DevopsConnectionTestResponse } from '@/types/devops-pipelines';
import { useNotifications } from '@/shared/hooks/useNotifications';

interface UseProvidersParams {
  provider_type?: string;
  is_active?: boolean;
}

export function useProviders(params: UseProvidersParams = {}) {
  const [providers, setProviders] = useState<DevopsProvider[]>([]);
  const [meta, setMeta] = useState<{
    total: number;
    by_type: Record<string, number>;
  } | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const { showNotification } = useNotifications();
  const hasLoadedRef = useRef(false);
  const currentParamsRef = useRef<string>('');

  const fetchProviders = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const data = await devopsProvidersApi.getAll(params);
      setProviders(data.providers);
      setMeta(data.meta);
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to fetch providers';
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
      fetchProviders();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [params.provider_type, params.is_active]);

  const createProvider = async (data: DevopsProviderFormData) => {
    try {
      const provider = await devopsProvidersApi.create(data);
      showNotification('Provider created successfully', 'success');
      await fetchProviders();
      return provider;
    } catch (err) {
      showNotification('Failed to create provider', 'error');
      return null;
    }
  };

  const updateProvider = async (id: string, data: Partial<DevopsProviderFormData>) => {
    try {
      const provider = await devopsProvidersApi.update(id, data);
      showNotification('Provider updated successfully', 'success');
      await fetchProviders();
      return provider;
    } catch (err) {
      showNotification('Failed to update provider', 'error');
      return null;
    }
  };

  const deleteProvider = async (id: string) => {
    try {
      await devopsProvidersApi.delete(id);
      showNotification('Provider deleted successfully', 'success');
      await fetchProviders();
      return true;
    } catch (err) {
      showNotification('Failed to delete provider', 'error');
      return false;
    }
  };

  const testConnection = async (id: string): Promise<DevopsConnectionTestResponse | null> => {
    try {
      const result = await devopsProvidersApi.testConnection(id);
      if (result.connected) {
        showNotification('Connection successful', 'success');
      } else {
        showNotification(result.message || 'Connection failed', 'error');
      }
      return result;
    } catch (err) {
      showNotification('Failed to test connection', 'error');
      return null;
    }
  };

  const syncRepositories = async (id: string) => {
    try {
      const result = await devopsProvidersApi.syncRepositories(id);
      showNotification(result.message || 'Repositories synced', 'success');
      return result;
    } catch (err) {
      showNotification('Failed to sync repositories', 'error');
      return null;
    }
  };

  return {
    providers,
    meta,
    loading,
    error,
    refresh: fetchProviders,
    createProvider,
    updateProvider,
    deleteProvider,
    testConnection,
    syncRepositories,
  };
}

export function useProvider(id: string | null) {
  const [provider, setProvider] = useState<DevopsProvider | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const { showNotification } = useNotifications();
  const hasLoadedRef = useRef<string | null>(null);

  const fetchProvider = useCallback(async () => {
    if (!id) return;

    try {
      setLoading(true);
      setError(null);
      const data = await devopsProvidersApi.getById(id, true);
      setProvider(data);
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to fetch provider';
      setError(message);
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => {
    if (id && hasLoadedRef.current !== id) {
      hasLoadedRef.current = id;
      fetchProvider();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id]);

  const updateProvider = async (data: Partial<DevopsProviderFormData>) => {
    if (!id) return null;

    try {
      const updated = await devopsProvidersApi.update(id, data);
      showNotification('Provider updated successfully', 'success');
      setProvider(updated);
      return updated;
    } catch (err) {
      showNotification('Failed to update provider', 'error');
      return null;
    }
  };

  return {
    provider,
    loading,
    error,
    refresh: fetchProvider,
    updateProvider,
  };
}
