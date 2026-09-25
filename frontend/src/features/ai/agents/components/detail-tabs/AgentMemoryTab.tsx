import React, { useState, useEffect, useCallback } from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import { Brain, Database, Plus, Trash2 } from 'lucide-react';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { MemoryViewer } from '@/features/ai/memory/components/MemoryViewer';
import { EntryEditor } from '@/features/ai/memory/components/EntryEditor';
import { contextApi } from '@/features/ai/memory/api/contextApi';
import { agentMemoryApiService } from '@/shared/services/ai/AgentMemoryApiService';
import type { AiContextEntry, AiPersistentContextSummary } from '@/features/ai/memory/types/context';

interface MemoryPool {
  id: string;
  name: string;
  pool_type: string;
  entry_count: number;
  created_at: string;
}

const MemoryPoolsPanel: React.FC = () => {
  const [pools, setPools] = useState<MemoryPool[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const load = async () => {
      try {
        setError(null);
        const result = await agentMemoryApiService.getMemoryPools();
        setPools((result.items || []) as unknown as MemoryPool[]);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Failed to load memory pools');
      } finally {
        setLoading(false);
      }
    };
    load();
  }, []);

  if (loading) return <LoadingSpinner size="md" className="py-12" />;

  if (error) {
    return (
      <div className="rounded-lg border border-theme-error-border/30 bg-theme-error-fg/5 p-4">
        <p className="text-sm text-theme-error-fg">{error}</p>
      </div>
    );
  }

  if (pools.length === 0) {
    return (
      <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
        <Database size={48} className="mx-auto text-theme-secondary mb-4" />
        <h3 className="text-lg font-semibold text-theme-primary mb-2">No Memory Pools</h3>
        <p className="text-theme-secondary">Shared memory pools will appear here once created</p>
      </div>
    );
  }

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
      {pools.map(pool => (
        <div key={pool.id} className="bg-theme-surface border border-theme rounded-lg p-4">
          <div className="flex items-center gap-2 mb-2">
            <Database className="h-4 w-4 text-theme-primary" />
            <h4 className="text-sm font-semibold text-theme-primary">{pool.name}</h4>
          </div>
          <div className="text-xs text-theme-secondary space-y-1">
            <p>Type: {pool.pool_type}</p>
            <p>Entries: {pool.entry_count}</p>
          </div>
        </div>
      ))}
    </div>
  );
};

/**
 * The agent detail page's Memory tab: the agent's own memory (its
 * PersistentContext, "Agent Memory") and the shared memory pools, each at its
 * own path under /app/ai/agents/:id/memory.
 */
