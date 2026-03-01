import { useState, useEffect, useCallback } from 'react';
import { contextApi } from '../api/contextApi';
import type {
  AiContextEntrySummary,
  AiAgentSummary,
  AiPersistentContextSummary,
  EntryFilters,
  Pagination,
} from '../types/context';

interface UseAgentMemoryOptions {
  agentId: string;
  filters?: EntryFilters;
  autoLoad?: boolean;
}

interface UseAgentMemoryResult {
  memories: AiContextEntrySummary[];
  agent: AiAgentSummary | null;
  context: AiPersistentContextSummary | null;
  pagination: Pagination | null;
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
  addMemory: (data: {
    entry_type: string;
    key: string;
    content: Record<string, unknown>;
    content_text?: string;
    importance_score?: number;
    tags?: string[];
  }) => Promise<boolean>;
  clearMemory: (entryTypes?: string[]) => Promise<boolean>;
}

export function useAgentMemory(options: UseAgentMemoryOptions): UseAgentMemoryResult {
  const { agentId, filters, autoLoad = true } = options;
  const [memories, setMemories] = useState<AiContextEntrySummary[]>([]);
  const [agent, setAgent] = useState<AiAgentSummary | null>(null);
  const [context, setContext] = useState<AiPersistentContextSummary | null>(null);
  const [pagination, setPagination] = useState<Pagination | null>(null);
  const [isLoading, setIsLoading] = useState(autoLoad);
  const [error, setError] = useState<string | null>(null);

  const fetchMemory = useCallback(async () => {
    if (!agentId) return;

    setIsLoading(true);
    setError(null);

    try {
      const response = await contextApi.getAgentMemory(agentId, 1, 100, filters);

      if (response.success && response.data) {
        setMemories(response.data.memories);
        setAgent(response.data.agent);
        setContext(response.data.context);
        setPagination(response.data.pagination);
      } else {
        setError(response.error || 'Failed to fetch agent memory');
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch agent memory');
    } finally {
      setIsLoading(false);
    }
  }, [agentId, filters]);

  useEffect(() => {
    if (autoLoad) {
      fetchMemory();
    }
  }, [fetchMemory, autoLoad]);

  const addMemory = useCallback(
    async (data: {
      entry_type: string;
      key: string;
      content: Record<string, unknown>;
      content_text?: string;
      importance_score?: number;
      tags?: string[];
    }): Promise<boolean> => {
      if (!agentId) return false;

      const response = await contextApi.addAgentMemory(agentId, {
        entry_type: data.entry_type as Parameters<typeof contextApi.addAgentMemory>[1]['entry_type'],
        key: data.key,
        content: data.content,
        content_text: data.content_text,
        importance_score: data.importance_score,
        tags: data.tags,
      });

      if (response.success) {
        await fetchMemory();
        return true;
      }

      return false;
    },
    [agentId, fetchMemory]
  );

  const clearMemory = useCallback(
    async (entryTypes?: string[]): Promise<boolean> => {
      if (!agentId) return false;

      const response = await contextApi.clearAgentMemory(
        agentId,
        entryTypes as Parameters<typeof contextApi.clearAgentMemory>[1]
      );

      if (response.success) {
        await fetchMemory();
        return true;
      }

      return false;
    },
    [agentId, fetchMemory]
  );

  return {
    memories,
    agent,
    context,
    pagination,
    isLoading,
    error,
    refetch: fetchMemory,
    addMemory,
    clearMemory,
  };
}
