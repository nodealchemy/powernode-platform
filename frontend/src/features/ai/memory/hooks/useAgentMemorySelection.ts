import { useState, useEffect, useCallback } from 'react';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { agentsApi } from '@/shared/services/ai';
import { fetchMemoryStats } from '../api/memoryApi';
import { useMemoryFilters } from './useMemoryFilters';
import type { AiAgent } from '@/shared/types/ai';
import type { MemoryStats } from '../types/memory';

interface UseAgentMemorySelectionOptions {
  /** Reset stats to null when a stats fetch fails (default: keep previous stats). */
  clearStatsOnError?: boolean;
}

/**
 * Shared agent-selector state for the memory surfaces: loads the agent list,
 * auto-selects the first agent (unless one is already pinned in the URL),
 * keeps the selection synced to the `memory_agent` URL param, and loads
 * per-agent memory stats whenever the selection changes.
 */
export function useAgentMemorySelection(options: UseAgentMemorySelectionOptions = {}) {
  const { clearStatsOnError = false } = options;
  const { addNotification } = useNotifications();
  const { agentId: urlAgentId, setAgentId: setUrlAgentId } = useMemoryFilters();

  const [agents, setAgents] = useState<AiAgent[]>([]);
  const [agentsLoading, setAgentsLoading] = useState(true);
  const [selectedAgentId, setSelectedAgentId] = useState(urlAgentId || '');
  const [stats, setStats] = useState<MemoryStats | null>(null);
  const [statsLoading, setStatsLoading] = useState(false);

  // Sync agent selection to URL
  const handleAgentChange = useCallback((id: string) => {
    setSelectedAgentId(id);
    setUrlAgentId(id);
  }, [setUrlAgentId]);

  // Load agents list (once)
  useEffect(() => {
    const loadAgents = async () => {
      try {
        setAgentsLoading(true);
        const { items } = await agentsApi.getAgents({ per_page: 100 });
        const agentsList = (items || []) as AiAgent[];
        setAgents(agentsList);
        if (agentsList.length > 0 && !selectedAgentId) {
          const firstId = agentsList[0].id;
          setSelectedAgentId(firstId);
          setUrlAgentId(firstId);
        }
      } catch (_error) {
        addNotification({ type: 'error', message: 'Failed to load agents' });
      } finally {
        setAgentsLoading(false);
      }
    };
    loadAgents();
  }, []);

  // Load stats when the selected agent changes
  const loadStats = useCallback(async () => {
    if (!selectedAgentId) return;
    try {
      setStatsLoading(true);
      const data = await fetchMemoryStats(selectedAgentId);
      setStats(data);
    } catch (_error) {
      // Stats failure is non-critical
      if (clearStatsOnError) setStats(null);
    } finally {
      setStatsLoading(false);
    }
  }, [selectedAgentId, clearStatsOnError]);

  useEffect(() => {
    loadStats();
  }, [loadStats]);

  return {
    agents,
    agentsLoading,
    selectedAgentId,
    handleAgentChange,
    stats,
    statsLoading,
    loadStats,
  };
}
