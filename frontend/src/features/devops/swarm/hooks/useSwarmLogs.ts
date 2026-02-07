import { useState, useEffect, useCallback, useRef } from 'react';
import { swarmApi } from '../services/swarmApi';
import type { ServiceLogEntry, ServiceLogOptions } from '../types';

interface UseSwarmLogsOptions {
  clusterId: string;
  serviceId: string;
  autoLoad?: boolean;
  pollInterval?: number;
  tail?: number;
}

interface UseSwarmLogsResult {
  logs: ServiceLogEntry[];
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
  startPolling: () => void;
  stopPolling: () => void;
  isPolling: boolean;
}

export function useSwarmLogs(options: UseSwarmLogsOptions): UseSwarmLogsResult {
  const { clusterId, serviceId, autoLoad = true, pollInterval = 5000, tail = 200 } = options;
  const [logs, setLogs] = useState<ServiceLogEntry[]>([]);
  const [isLoading, setIsLoading] = useState(autoLoad);
  const [error, setError] = useState<string | null>(null);
  const [isPolling, setIsPolling] = useState(false);
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const fetchLogs = useCallback(async (logOptions?: ServiceLogOptions) => {
    if (!clusterId || !serviceId) return;

    setIsLoading(true);
    setError(null);

    const response = await swarmApi.getServiceLogs(clusterId, serviceId, {
      tail,
      timestamps: true,
      ...logOptions,
    });

    if (response.success && response.data) {
      setLogs(response.data.items ?? []);
    } else {
      setError(response.error || 'Failed to fetch logs');
    }

    setIsLoading(false);
  }, [clusterId, serviceId, tail]);

  useEffect(() => {
    if (autoLoad) {
      fetchLogs();
    }
  }, [fetchLogs, autoLoad]);

  const startPolling = useCallback(() => {
    if (intervalRef.current) return;

    setIsPolling(true);
    intervalRef.current = setInterval(() => {
      fetchLogs();
    }, pollInterval);
  }, [fetchLogs, pollInterval]);

  const stopPolling = useCallback(() => {
    if (intervalRef.current) {
      clearInterval(intervalRef.current);
      intervalRef.current = null;
    }
    setIsPolling(false);
  }, []);

  useEffect(() => {
    return () => {
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
      }
    };
  }, []);

  return {
    logs,
    isLoading,
    error,
    refetch: fetchLogs,
    startPolling,
    stopPolling,
    isPolling,
  };
}
