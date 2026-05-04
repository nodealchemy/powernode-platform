import { useState, useEffect, useCallback } from 'react';
import { kubernetesApi } from '../services/kubernetesApi';
import type { ClusterFilters, KubernetesClusterSummary } from '../types';

export function useKubernetesClusters(filters?: ClusterFilters) {
  const [clusters, setClusters] = useState<KubernetesClusterSummary[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetch = useCallback(async () => {
    setIsLoading(true);
    setError(null);
    const response = await kubernetesApi.getClusters(filters);
    if (response.success && response.data) {
      setClusters(response.data.items ?? []);
    } else {
      setError(response.error || 'Failed to fetch clusters');
    }
    setIsLoading(false);
    // Stringify filters for stable dep — matches the pattern used by
    // useDockerHosts in the Docker feature.
  }, [filters?.status, filters?.flavor, filters?.environment]);

  useEffect(() => {
    fetch();
  }, [fetch]);

  return { clusters, isLoading, error, refresh: fetch };
}
