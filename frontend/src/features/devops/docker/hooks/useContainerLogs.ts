import { useState, useEffect, useCallback, useRef } from 'react';
import { dockerApi } from '../services/dockerApi';
import type { ContainerLogEntry, ContainerLogOptions } from '../types';

export function useContainerLogs(
  hostId: string | null,
  containerId: string | null,
  options?: ContainerLogOptions,
  pollIntervalMs = 0
) {
  const [logs, setLogs] = useState<ContainerLogEntry[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const fetch = useCallback(async () => {
    if (!hostId || !containerId) return;
    setIsLoading(true);
    setError(null);
    const response = await dockerApi.getContainerLogs(hostId, containerId, options);
    if (response.success && response.data) {
      setLogs(response.data.items ?? []);
    } else {
      setError(response.error || 'Failed to fetch container logs');
    }
    setIsLoading(false);
  }, [hostId, containerId, options?.tail, options?.since, options?.timestamps]);

  useEffect(() => { fetch(); }, [fetch]);

  useEffect(() => {
    if (pollIntervalMs > 0 && hostId && containerId) {
      intervalRef.current = setInterval(fetch, pollIntervalMs);
      return () => {
        if (intervalRef.current) clearInterval(intervalRef.current);
      };
    }
    return () => {
      if (intervalRef.current) clearInterval(intervalRef.current);
    };
  }, [fetch, pollIntervalMs, hostId, containerId]);

  return { logs, isLoading, error, refresh: fetch };
}
