import { useState, useEffect, useCallback } from 'react';
import { dockerApi } from '../services/dockerApi';
import type { DockerEventSummary, Pagination, EventFilters } from '../types';

export function useDockerEvents(hostId: string | null, page = 1, perPage = 50, filters?: EventFilters) {
  const [events, setEvents] = useState<DockerEventSummary[]>([]);
  const [pagination, setPagination] = useState<Pagination | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetch = useCallback(async () => {
    if (!hostId) return;
    setIsLoading(true);
    setError(null);
    const response = await dockerApi.getEvents(hostId, page, perPage, filters);
    if (response.success && response.data) {
      setEvents(response.data.items ?? []);
      setPagination(response.data.pagination);
    } else {
      setError(response.error || 'Failed to fetch events');
    }
    setIsLoading(false);
  }, [hostId, page, perPage, filters?.severity, filters?.source_type, filters?.acknowledged, filters?.since]);

  useEffect(() => { fetch(); }, [fetch]);

  return { events, pagination, isLoading, error, refresh: fetch };
}