export const AgentMemoryTab: React.FC<{ agentId: string }> = ({ agentId }) => {
  const navigate = useNavigate();
  const location = useLocation();
  const { showNotification } = useNotifications();
  const { hasPermission } = usePermissions();
  const { confirm, ConfirmationDialog } = useConfirmation();

  const [context, setContext] = useState<AiPersistentContextSummary | null>(null);
  const [loading, setLoading] = useState(true);
  const [editingEntry, setEditingEntry] = useState<AiContextEntry | null>(null);
  const [isCreating, setIsCreating] = useState(false);
  const [refreshKey, setRefreshKey] = useState(0);

  const basePath = `/app/ai/agents/${agentId}/memory`;
  const tabs = [
    { id: 'agent', label: 'Agent Memory', icon: <Brain size={16} />, path: '/' },
    // MemoryPoolsController reads need ai.memory_pools.read.
    { id: 'pools', label: 'Memory Pools', icon: <Database size={16} />, path: '/pools', permissions: ['ai.memory_pools.read'] },
  ];
  const canReadPools = hasPermission('ai.memory_pools.read');
  const activeTab = canReadPools && location.pathname.startsWith(`${basePath}/pools`) ? 'pools' : 'agent';

  const loadContext = useCallback(async () => {
    setLoading(true);
    try {
      const memoryResponse = await contextApi.getAgentMemory(agentId);
      if (memoryResponse.success && memoryResponse.data) {
        // Backend returns { memory, entries } — map memory to context summary
        const mem = memoryResponse.data as Record<string, unknown>;
        const memorySummary = mem.memory as Record<string, unknown> | null;
        if (memorySummary) {
          setContext({
            id: String(memorySummary.id || ''),
            name: String(memorySummary.name || ''),
            context_type: (memorySummary.context_type as AiPersistentContextSummary['context_type']) || 'agent_memory',
            scope: (memorySummary.scope as AiPersistentContextSummary['scope']) || 'agent',
            entry_count: (memorySummary.entry_count as number) || 0,
            data_size_bytes: (memorySummary.data_size_bytes as number) || 0,
            is_archived: false,
            last_accessed_at: memorySummary.last_accessed_at as string | undefined,
          });
        }
      }
    } catch {
      showNotification('Failed to load agent memory', 'error');
    }
    setLoading(false);
  }, [agentId, showNotification]);

  useEffect(() => {
    loadContext();
  }, [loadContext]);

  const closeEditor = () => {
    setEditingEntry(null);
    setIsCreating(false);
  };

  const handleClearMemory = () => {
    confirm({
      title: 'Clear Agent Memory',
      message: 'Are you sure you want to clear all memories for this agent?',
      confirmLabel: 'Clear All',
      variant: 'danger',
      onConfirm: async () => {
        const response = await contextApi.clearAgentMemory(agentId);
        if (response.success) {
          showNotification(`Cleared ${response.cleared || 0} memories`, 'success');
          setRefreshKey((k) => k + 1);
        } else {
          showNotification(response.error || 'Failed to clear memory', 'error');
        }
      },
    });
  };

  const handleEntrySave = (_entry: AiContextEntry) => {
    showNotification(editingEntry ? 'Memory updated' : 'Memory added', 'success');
    closeEditor();
    setRefreshKey((k) => k + 1);
  };

  const handleEntryDelete = async (entryId: string) => {
    if (!context) return;
    confirm({
      title: 'Delete Memory',
      message: 'Are you sure you want to delete this memory?',
      confirmLabel: 'Delete',
      variant: 'danger',
      onConfirm: async () => {
        const response = await contextApi.deleteEntry(context.id, entryId);
        if (response.success) {
          showNotification('Memory deleted', 'success');
          closeEditor();
          setRefreshKey((k) => k + 1);
        } else {
          showNotification(response.error || 'Failed to delete memory', 'error');
        }
      },
    });
  };

  const renderAgentMemory = () => {
    if (loading) return <LoadingSpinner size="md" className="py-12" message="Loading agent memory..." />;

    if (editingEntry || isCreating) {
      return context ? (
        <div className="max-w-2xl mx-auto bg-theme-surface border border-theme rounded-lg p-6">
          <EntryEditor
            entry={editingEntry || undefined}
            contextId={context.id}
            onSave={handleEntrySave}
            onCancel={closeEditor}
            onDelete={editingEntry ? handleEntryDelete : undefined}
          />
        </div>
      ) : null;
    }

    return (
      <div className="space-y-6">
        <div className="flex items-center justify-end gap-2">
          <Button variant="danger" size="sm" onClick={handleClearMemory}>
            <Trash2 className="h-3.5 w-3.5 mr-1" />
            Clear All
          </Button>
          <Button variant="primary" size="sm" onClick={() => setIsCreating(true)}>
            <Plus className="h-3.5 w-3.5 mr-1" />
            Add Memory
          </Button>
        </div>

        {context && (
          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                <Brain className="h-6 w-6 text-theme-primary" />
                <div>
                  <h3 className="font-medium text-theme-primary">{context.name}</h3>
                  <p className="text-sm text-theme-secondary">
                    {context.entry_count} entries •{' '}
                    {contextApi.formatBytes(context.data_size_bytes)}
                  </p>
                </div>
              </div>
              <button
                type="button"
                onClick={() => navigate(`/app/ai/knowledge/contexts/${context.id}`)}
                className="px-4 py-2 text-sm text-theme-secondary hover:text-theme-primary transition-colors"
              >
                View Full Context
              </button>
            </div>
          </div>
        )}

        <MemoryViewer
          key={refreshKey}
          agentId={agentId}
          onEntrySelect={(entry) => setEditingEntry(entry)}
          onAddEntry={() => setIsCreating(true)}
        />
      </div>
    );
  };

  return (
    <>
      <TabContainer tabs={tabs} activeTab={activeTab} basePath={basePath} variant="pills" size="sm" className="mb-4">
        <TabPanel tabId="agent" activeTab={activeTab}>{renderAgentMemory()}</TabPanel>
        <TabPanel tabId="pools" activeTab={activeTab}>
          <MemoryPoolsPanel />
        </TabPanel>
      </TabContainer>
      {ConfirmationDialog}
    </>
  );
};
