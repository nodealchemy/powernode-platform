import { useState, useEffect, useCallback } from 'react';
import { dockerApi } from '../services/dockerApi';
import type { DockerVolume } from '../types';

export function useDockerVolumes(hostId: string | null) {
  const [volumes, setVolumes] = useState<DockerVolume[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetch = useCallback(async () => {
    if (!hostId) return;
    setIsLoading(true);
    setError(null);
    const response = await dockerApi.getVolumes(hostId);
    if (response.success && response.data) {
      setVolumes(response.data.items ?? []);
    } else {
      setError(response.error || 'Failed to fetch volumes');
    }
    setIsLoading(false);
  }, [hostId]);

  useEffect(() => { fetch(); }, [fetch]);

  return { volumes, isLoading, error, refresh: fetch };
}
