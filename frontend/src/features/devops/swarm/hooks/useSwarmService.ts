import { useState, useEffect, useCallback, useRef } from 'react';
import { swarmApi } from '../services/swarmApi';
import type { SwarmService, SwarmTask } from '../types';

interface UseSwarmServiceOptions {
  clusterId: string;
  serviceId: string;
  autoLoad?: boolean;
}

interface UseSwarmServiceResult {
  service: SwarmService | null;
  tasks: SwarmTask[];
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
  refetchTasks: () => Promise<void>;
}

export function useSwarmService(options: UseSwarmServiceOptions): UseSwarmServiceResult {
  const { clusterId, serviceId, autoLoad = true } = options;
  const [service, setService] = useState<SwarmService | null>(null);
  const [tasks, setTasks] = useState<SwarmTask[]>([]);
  const [isLoading, setIsLoading] = useState(autoLoad);
  const [error, setError] = useState<string | null>(null);
  const initialLoadDone = useRef(false);

  const fetchService = useCallback(async () => {
    if (!clusterId || !serviceId) return;

    if (!initialLoadDone.current) setIsLoading(true);
    setError(null);

    const response = await swarmApi.getService(clusterId, serviceId);

    if (response.success && response.data) {
      setService(response.data.service);
    } else {
      setError(response.error || 'Failed to fetch service');
    }

    setIsLoading(false);
    initialLoadDone.current = true;
  }, [clusterId, serviceId]);

  const fetchTasks = useCallback(async () => {
    if (!clusterId || !serviceId) return;

    const response = await swarmApi.getServiceTasks(clusterId, serviceId);

    if (response.success && response.data) {
      setTasks(response.data.items ?? []);
    }
  }, [clusterId, serviceId]);

  useEffect(() => {
    if (autoLoad) {
      fetchService();
      fetchTasks();
    }
  }, [fetchService, fetchTasks, autoLoad]);

  return {
    service,
    tasks,
    isLoading,
    error,
    refetch: fetchService,
    refetchTasks: fetchTasks,
  };
}
