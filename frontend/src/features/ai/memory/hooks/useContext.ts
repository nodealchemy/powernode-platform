import { useState, useEffect, useCallback } from 'react';
import { contextApi } from '../api/contextApi';
import type { AiPersistentContext, ContextStatsResponse } from '../types/context';

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

