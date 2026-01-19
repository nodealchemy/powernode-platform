import { useState, useEffect, useCallback } from 'react';
import { contextApi } from '../services/contextApi';
import type {
  AiPersistentContext,
  AiPersistentContextSummary,
  AiContextEntrySummary,
  AiContextEntry,
  ContextFilters,
  EntryFilters,
  Pagination,
  ContextStatsResponse,
} from '../types';

interface UseContextsOptions {
  filters?: ContextFilters;
  autoLoad?: boolean;
}

interface UseContextsResult {
  contexts: AiPersistentContextSummary[];
  pagination: Pagination | null;
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

export function useContexts(options: UseContextsOptions = {}): UseContextsResult {
  const { filters, autoLoad = true } = options;
  const [contexts, setContexts] = useState<AiPersistentContextSummary[]>([]);
  const [pagination, setPagination] = useState<Pagination | null>(null);
  const [isLoading, setIsLoading] = useState(autoLoad);
  const [error, setError] = useState<string | null>(null);

  const fetchContexts = useCallback(async () => {
    setIsLoading(true);
    setError(null);

    const response = await contextApi.getContexts(1, 100, filters);

    if (response.success && response.data) {
      setContexts(response.data.contexts);
      setPagination(response.data.pagination);
    } else {
      setError(response.error || 'Failed to fetch contexts');
    }

    setIsLoading(false);
  }, [filters]);

  useEffect(() => {
    if (autoLoad) {
      fetchContexts();
    }
  }, [fetchContexts, autoLoad]);

  return {
    contexts,
    pagination,
    isLoading,
    error,
    refetch: fetchContexts,
  };
}

interface UseContextOptions {
  id: string;
  autoLoad?: boolean;
}

interface UseContextResult {
  context: AiPersistentContext | null;
  stats: ContextStatsResponse['data'] | null;
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

export function useContext(options: UseContextOptions): UseContextResult {
  const { id, autoLoad = true } = options;
  const [context, setContext] = useState<AiPersistentContext | null>(null);
  const [stats, setStats] = useState<ContextStatsResponse['data'] | null>(null);
  const [isLoading, setIsLoading] = useState(autoLoad);
  const [error, setError] = useState<string | null>(null);

  const fetchContext = useCallback(async () => {
    if (!id) return;

    setIsLoading(true);
    setError(null);

    const [contextRes, statsRes] = await Promise.all([
      contextApi.getContext(id),
      contextApi.getContextStats(id),
    ]);

    if (contextRes.success && contextRes.data) {
      setContext(contextRes.data.context);
    } else {
      setError(contextRes.error || 'Failed to fetch context');
    }

    if (statsRes.success && statsRes.data) {
      setStats(statsRes.data);
    }

    setIsLoading(false);
  }, [id]);

  useEffect(() => {
    if (autoLoad) {
      fetchContext();
    }
  }, [fetchContext, autoLoad]);

  return {
    context,
    stats,
    isLoading,
    error,
    refetch: fetchContext,
  };
}

interface UseEntriesOptions {
  contextId: string;
  filters?: EntryFilters;
  autoLoad?: boolean;
}

interface UseEntriesResult {
  entries: AiContextEntrySummary[];
  pagination: Pagination | null;
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
  loadMore: () => Promise<void>;
}

export function useEntries(options: UseEntriesOptions): UseEntriesResult {
  const { contextId, filters, autoLoad = true } = options;
  const [entries, setEntries] = useState<AiContextEntrySummary[]>([]);
  const [pagination, setPagination] = useState<Pagination | null>(null);
  const [isLoading, setIsLoading] = useState(autoLoad);
  const [error, setError] = useState<string | null>(null);
  const [page, setPage] = useState(1);

  const fetchEntries = useCallback(
    async (pageNum: number, append = false) => {
      if (!contextId) return;

      setIsLoading(true);
      setError(null);

      const response = await contextApi.getEntries(contextId, pageNum, 50, filters);

      if (response.success && response.data) {
        if (append) {
          setEntries((prev) => [...prev, ...response.data!.entries]);
        } else {
          setEntries(response.data.entries);
        }
        setPagination(response.data.pagination);
      } else {
        setError(response.error || 'Failed to fetch entries');
      }

      setIsLoading(false);
    },
    [contextId, filters]
  );

  useEffect(() => {
    if (autoLoad) {
      setPage(1);
      fetchEntries(1);
    }
  }, [fetchEntries, autoLoad]);

  const refetch = useCallback(async () => {
    setPage(1);
    await fetchEntries(1);
  }, [fetchEntries]);

  const loadMore = useCallback(async () => {
    if (pagination && page < pagination.total_pages) {
      const nextPage = page + 1;
      setPage(nextPage);
      await fetchEntries(nextPage, true);
    }
  }, [pagination, page, fetchEntries]);

  return {
    entries,
    pagination,
    isLoading,
    error,
    refetch,
    loadMore,
  };
}

interface UseEntryOptions {
  contextId: string;
  entryId: string;
  autoLoad?: boolean;
}

interface UseEntryResult {
  entry: AiContextEntry | null;
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

export function useEntry(options: UseEntryOptions): UseEntryResult {
  const { contextId, entryId, autoLoad = true } = options;
  const [entry, setEntry] = useState<AiContextEntry | null>(null);
  const [isLoading, setIsLoading] = useState(autoLoad);
  const [error, setError] = useState<string | null>(null);

  const fetchEntry = useCallback(async () => {
    if (!contextId || !entryId) return;

    setIsLoading(true);
    setError(null);

    const response = await contextApi.getEntry(contextId, entryId);

    if (response.success && response.data) {
      setEntry(response.data.entry);
    } else {
      setError(response.error || 'Failed to fetch entry');
    }

    setIsLoading(false);
  }, [contextId, entryId]);

  useEffect(() => {
    if (autoLoad) {
      fetchEntry();
    }
  }, [fetchEntry, autoLoad]);

  return {
    entry,
    isLoading,
    error,
    refetch: fetchEntry,
  };
}
