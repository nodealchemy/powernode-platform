import React, { useState, useEffect, useCallback } from 'react';
import { Lightbulb, Eraser } from 'lucide-react';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useRefreshAction } from '@/shared/hooks/useRefreshAction';
import { MemoryStats } from './AgentMemoryStats';
import { MemoryTimeline } from './MemoryTimeline';
import { SharedLearningsPanel } from './SharedLearningsPanel';
import { AgentSelectorCard } from './AgentSelectorCard';
import { deleteMemory } from '../api/memoryApi';
import { contextApi } from '../api/contextApi';
import { useAgentMemorySelection } from '../hooks/useAgentMemorySelection';
import type { PageAction } from '@/shared/components/layout/PageContainer';
import type { MemoryEntry } from '../types/memory';

interface AgentMemoryContentProps {
  onActionsReady?: (actions: PageAction[]) => void;
}

export const AgentMemoryContent: React.FC<AgentMemoryContentProps> = ({ onActionsReady }) => {
  const { addNotification } = useNotifications();
  const {
    agents,
    agentsLoading,
    selectedAgentId,
    handleAgentChange,
    stats,
    loadStats,
  } = useAgentMemorySelection();
  const [refreshKey, setRefreshKey] = useState(0);

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
      loadStats();
    } catch (_error) {
      addNotification({ type: 'error', message: 'Failed to delete memory entry' });
    }
  }, [selectedAgentId, addNotification, loadStats]);

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
      <div className="rounded-lg border border-theme bg-theme-surface/50 p-4">
        <div className="flex items-start gap-3">
          <Lightbulb className="w-5 h-5 text-theme-warning-fg shrink-0 mt-0.5" />
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
      <AgentSelectorCard
        agents={agents}
        selectedAgentId={selectedAgentId}
        onAgentChange={handleAgentChange}
      />

      {selectedAgentId && (
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <div className="lg:col-span-2">
            <MemoryTimeline
              key={`timeline-${selectedAgentId}-${refreshKey}`}
              agentId={selectedAgentId}
              stats={stats ?? undefined}
              onDeleteEntry={handleDeleteEntry}
            />
          </div>
          <div className="space-y-6">
            <MemoryStats
              key={`stats-${refreshKey}`}
              agentId={selectedAgentId}
              stats={stats ?? undefined}
            />
            <SharedLearningsPanel />
          </div>
        </div>
      )}
    </div>
  );
};
