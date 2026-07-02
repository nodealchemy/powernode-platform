import React, { useState, useEffect, useCallback, useRef } from 'react';
import { Brain } from 'lucide-react';
import { PageContainer, type PageAction } from '@/shared/components/layout/PageContainer';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { Loading } from '@/shared/components/ui/Loading';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useRefreshAction } from '@/shared/hooks/useRefreshAction';
import { MemoryStatsBar } from '../components/MemoryStatsBar';
import { MemoryTierTabs } from '../components/MemoryTierTabs';
import { MemoryEntryCard } from '../components/MemoryEntryCard';
import { MemoryFilterBar } from '../components/MemoryFilterBar';
import { SharedKnowledgeList } from '../components/SharedKnowledgeList';
import { AgentSelectorCard } from '../components/AgentSelectorCard';
import { useInfiniteMemory } from '../hooks/useInfiniteMemory';
import { useMemoryFilters } from '../hooks/useMemoryFilters';
import { useAgentMemorySelection } from '../hooks/useAgentMemorySelection';
import {
  fetchSharedKnowledge,
  deleteMemory,
} from '../api/memoryApi';
import type { MemoryEntry, SharedKnowledgeEntry } from '../types/memory';

interface MemoryExplorerContentProps {
  onActionsReady?: (actions: PageAction[]) => void;
}

export const MemoryExplorerContent: React.FC<MemoryExplorerContentProps> = ({ onActionsReady }) => {
  const { addNotification } = useNotifications();
  const { tier: activeTier, filters, activeFilterCount, setTier, setSearch, setFilter, clearFilters } = useMemoryFilters();

  const {
    agents,
    agentsLoading,
    selectedAgentId,
    handleAgentChange,
    stats,
    statsLoading,
    loadStats,
  } = useAgentMemorySelection({ clearStatsOnError: true });

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

  // Stats loading on agent change is handled inside useAgentMemorySelection
  useEffect(() => {
    loadSharedKnowledge();
  }, [loadSharedKnowledge]);

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
      <AgentSelectorCard
        agents={agents}
        selectedAgentId={selectedAgentId}
        onAgentChange={handleAgentChange}
      />

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
            <div className="p-4 bg-theme-danger-fg/10 border border-theme-danger-border/30 rounded-lg text-theme-danger-fg">
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
