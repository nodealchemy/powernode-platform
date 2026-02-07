import { useState, useEffect, useCallback } from 'react';
import { dockerApi } from '../services/dockerApi';
import type { DockerContainerSummary, ContainerFilters } from '../types';

export function useDockerContainers(hostId: string | null, filters?: ContainerFilters) {
  const [containers, setContainers] = useState<DockerContainerSummary[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetch = useCallback(async () => {
    if (!hostId) return;
    setIsLoading(true);
    setError(null);
    const response = await dockerApi.getContainers(hostId, filters);
    if (response.success && response.data) {
      setContainers(response.data.items ?? []);
    } else {
      setError(response.error || 'Failed to fetch containers');
    }
    setIsLoading(false);
  }, [hostId, filters?.state, filters?.q]);

  useEffect(() => { fetch(); }, [fetch]);

  return { containers, isLoading, error, refresh: fetch };
}
