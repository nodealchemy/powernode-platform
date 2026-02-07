import { useState, useEffect, useCallback } from 'react';
import { dockerApi } from '../services/dockerApi';
import type { HostHealthSummary } from '../types';

export function useDockerHealth(hostId: string | null) {
  const [health, setHealth] = useState<HostHealthSummary | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetch = useCallback(async () => {
    if (!hostId) return;
    setIsLoading(true);
    setError(null);
    const response = await dockerApi.getHostHealth(hostId);
    if (response.success && response.data) {
      setHealth(response.data.health);
    } else {
      setError(response.error || 'Failed to fetch host health');
    }
    setIsLoading(false);
  }, [hostId]);

  useEffect(() => { fetch(); }, [fetch]);

  return { health, isLoading, error, refresh: fetch };
}
