import React, { useState, useEffect, useCallback } from 'react';
import { Brain, Lightbulb, Eraser } from 'lucide-react';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useRefreshAction } from '@/shared/hooks/useRefreshAction';
import { agentsApi } from '@/shared/services/ai';
import { MemoryStats } from './AgentMemoryStats';
import { MemoryTimeline } from './MemoryTimeline';
import { SharedLearningsPanel } from './SharedLearningsPanel';
import { fetchMemoryStats, deleteMemory } from '../api/memoryApi';
import { contextApi } from '../api/contextApi';
import type { PageAction } from '@/shared/components/layout/PageContainer';
import type { AiAgent } from '@/shared/types/ai';
import type { MemoryStats as MemoryStatsType, MemoryTier, MemoryEntry } from '../types/memory';

interface AgentMemoryContentProps {
  onActionsReady?: (actions: PageAction[]) => void;
}

export const AgentMemoryContent: React.FC<AgentMemoryContentProps> = ({ onActionsReady }) => {
  const { addNotification } = useNotifications();
  const [agents, setAgents] = useState<AiAgent[]>([]);
  const [agentsLoading, setAgentsLoading] = useState(true);
  const [selectedAgentId, setSelectedAgentId] = useState('');
  const [refreshKey, setRefreshKey] = useState(0);
  const [stats, setStats] = useState<MemoryStatsType | undefined>();
  const [activeTier, setActiveTier] = useState<MemoryTier>('short_term');

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

  const loadStats = useCallback(async () => {
    if (!selectedAgentId) return;
    try {
      const data = await fetchMemoryStats(selectedAgentId);
      setStats(data);
    } catch (_error) {
      // Stats failure is non-critical — sidebar will fall back to its own fetch
    }
  }, [selectedAgentId]);

  useEffect(() => {
    loadStats();
  }, [loadStats]);

  const handleRefresh = useCallback(() => {
    setRefreshKey((k) => k + 1);
    loadStats();
  }, [loadStats]);

  const { refreshAction } = useRefreshAction({ onRefresh: handleRefresh });

  const handleClearMemory = useCallback(async () => {
    if (!selectedAgentId) return;
    if (!window.confirm('Clear all memory for this agent? This cannot be undone.')) return;
    try {
      const result = await contextApi.clearAgentMemory(selectedAgentId);
      if (result.success) {
        addNotification({
          type: 'success',
          message: `Cleared ${result.cleared ?? 0} memory entries`,
        });
        handleRefresh();
      } else {
        addNotification({ type: 'error', message: result.error || 'Failed to clear memory' });
      }
    } catch (_error) {
      addNotification({ type: 'error', message: 'Failed to clear memory' });
    }
  }, [selectedAgentId, addNotification, handleRefresh]);

  const handleDeleteEntry = useCallback(async (entry: MemoryEntry) => {
    if (!selectedAgentId) return;
    try {
      await deleteMemory({
        agent_id: selectedAgentId,
        key: entry.key,
        tier: entry.tier,
        session_id: entry.session_id,
      });
      addNotification({ type: 'success', message: `Deleted memory entry "${entry.key}"` });
      handleRefresh();
    } catch (_error) {
      addNotification({ type: 'error', message: 'Failed to delete memory entry' });
    }
  }, [selectedAgentId, addNotification, handleRefresh]);

  const handleTierClick = useCallback((tier: MemoryTier) => {
    setActiveTier(tier);
  }, []);

  useEffect(() => {
    if (onActionsReady) {
      onActionsReady([
        {
          label: 'Clear Memory',
          onClick: handleClearMemory,
          icon: Eraser,
          variant: 'danger' as const,
        },
        refreshAction,
      ]);
    }
  }, [onActionsReady, refreshAction, handleClearMemory]);

  if (agentsLoading) {
    return <LoadingSpinner size="lg" className="py-12" message="Loading agents..." />;
  }

  return (
    <div className="space-y-6">
      {/* Intro callout */}
      <div className="rounded-lg border border-theme-border bg-theme-surface/50 p-4">
        <div className="flex items-start gap-3">
          <Lightbulb className="w-5 h-5 text-theme-warning shrink-0 mt-0.5" />
          <div className="text-sm text-theme-secondary">
            <p className="font-medium text-theme-primary mb-1">Agent Memory</p>
            <p>
              Agent memory captures knowledge across executions in four tiers:
              {' '}<strong>Working</strong> (ephemeral session data),
              {' '}<strong>Short-Term</strong> (recent context with TTL),
              {' '}<strong>Long-Term</strong> (persisted by access patterns), and
              {' '}<strong>Shared</strong> (cross-agent knowledge).
            </p>
          </div>
        </div>
      </div>

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

      {selectedAgentId && (
        <>
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
            <div className="lg:col-span-2">
              <MemoryTimeline
                key={`timeline-${refreshKey}`}
                agentId={selectedAgentId}
                stats={stats}
                tier={activeTier}
                onTierChange={setActiveTier}
                onDeleteEntry={handleDeleteEntry}
              />
            </div>
            <div className="space-y-6">
              <MemoryStats
                key={`stats-${refreshKey}`}
                agentId={selectedAgentId}
                stats={stats}
                onTierClick={handleTierClick}
              />
              <SharedLearningsPanel />
            </div>
          </div>
        </>
      )}
    </div>
  );
};
