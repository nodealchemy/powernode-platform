import { useState, useEffect, useCallback, useRef } from 'react';
import { swarmApi } from '../services/swarmApi';
import type { ClusterHealthSummary } from '../types';

interface UseSwarmHealthOptions {
  clusterId: string;
  autoLoad?: boolean;
  refreshInterval?: number;
}

interface UseSwarmHealthResult {
  health: ClusterHealthSummary | null;
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

export function useSwarmHealth(options: UseSwarmHealthOptions): UseSwarmHealthResult {
  const { clusterId, autoLoad = true, refreshInterval = 30000 } = options;
  const [health, setHealth] = useState<ClusterHealthSummary | null>(null);
  const [isLoading, setIsLoading] = useState(autoLoad);
  const [error, setError] = useState<string | null>(null);
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const fetchHealth = useCallback(async () => {
    if (!clusterId) return;

    setIsLoading(true);
    setError(null);

    const response = await swarmApi.getClusterHealth(clusterId);

    if (response.success && response.data) {
      setHealth(response.data.health);
    } else {
      setError(response.error || 'Failed to fetch cluster health');
    }

    setIsLoading(false);
  }, [clusterId]);

  useEffect(() => {
    if (autoLoad) {
      fetchHealth();
    }
  }, [fetchHealth, autoLoad]);

  useEffect(() => {
    if (!clusterId || !refreshInterval || refreshInterval <= 0) return;

    intervalRef.current = setInterval(fetchHealth, refreshInterval);

    return () => {
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
        intervalRef.current = null;
      }
    };
  }, [clusterId, refreshInterval, fetchHealth]);

  return {
    health,
    isLoading,
    error,
    refetch: fetchHealth,
  };
}
