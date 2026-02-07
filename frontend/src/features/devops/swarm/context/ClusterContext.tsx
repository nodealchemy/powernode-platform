import React, { createContext, useState, useEffect, useCallback, useMemo } from 'react';
import { swarmApi } from '../services/swarmApi';
import type { SwarmClusterSummary } from '../types';

const STORAGE_KEY = 'powernode_selected_cluster_id';

interface ClusterContextValue {
  selectedClusterId: string | null;
  selectedCluster: SwarmClusterSummary | null;
  clusters: SwarmClusterSummary[];
  isLoading: boolean;
  error: string | null;
  selectCluster: (clusterId: string | null) => void;
  refreshClusters: () => Promise<void>;
}

export const ClusterContext = createContext<ClusterContextValue>({
  selectedClusterId: null,
  selectedCluster: null,
  clusters: [],
  isLoading: false,
  error: null,
  selectCluster: () => {},
  refreshClusters: async () => {},
});

interface ClusterProviderProps {
  children: React.ReactNode;
}

export function ClusterProvider({ children }: ClusterProviderProps) {
  const [clusters, setClusters] = useState<SwarmClusterSummary[]>([]);
  const [selectedClusterId, setSelectedClusterId] = useState<string | null>(() => {
    return localStorage.getItem(STORAGE_KEY);
  });
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchClusters = useCallback(async () => {
    setIsLoading(true);
    setError(null);

    const response = await swarmApi.getClusters(1, 100);

    if (response.success && response.data) {
      const fetched = response.data.items ?? [];
      setClusters(fetched);

      // Auto-select first connected cluster if nothing selected or selection invalid
      const currentSelection = localStorage.getItem(STORAGE_KEY);
      const isSelectionValid = currentSelection && fetched.some((c) => c.id === currentSelection);

      if (!isSelectionValid && fetched.length > 0) {
        const connected = fetched.find((c) => c.status === 'connected');
        const autoId = connected?.id ?? fetched[0].id;
        setSelectedClusterId(autoId);
        localStorage.setItem(STORAGE_KEY, autoId);
      }
    } else {
      setError(response.error || 'Failed to fetch clusters');
    }

    setIsLoading(false);
  }, []);

  useEffect(() => {
    fetchClusters();
  }, [fetchClusters]);

  const selectCluster = useCallback((clusterId: string | null) => {
    setSelectedClusterId(clusterId);
    if (clusterId) {
      localStorage.setItem(STORAGE_KEY, clusterId);
    } else {
      localStorage.removeItem(STORAGE_KEY);
    }
  }, []);

  const selectedCluster = useMemo(
    () => clusters.find((c) => c.id === selectedClusterId) ?? null,
    [clusters, selectedClusterId]
  );

  const value = useMemo<ClusterContextValue>(
    () => ({
      selectedClusterId,
      selectedCluster,
      clusters,
      isLoading,
      error,
      selectCluster,
      refreshClusters: fetchClusters,
    }),
    [selectedClusterId, selectedCluster, clusters, isLoading, error, selectCluster, fetchClusters]
  );

  return (
    <ClusterContext.Provider value={value}>
      {children}
    </ClusterContext.Provider>
  );
}
