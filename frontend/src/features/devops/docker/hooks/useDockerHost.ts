import { useState, useEffect, useCallback } from 'react';
import { dockerApi } from '../services/dockerApi';
import type { DockerHost } from '../types';

export function useDockerHost(hostId: string | null) {
  const [host, setHost] = useState<DockerHost | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetch = useCallback(async () => {
    if (!hostId) return;
    setIsLoading(true);
    setError(null);
    const response = await dockerApi.getHost(hostId);
    if (response.success && response.data) {
      setHost(response.data.host);
    } else {
      setError(response.error || 'Failed to fetch host');
    }
    setIsLoading(false);
  }, [hostId]);

  useEffect(() => { fetch(); }, [fetch]);

  return { host, isLoading, error, refresh: fetch };
}
