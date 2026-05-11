import React, { useState, useEffect, useCallback, useRef } from 'react';
import { Brain } from 'lucide-react';
import { PageContainer, type PageAction } from '@/shared/components/layout/PageContainer';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { Loading } from '@/shared/components/ui/Loading';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useRefreshAction } from '@/shared/hooks/useRefreshAction';
import { agentsApi } from '@/shared/services/ai';
import { MemoryStatsBar } from '../components/MemoryStatsBar';
import { MemoryTierTabs } from '../components/MemoryTierTabs';
import { MemoryEntryCard } from '../components/MemoryEntryCard';
import { MemoryFilterBar } from '../components/MemoryFilterBar';
import { SharedKnowledgeList } from '../components/SharedKnowledgeList';
import { useInfiniteMemory } from '../hooks/useInfiniteMemory';
import { useMemoryFilters } from '../hooks/useMemoryFilters';
import {
  fetchMemoryStats,
  fetchSharedKnowledge,
  deleteMemory,
} from '../api/memoryApi';
import type { MemoryStats, MemoryEntry, SharedKnowledgeEntry } from '../types/memory';
import type { AiAgent } from '@/shared/types/ai';

interface MemoryExplorerContentProps {
  onActionsReady?: (actions: PageAction[]) => void;
}

