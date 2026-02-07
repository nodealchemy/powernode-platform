import { useState, useEffect, useCallback } from 'react';
import { swarmApi } from '../services/swarmApi';
import type { SwarmStackSummary, SwarmStack, StackFormData } from '../types';

interface UseSwarmStacksOptions {
  clusterId: string;
  autoLoad?: boolean;
}

interface UseSwarmStacksResult {
  stacks: SwarmStackSummary[];
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
  getStack: (stackId: string) => Promise<SwarmStack | null>;
  createStack: (data: StackFormData) => Promise<SwarmStack | null>;
  updateStack: (stackId: string, data: Partial<StackFormData>) => Promise<SwarmStack | null>;
  deleteStack: (stackId: string) => Promise<boolean>;
  deployStack: (stackId: string) => Promise<boolean>;
  removeStack: (stackId: string) => Promise<boolean>;
}

export function useSwarmStacks(options: UseSwarmStacksOptions): UseSwarmStacksResult {
  const { clusterId, autoLoad = true } = options;
  const [stacks, setStacks] = useState<SwarmStackSummary[]>([]);
  const [isLoading, setIsLoading] = useState(autoLoad);
  const [error, setError] = useState<string | null>(null);

  const fetchStacks = useCallback(async () => {
    if (!clusterId) return;

    setIsLoading(true);
    setError(null);

    const response = await swarmApi.getStacks(clusterId);

    if (response.success && response.data) {
      setStacks(response.data.items ?? []);
    } else {
      setError(response.error || 'Failed to fetch stacks');
    }

    setIsLoading(false);
  }, [clusterId]);

  useEffect(() => {
    if (autoLoad) {
      fetchStacks();
    }
  }, [fetchStacks, autoLoad]);

  const getStack = useCallback(async (stackId: string): Promise<SwarmStack | null> => {
    const response = await swarmApi.getStack(clusterId, stackId);
    if (response.success && response.data) {
      return response.data.stack;
    }
    setError(response.error || 'Failed to fetch stack');
    return null;
  }, [clusterId]);

  const createStack = useCallback(async (data: StackFormData): Promise<SwarmStack | null> => {
    const response = await swarmApi.createStack(clusterId, data);
    if (response.success && response.data) {
      await fetchStacks();
      return response.data.stack;
    }
    setError(response.error || 'Failed to create stack');
    return null;
  }, [clusterId, fetchStacks]);

  const updateStack = useCallback(async (stackId: string, data: Partial<StackFormData>): Promise<SwarmStack | null> => {
    const response = await swarmApi.updateStack(clusterId, stackId, data);
    if (response.success && response.data) {
      await fetchStacks();
      return response.data.stack;
    }
    setError(response.error || 'Failed to update stack');
    return null;
  }, [clusterId, fetchStacks]);

  const deleteStack = useCallback(async (stackId: string): Promise<boolean> => {
    const response = await swarmApi.deleteStack(clusterId, stackId);
    if (response.success) {
      await fetchStacks();
      return true;
    }
    setError(response.error || 'Failed to delete stack');
    return false;
  }, [clusterId, fetchStacks]);

  const deployStack = useCallback(async (stackId: string): Promise<boolean> => {
    const response = await swarmApi.deployStack(clusterId, stackId);
    if (response.success) {
      await fetchStacks();
      return true;
    }
    setError(response.error || 'Failed to deploy stack');
    return false;
  }, [clusterId, fetchStacks]);

  const removeStack = useCallback(async (stackId: string): Promise<boolean> => {
    const response = await swarmApi.removeStack(clusterId, stackId);
    if (response.success) {
      await fetchStacks();
      return true;
    }
    setError(response.error || 'Failed to remove stack');
    return false;
  }, [clusterId, fetchStacks]);

  return {
    stacks,
    isLoading,
    error,
    refetch: fetchStacks,
    getStack,
    createStack,
    updateStack,
    deleteStack,
    deployStack,
    removeStack,
  };
}
