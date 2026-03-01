import { useState, useEffect, useCallback } from 'react';
import { dockerApi } from '../services/dockerApi';
import type { DockerHostSummary, Pagination, HostFilters } from '../types';

export function useDockerHosts(page = 1, perPage = 20, filters?: HostFilters) {
  const [hosts, setHosts] = useState<DockerHostSummary[]>([]);
  const [pagination, setPagination] = useState<Pagination | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetch = useCallback(async () => {
    setIsLoading(true);
    setError(null);
    const response = await dockerApi.getHosts(page, perPage, filters);
    if (response.success && response.data) {
      setHosts(response.data.items ?? []);
      setPagination(response.data.pagination);
    } else {
      setError(response.error || 'Failed to fetch hosts');
    }
    setIsLoading(false);
  }, [page, perPage, filters?.environment, filters?.status, filters?.q]);

  useEffect(() => { fetch(); }, [fetch]);

  return { hosts, pagination, isLoading, error, refresh: fetch };
}
