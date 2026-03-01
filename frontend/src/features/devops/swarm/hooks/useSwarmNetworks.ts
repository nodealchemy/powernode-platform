import { useState, useEffect, useCallback } from 'react';
import { swarmApi } from '../services/swarmApi';
import type { SwarmNetwork, NetworkFormData } from '../types';

interface UseSwarmNetworksOptions {
  clusterId: string;
  autoLoad?: boolean;
}

interface UseSwarmNetworksResult {
  networks: SwarmNetwork[];
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
  createNetwork: (data: NetworkFormData) => Promise<SwarmNetwork | null>;
  deleteNetwork: (networkId: string) => Promise<boolean>;
}

export function useSwarmNetworks(options: UseSwarmNetworksOptions): UseSwarmNetworksResult {
  const { clusterId, autoLoad = true } = options;
  const [networks, setNetworks] = useState<SwarmNetwork[]>([]);
  const [isLoading, setIsLoading] = useState(autoLoad);
  const [error, setError] = useState<string | null>(null);

  const fetchNetworks = useCallback(async () => {
    if (!clusterId) return;

    setIsLoading(true);
    setError(null);

    const response = await swarmApi.getNetworks(clusterId);

    if (response.success && response.data) {
      setNetworks(response.data.items ?? []);
    } else {
      setError(response.error || 'Failed to fetch networks');
    }

    setIsLoading(false);
  }, [clusterId]);

  useEffect(() => {
    if (autoLoad) {
      fetchNetworks();
    }
  }, [fetchNetworks, autoLoad]);

  const createNetwork = useCallback(async (data: NetworkFormData): Promise<SwarmNetwork | null> => {
    const response = await swarmApi.createNetwork(clusterId, data);
    if (response.success && response.data) {
      await fetchNetworks();
      return response.data.network;
    }
    setError(response.error || 'Failed to create network');
    return null;
  }, [clusterId, fetchNetworks]);

  const deleteNetwork = useCallback(async (networkId: string): Promise<boolean> => {
    const response = await swarmApi.deleteNetwork(clusterId, networkId);
    if (response.success) {
      await fetchNetworks();
      return true;
    }
    setError(response.error || 'Failed to delete network');
    return false;
  }, [clusterId, fetchNetworks]);

  return {
    networks,
    isLoading,
    error,
    refetch: fetchNetworks,
    createNetwork,
    deleteNetwork,
  };
}
