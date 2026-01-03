import { useState, useEffect, useCallback } from 'react';
import { gitProvidersApi } from '@/features/git-providers/services/gitProvidersApi';
import type {
  GitWebhookEvent,
  WebhookEventStats,
  PaginationInfo,
  WebhookEventFilters,
} from '../types';

interface UseWebhookEventsParams extends WebhookEventFilters {
  page?: number;
  perPage?: number;
}

interface UseWebhookEventsReturn {
  events: GitWebhookEvent[];
  pagination: PaginationInfo | null;
  stats: WebhookEventStats | null;
  loading: boolean;
  error: string | null;
  refresh: () => Promise<void>;
  retryEvent: (eventId: string) => Promise<void>;
}

export function useWebhookEvents(
  params: UseWebhookEventsParams = {}
): UseWebhookEventsReturn {
  const [events, setEvents] = useState<GitWebhookEvent[]>([]);
  const [pagination, setPagination] = useState<PaginationInfo | null>(null);
  const [stats, setStats] = useState<WebhookEventStats | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchEvents = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);

      const data = await gitProvidersApi.getWebhookEvents({
        page: params.page,
        per_page: params.perPage,
        event_type: params.eventType,
        status: params.status === 'all' ? undefined : params.status,
        repository_id: params.repositoryId,
        since: params.since,
        until: params.until,
      });

      setEvents(data.events);
      setPagination(data.pagination);
      setStats(data.stats);
    } catch (err) {
      setError(
        err instanceof Error ? err.message : 'Failed to fetch webhook events'
      );
    } finally {
      setLoading(false);
    }
  }, [
    params.page,
    params.perPage,
    params.eventType,
    params.status,
    params.repositoryId,
    params.since,
    params.until,
  ]);

  useEffect(() => {
    fetchEvents();
  }, [fetchEvents]);

  const retryEvent = useCallback(
    async (eventId: string) => {
      try {
        await gitProvidersApi.retryWebhookEvent(eventId);
        await fetchEvents();
      } catch (err) {
        // Re-throw so caller can handle with notification
        throw err;
      }
    },
    [fetchEvents]
  );

  return {
    events,
    pagination,
    stats,
    loading,
    error,
    refresh: fetchEvents,
    retryEvent,
  };
}

export default useWebhookEvents;
