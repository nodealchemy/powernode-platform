import { useState, useEffect, useCallback } from 'react';
import { swarmApi } from '../services/swarmApi';
import type {
  SwarmClusterSummary,
  SwarmCluster,
  ClusterFormData,
  ClusterFilters,
  Pagination,
} from '../types';

interface UseSwarmClustersOptions {
  filters?: ClusterFilters;
  autoLoad?: boolean;
}

interface UseSwarmClustersResult {
  clusters: SwarmClusterSummary[];
  pagination: Pagination | null;
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
  createCluster: (data: ClusterFormData) => Promise<SwarmCluster | null>;
  updateCluster: (id: string, data: Partial<ClusterFormData>) => Promise<SwarmCluster | null>;
  deleteCluster: (id: string) => Promise<boolean>;
  testConnection: (id: string) => Promise<{ connected: boolean; message: string } | null>;
  syncCluster: (id: string) => Promise<boolean>;
}

export function useSwarmClusters(options: UseSwarmClustersOptions = {}): UseSwarmClustersResult {
  const { filters, autoLoad = true } = options;
  const [clusters, setClusters] = useState<SwarmClusterSummary[]>([]);
  const [pagination, setPagination] = useState<Pagination | null>(null);
  const [isLoading, setIsLoading] = useState(autoLoad);
  const [error, setError] = useState<string | null>(null);

  const fetchClusters = useCallback(async () => {
    setIsLoading(true);
    setError(null);

    const response = await swarmApi.getClusters(1, 100, filters);

    if (response.success && response.data) {
      setClusters(response.data.items ?? []);
      setPagination(response.data.pagination);
    } else {
      setError(response.error || 'Failed to fetch clusters');
    }

    setIsLoading(false);
  }, [filters]);

  useEffect(() => {
    if (autoLoad) {
      fetchClusters();
    }
  }, [fetchClusters, autoLoad]);

  const createCluster = useCallback(async (data: ClusterFormData): Promise<SwarmCluster | null> => {
    const response = await swarmApi.createCluster(data);
    if (response.success && response.data) {
      await fetchClusters();
      return response.data.cluster;
    }
    setError(response.error || 'Failed to create cluster');
    return null;
  }, [fetchClusters]);

  const updateCluster = useCallback(async (id: string, data: Partial<ClusterFormData>): Promise<SwarmCluster | null> => {
    const response = await swarmApi.updateCluster(id, data);
    if (response.success && response.data) {
      await fetchClusters();
      return response.data.cluster;
    }
    setError(response.error || 'Failed to update cluster');
    return null;
  }, [fetchClusters]);

  const deleteCluster = useCallback(async (id: string): Promise<boolean> => {
    const response = await swarmApi.deleteCluster(id);
    if (response.success) {
      await fetchClusters();
      return true;
    }
    setError(response.error || 'Failed to delete cluster');
    return false;
  }, [fetchClusters]);

  const testConnection = useCallback(async (id: string) => {
    const response = await swarmApi.testClusterConnection(id);
    if (response.success && response.data) {
      return { connected: response.data.connected, message: response.data.message };
    }
    setError(response.error || 'Failed to test connection');
    return null;
  }, []);

  const syncCluster = useCallback(async (id: string): Promise<boolean> => {
    const response = await swarmApi.syncCluster(id);
    if (response.success) {
      await fetchClusters();
      return true;
    }
    setError(response.error || 'Failed to sync cluster');
    return false;
  }, [fetchClusters]);

  return {
    clusters,
    pagination,
    isLoading,
    error,
    refetch: fetchClusters,
    createCluster,
    updateCluster,
    deleteCluster,
    testConnection,
    syncCluster,
  };
}
