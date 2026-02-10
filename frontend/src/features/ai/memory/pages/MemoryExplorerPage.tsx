import React, { useState, useEffect, useCallback } from 'react';
import { Brain, RefreshCw } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { agentsApi } from '@/shared/services/ai';
import { MemoryStatsBar } from '../components/MemoryStatsBar';
import { MemoryTierTabs } from '../components/MemoryTierTabs';
import { MemoryEntryCard } from '../components/MemoryEntryCard';
import { SharedKnowledgeList } from '../components/SharedKnowledgeList';
import {
  fetchMemoryStats,
  fetchMemoryEntries,
  fetchSharedKnowledge,
  deleteMemory,
} from '../api/memoryApi';
import type { MemoryTier, MemoryStats, MemoryEntry, SharedKnowledgeEntry } from '../types/memory';
import type { AiAgent } from '@/shared/types/ai';

export const MemoryExplorerPage: React.FC = () => {
  const { addNotification } = useNotifications();

  const [agents, setAgents] = useState<AiAgent[]>([]);
  const [agentsLoading, setAgentsLoading] = useState(true);
  const [selectedAgentId, setSelectedAgentId] = useState('');

  const [stats, setStats] = useState<MemoryStats | null>(null);
  const [statsLoading, setStatsLoading] = useState(false);

  const [activeTier, setActiveTier] = useState<MemoryTier>('working');
  const [entries, setEntries] = useState<MemoryEntry[]>([]);
  const [entriesLoading, setEntriesLoading] = useState(false);

  const [sharedKnowledge, setSharedKnowledge] = useState<SharedKnowledgeEntry[]>([]);
  const [sharedLoading, setSharedLoading] = useState(false);

  // Load agents list
  useEffect(() => {
    const loadAgents = async () => {
      try {
        setAgentsLoading(true);
        const { items } = await agentsApi.getAgents({ per_page: 100 });
        const agentsList = (items || []) as AiAgent[];
        setAgents(agentsList);
        if (agentsList.length > 0 && !selectedAgentId) {
          setSelectedAgentId(agentsList[0].id);
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

  // Load entries for selected tier
  const loadEntries = useCallback(async () => {
    if (!selectedAgentId) return;
    try {
      setEntriesLoading(true);
      const data = await fetchMemoryEntries(selectedAgentId, activeTier);
      setEntries(data || []);
    } catch (_error) {
      setEntries([]);
    } finally {
      setEntriesLoading(false);
    }
  }, [selectedAgentId, activeTier]);

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

  useEffect(() => {
    loadEntries();
  }, [loadEntries]);

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
      loadEntries();
      loadStats();
    } catch (_error) {
      addNotification({ type: 'error', message: 'Failed to delete memory entry' });
    }
  };

  const handleRefresh = () => {
    loadStats();
    loadEntries();
    loadSharedKnowledge();
  };

  if (agentsLoading) {
    return (
      <PageContainer
        title="Agent Memory"
        description="Explore and manage agent memory tiers"
        breadcrumbs={[
          { label: 'Dashboard', href: '/app' },
          { label: 'AI', href: '/app/ai' },
          { label: 'Memory Explorer' },
        ]}
      >
        <LoadingSpinner size="lg" className="py-12" message="Loading agents..." />
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title="Agent Memory"
      description="Explore and manage agent memory tiers"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'AI', href: '/app/ai' },
        { label: 'Memory Explorer' },
      ]}
      actions={[
        {
          label: 'Refresh',
          icon: RefreshCw,
          variant: 'outline',
          onClick: handleRefresh,
        },
      ]}
    >
      {/* Agent Selector */}
      <Card>
        <CardContent className="p-4">
          <div className="flex items-center gap-3">
            <Brain className="h-5 w-5 text-theme-primary shrink-0" />
            <label className="text-sm font-medium text-theme-secondary shrink-0">Agent:</label>
            <select
              value={selectedAgentId}
              onChange={(e) => setSelectedAgentId(e.target.value)}
              className="flex-1 text-sm rounded-lg bg-theme-surface border border-theme-border text-theme-primary py-2 px-3 focus:outline-none focus:ring-2 focus:ring-theme-primary"
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
      <MemoryStatsBar stats={stats} loading={statsLoading} />

      {/* Tier Tabs + Entries */}
      <Card>
        <MemoryTierTabs
          activeTier={activeTier}
          onTierChange={setActiveTier}
          stats={stats}
        />
        <CardContent className="p-4">
          {entriesLoading ? (
            <LoadingSpinner className="py-8" message="Loading entries..." />
          ) : entries.length === 0 ? (
            <EmptyState
              icon={Brain}
              title={`No ${activeTier.replace('_', ' ')} memory entries`}
              description="Memory entries will appear here as the agent operates"
            />
          ) : (
            <div className="space-y-3">
              {entries.map((entry, idx) => (
                <MemoryEntryCard
                  key={entry.id || `${entry.key}-${idx}`}
                  entry={entry}
                  onDelete={handleDelete}
                />
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      {/* Shared Knowledge Section */}
      <SharedKnowledgeList
        entries={sharedKnowledge}
        loading={sharedLoading}
      />
    </PageContainer>
  );
};
