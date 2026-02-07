import { useState, useEffect, useCallback } from 'react';
import { dockerApi } from '../services/dockerApi';
import type { DockerContainer } from '../types';

export function useDockerContainer(hostId: string | null, containerId: string | null) {
  const [container, setContainer] = useState<DockerContainer | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetch = useCallback(async () => {
    if (!hostId || !containerId) return;
    setIsLoading(true);
    setError(null);
    const response = await dockerApi.getContainer(hostId, containerId);
    if (response.success && response.data) {
      setContainer(response.data.container);
    } else {
      setError(response.error || 'Failed to fetch container');
    }
    setIsLoading(false);
  }, [hostId, containerId]);

  useEffect(() => { fetch(); }, [fetch]);

  return { container, isLoading, error, refresh: fetch };
}
