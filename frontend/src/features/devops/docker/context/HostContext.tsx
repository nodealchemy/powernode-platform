import React, { createContext, useState, useEffect, useCallback, useMemo } from 'react';
import { dockerApi } from '../services/dockerApi';
import type { DockerHostSummary } from '../types';

const STORAGE_KEY = 'powernode_selected_docker_host_id';

interface HostContextValue {
  selectedHostId: string | null;
  selectedHost: DockerHostSummary | null;
  hosts: DockerHostSummary[];
  isLoading: boolean;
  error: string | null;
  selectHost: (hostId: string | null) => void;
  refreshHosts: () => Promise<void>;
}

export const HostContext = createContext<HostContextValue>({
  selectedHostId: null,
  selectedHost: null,
  hosts: [],
  isLoading: false,
  error: null,
  selectHost: () => {},
  refreshHosts: async () => {},
});

interface HostProviderProps {
  children: React.ReactNode;
}

export function HostProvider({ children }: HostProviderProps) {
  const [hosts, setHosts] = useState<DockerHostSummary[]>([]);
  const [selectedHostId, setSelectedHostId] = useState<string | null>(() => {
    return localStorage.getItem(STORAGE_KEY);
  });
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchHosts = useCallback(async () => {
    setIsLoading(true);
    setError(null);

    const response = await dockerApi.getHosts(1, 100);

    if (response.success && response.data) {
      const fetched = response.data.items ?? [];
      setHosts(fetched);

      // Auto-select first connected host if nothing selected or selection invalid
      const currentSelection = localStorage.getItem(STORAGE_KEY);
      const isSelectionValid = currentSelection && fetched.some((h) => h.id === currentSelection);

      if (!isSelectionValid && fetched.length > 0) {
        const connected = fetched.find((h) => h.status === 'connected');
        const autoId = connected?.id ?? fetched[0].id;
        setSelectedHostId(autoId);
        localStorage.setItem(STORAGE_KEY, autoId);
      }
    } else {
      setError(response.error || 'Failed to fetch hosts');
    }

    setIsLoading(false);
  }, []);

  useEffect(() => {
    fetchHosts();
  }, [fetchHosts]);

  const selectHost = useCallback((hostId: string | null) => {
    setSelectedHostId(hostId);
    if (hostId) {
      localStorage.setItem(STORAGE_KEY, hostId);
    } else {
      localStorage.removeItem(STORAGE_KEY);
    }
  }, []);

  const selectedHost = useMemo(
    () => hosts.find((h) => h.id === selectedHostId) ?? null,
    [hosts, selectedHostId]
  );

  const value = useMemo<HostContextValue>(
    () => ({
      selectedHostId,
      selectedHost,
      hosts,
      isLoading,
      error,
      selectHost,
      refreshHosts: fetchHosts,
    }),
    [selectedHostId, selectedHost, hosts, isLoading, error, selectHost, fetchHosts]
  );

  return (
    <HostContext.Provider value={value}>
      {children}
    </HostContext.Provider>
  );
}
