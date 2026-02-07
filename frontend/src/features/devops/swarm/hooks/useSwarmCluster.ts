import { useState, useEffect, useCallback } from 'react';
import { swarmApi } from '../services/swarmApi';
import type { SwarmCluster } from '../types';

interface UseSwarmClusterOptions {
  clusterId: string;
  autoLoad?: boolean;
}

interface UseSwarmClusterResult {
  cluster: SwarmCluster | null;
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

export function useSwarmCluster(options: UseSwarmClusterOptions): UseSwarmClusterResult {
  const { clusterId, autoLoad = true } = options;
  const [cluster, setCluster] = useState<SwarmCluster | null>(null);
  const [isLoading, setIsLoading] = useState(autoLoad);
  const [error, setError] = useState<string | null>(null);

  const fetchCluster = useCallback(async () => {
    if (!clusterId) return;

    setIsLoading(true);
    setError(null);

    const response = await swarmApi.getCluster(clusterId);

    if (response.success && response.data) {
      setCluster(response.data.cluster);
    } else {
      setError(response.error || 'Failed to fetch cluster');
    }

    setIsLoading(false);
  }, [clusterId]);

  useEffect(() => {
    if (autoLoad) {
      fetchCluster();
    }
  }, [fetchCluster, autoLoad]);

  return {
    cluster,
    isLoading,
    error,
    refetch: fetchCluster,
  };
}
