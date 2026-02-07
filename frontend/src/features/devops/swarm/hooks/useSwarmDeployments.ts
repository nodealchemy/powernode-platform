import { useState, useEffect, useCallback } from 'react';
import { swarmApi } from '../services/swarmApi';
import type { SwarmDeploymentSummary, SwarmDeployment, DeploymentFilters, Pagination } from '../types';

interface UseSwarmDeploymentsOptions {
  clusterId: string;
  filters?: DeploymentFilters;
  autoLoad?: boolean;
}

interface UseSwarmDeploymentsResult {
  deployments: SwarmDeploymentSummary[];
  pagination: Pagination | null;
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
  loadMore: () => Promise<void>;
  getDeployment: (deploymentId: string) => Promise<SwarmDeployment | null>;
  cancelDeployment: (deploymentId: string) => Promise<boolean>;
}

export function useSwarmDeployments(options: UseSwarmDeploymentsOptions): UseSwarmDeploymentsResult {
  const { clusterId, filters, autoLoad = true } = options;
  const [deployments, setDeployments] = useState<SwarmDeploymentSummary[]>([]);
  const [pagination, setPagination] = useState<Pagination | null>(null);
  const [isLoading, setIsLoading] = useState(autoLoad);
  const [error, setError] = useState<string | null>(null);
  const [page, setPage] = useState(1);

  const fetchDeployments = useCallback(
    async (pageNum: number, append = false) => {
      if (!clusterId) return;

      setIsLoading(true);
      setError(null);

      const response = await swarmApi.getDeployments(clusterId, pageNum, 20, filters);

      if (response.success && response.data) {
        if (append) {
          setDeployments((prev) => [...prev, ...(response.data!.items ?? [])]);
        } else {
          setDeployments(response.data.items ?? []);
        }
        setPagination(response.data.pagination);
      } else {
        setError(response.error || 'Failed to fetch deployments');
      }

      setIsLoading(false);
    },
    [clusterId, filters]
  );

  useEffect(() => {
    if (autoLoad) {
      setPage(1);
      fetchDeployments(1);
    }
  }, [fetchDeployments, autoLoad]);

  const refetch = useCallback(async () => {
    setPage(1);
    await fetchDeployments(1);
  }, [fetchDeployments]);

  const loadMore = useCallback(async () => {
    if (pagination && page < pagination.total_pages) {
      const nextPage = page + 1;
      setPage(nextPage);
      await fetchDeployments(nextPage, true);
    }
  }, [pagination, page, fetchDeployments]);

  const getDeployment = useCallback(async (deploymentId: string): Promise<SwarmDeployment | null> => {
    const response = await swarmApi.getDeployment(clusterId, deploymentId);
    if (response.success && response.data) {
      return response.data.deployment;
    }
    setError(response.error || 'Failed to fetch deployment');
    return null;
  }, [clusterId]);

  const cancelDeployment = useCallback(async (deploymentId: string): Promise<boolean> => {
    const response = await swarmApi.cancelDeployment(clusterId, deploymentId);
    if (response.success) {
      await refetch();
      return true;
    }
    setError(response.error || 'Failed to cancel deployment');
    return false;
  }, [clusterId, refetch]);

  return {
    deployments,
    pagination,
    isLoading,
    error,
    refetch,
    loadMore,
    getDeployment,
    cancelDeployment,
  };
}
