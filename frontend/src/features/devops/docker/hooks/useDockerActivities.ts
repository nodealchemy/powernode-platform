import { useState, useEffect, useCallback } from 'react';
import { dockerApi } from '../services/dockerApi';
import type { DockerActivitySummary, Pagination, ActivityFilters } from '../types';

export function useDockerActivities(hostId: string | null, page = 1, perPage = 20, filters?: ActivityFilters) {
  const [activities, setActivities] = useState<DockerActivitySummary[]>([]);
  const [pagination, setPagination] = useState<Pagination | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetch = useCallback(async () => {
    if (!hostId) return;
    setIsLoading(true);
    setError(null);
    const response = await dockerApi.getActivities(hostId, page, perPage, filters);
    if (response.success && response.data) {
      setActivities(response.data.items ?? []);
      setPagination(response.data.pagination);
    } else {
      setError(response.error || 'Failed to fetch activities');
    }
    setIsLoading(false);
  }, [hostId, page, perPage, filters?.activity_type, filters?.status]);

  useEffect(() => { fetch(); }, [fetch]);

  return { activities, pagination, isLoading, error, refresh: fetch };
}