export const MemoryExplorerContent: React.FC<MemoryExplorerContentProps> = ({ onActionsReady }) => {
  const { addNotification } = useNotifications();
  const { tier: activeTier, filters, activeFilterCount, setTier, setSearch, setFilter, clearFilters, agentId: urlAgentId, setAgentId: setUrlAgentId } = useMemoryFilters();

  const [agents, setAgents] = useState<AiAgent[]>([]);
  const [agentsLoading, setAgentsLoading] = useState(true);
  const [selectedAgentId, setSelectedAgentId] = useState(urlAgentId || '');

  const [stats, setStats] = useState<MemoryStats | null>(null);
  const [statsLoading, setStatsLoading] = useState(false);

  const [sharedKnowledge, setSharedKnowledge] = useState<SharedKnowledgeEntry[]>([]);
  const [sharedLoading, setSharedLoading] = useState(false);

  const {
    entries,
    loading: entriesLoading,
    loadingMore,
    error: entriesError,
    hasMore,
    totalCount,
    loadMore,
    refresh: refreshEntries,
    removeEntry,
  } = useInfiniteMemory({ agentId: selectedAgentId, tier: activeTier, filters });

  // Infinite scroll sentinel
  const sentinelRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const sentinel = sentinelRef.current;
    if (!sentinel) return;

    const observer = new IntersectionObserver(
      (intersections) => {
        if (intersections[0]?.isIntersecting && hasMore && !loadingMore) {
          loadMore();
        }
      },
      { rootMargin: '200px' }
    );
    observer.observe(sentinel);
    return () => observer.disconnect();
  }, [hasMore, loadingMore, loadMore]);

  const handleAgentChange = useCallback((id: string) => {
    setSelectedAgentId(id);
    setUrlAgentId(id);
  }, [setUrlAgentId]);

  // Load agents list
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

  // Load stats when agent changes
  const loadStats = useCallback(async () => {
    if (!selectedAgentId) return;
    try {
      setStatsLoading(true);
      const data = await fetchMemoryStats(selectedAgentId);
      setStats(data);
    } catch (_error) {
      setStats(null);
    } finally {
      setStatsLoading(false);
    }
  }, [selectedAgentId]);

  // Load shared knowledge
  const loadSharedKnowledge = useCallback(async () => {
    try {
      setSharedLoading(true);
      const data = await fetchSharedKnowledge();
      setSharedKnowledge(data || []);
    } catch (_error) {
      setSharedKnowledge([]);
    } finally {
      setSharedLoading(false);
    }
  }, []);

  useEffect(() => {
    loadStats();
    loadSharedKnowledge();
  }, [loadStats, loadSharedKnowledge]);

  const handleDelete = async (entry: MemoryEntry) => {
    if (!selectedAgentId || !entry.key) return;
    try {
      await deleteMemory({
        agent_id: selectedAgentId,
        key: entry.key,
        tier: entry.tier,
        session_id: entry.session_id,
      });
      addNotification({ type: 'success', message: `Memory "${entry.key}" deleted` });
      removeEntry(entry.id, entry.key);
      loadStats();
    } catch (_error) {
      addNotification({ type: 'error', message: 'Failed to delete memory entry' });
    }
  };

  const handleRefresh = useCallback(() => {
    loadStats();
    refreshEntries();
    loadSharedKnowledge();
  }, [loadStats, refreshEntries, loadSharedKnowledge]);

  const { refreshAction } = useRefreshAction({ onRefresh: handleRefresh });

  useEffect(() => {
    if (onActionsReady) {
      onActionsReady([refreshAction]);
    }
  }, [onActionsReady, refreshAction]);

  if (agentsLoading) {
    return <LoadingSpinner size="lg" className="py-12" message="Loading agents..." />;
  }

  return (
    <div className="space-y-6">
      {/* Agent Selector */}
      <Card>
        <CardContent className="p-4">
          <div className="flex items-center gap-3">
            <Brain className="h-5 w-5 text-theme-primary shrink-0" />
            <label className="text-sm font-medium text-theme-secondary shrink-0">Agent:</label>
            <select
              value={selectedAgentId}
              onChange={(e) => handleAgentChange(e.target.value)}
              className="flex-1 text-sm rounded-lg bg-theme-surface border border-theme text-theme-primary py-2 px-3 focus:outline-none focus:ring-2 focus:ring-theme-primary"
            >
              {agents.length === 0 && <option value="">No agents available</option>}
              {agents.map((agent) => (
                <option key={agent.id} value={agent.id}>
                  {agent.name} ({agent.status})
                </option>
              ))}
            </select>
          </div>
        </CardContent>
      </Card>

      {/* Stats Bar */}
      <MemoryStatsBar stats={stats} loading={statsLoading} onTierClick={setTier} />

      {/* Tier Tabs + Filters + Entries */}
      <Card>
        <MemoryTierTabs
          activeTier={activeTier}
          onTierChange={setTier}
          stats={stats}
        />
        <CardContent className="p-4 space-y-4">
          {/* Search & filters (hidden for working tier) */}
          {activeTier !== 'working' && (
            <MemoryFilterBar
              tier={activeTier}
              filters={filters}
              activeFilterCount={activeFilterCount}
              totalCount={totalCount}
              loading={entriesLoading}
              onSearchChange={setSearch}
              onFilterChange={setFilter}
              onClearFilters={clearFilters}
              onRefresh={refreshEntries}
            />
          )}

          {/* Error state */}
          {entriesError && (
            <div className="p-4 bg-theme-danger/10 border border-theme-danger/30 rounded-lg text-theme-danger">
              {entriesError}
            </div>
          )}

          {entriesLoading && entries.length === 0 ? (
            <LoadingSpinner className="py-8" message="Loading entries..." />
          ) : activeTier === 'working' ? (
            <EmptyState
              icon={Brain}
              title="Working Memory (Redis)"
              description={`${stats?.working?.count ?? 0} active key${(stats?.working?.count ?? 0) === 1 ? '' : 's'} in Redis. Working memory is ephemeral session storage and cannot be browsed individually.`}
            />
          ) : entries.length === 0 && !entriesError ? (
            <EmptyState
              icon={Brain}
              title={
                filters.q || activeFilterCount > 0
                  ? 'No matching entries'
                  : `No ${activeTier.replace(/_/g, ' ')} memory entries`
              }
              description={
                filters.q || activeFilterCount > 0
                  ? 'Try adjusting your search or filters.'
                  : 'Memory entries will appear here as the agent operates'
              }
            />
          ) : (
            <>
              <div className="space-y-3">
                {entries.map((entry, idx) => (
                  <MemoryEntryCard
                    key={entry.id || `${entry.key}-${idx}`}
                    entry={entry}
                    onDelete={handleDelete}
                  />
                ))}
              </div>

              {/* Infinite scroll sentinel */}
              <div ref={sentinelRef} className="h-1" />
              {loadingMore && (
                <div className="flex justify-center py-4">
                  <Loading size="sm" message="Loading more..." />
                </div>
              )}
              {!hasMore && entries.length > 0 && (
                <p className="text-center text-sm text-theme-tertiary py-2">
                  All {totalCount} entries loaded
                </p>
              )}
            </>
          )}
        </CardContent>
      </Card>

      {/* Shared Knowledge Section */}
      <SharedKnowledgeList
        entries={sharedKnowledge}
        loading={sharedLoading}
      />
    </div>
  );
};

/** Standalone page wrapper (backward compatibility) */
export const MemoryExplorerPage: React.FC = () => {
  const [actions, setActions] = useState<PageAction[]>([]);

  return (
    <PageContainer
      title="Knowledge & Memory"
      description="Explore and manage agent memory tiers"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'AI', href: '/app/ai' },
        { label: 'Knowledge & Memory' },
      ]}
      actions={actions}
    >
      <MemoryExplorerContent onActionsReady={setActions} />
    </PageContainer>
  );
};
