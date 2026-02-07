import { useState, useEffect, useCallback } from 'react';
import { dockerApi } from '../services/dockerApi';
import type { DockerNetwork } from '../types';

export function useDockerNetworks(hostId: string | null) {
  const [networks, setNetworks] = useState<DockerNetwork[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetch = useCallback(async () => {
    if (!hostId) return;
    setIsLoading(true);
    setError(null);
    const response = await dockerApi.getNetworks(hostId);
    if (response.success && response.data) {
      setNetworks(response.data.items ?? []);
    } else {
      setError(response.error || 'Failed to fetch networks');
    }
    setIsLoading(false);
  }, [hostId]);

  useEffect(() => { fetch(); }, [fetch]);

  return { networks, isLoading, error, refresh: fetch };
}
