import { useState, useCallback, useRef, useEffect } from 'react';
import { fetchMemoryEntriesPaginated } from '../api/memoryApi';
import type { MemoryEntry, MemoryTier, MemoryPagination, MemoryFilters } from '../types/memory';

const PER_PAGE = 25;

interface UseInfiniteMemoryOptions {
  agentId: string;
  tier: MemoryTier;
  filters?: MemoryFilters;
}

export function useInfiniteMemory({ agentId, tier, filters = {} }: UseInfiniteMemoryOptions) {
  const [entries, setEntries] = useState<MemoryEntry[]>([]);
  const [pagination, setPagination] = useState<MemoryPagination | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Track the current request identity to discard stale responses
  const requestIdRef = useRef(0);

  const loadPage = useCallback(
    async (page: number, append: boolean) => {
      if (!agentId) return;
      const currentRequestId = ++requestIdRef.current;

      try {
        if (append) {
          setLoadingMore(true);
        } else {
          setLoading(true);
          setError(null);
        }

        const response = await fetchMemoryEntriesPaginated(agentId, tier, page, PER_PAGE, filters);

        // Discard if a newer request has been issued
        if (currentRequestId !== requestIdRef.current) return;

        if (append) {
          setEntries((prev) => [...prev, ...response.entries]);
        } else {
          setEntries(response.entries);
        }
        setPagination(response.pagination);
      } catch (err) {
        if (currentRequestId !== requestIdRef.current) return;
        setError(err instanceof Error ? err.message : 'Failed to load memories');
      } finally {
        if (currentRequestId === requestIdRef.current) {
          setLoading(false);
          setLoadingMore(false);
        }
      }
    },
    [agentId, tier, filters]
  );

  // Reset and load first page when dependencies change
  useEffect(() => {
    setEntries([]);
    setPagination(null);
    loadPage(1, false);
  }, [loadPage]);

  const loadMore = useCallback(() => {
    if (loadingMore || !pagination?.has_more) return;
    loadPage(pagination.current_page + 1, true);
  }, [loadingMore, pagination, loadPage]);

  const refresh = useCallback(() => {
    setEntries([]);
    setPagination(null);
    loadPage(1, false);
  }, [loadPage]);

  const removeEntry = useCallback((entryId: string | undefined, key: string) => {
    setEntries((prev) => prev.filter((e) => (e.id ? e.id !== entryId : e.key !== key)));
    if (pagination) {
      setPagination({ ...pagination, total_count: pagination.total_count - 1 });
    }
  }, [pagination]);

  return {
    entries,
    pagination,
    loading,
    loadingMore,
    error,
    hasMore: pagination?.has_more ?? false,
    totalCount: pagination?.total_count ?? 0,
    loadMore,
    refresh,
    removeEntry,
  };
}
