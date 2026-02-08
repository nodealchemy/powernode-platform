import { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { ArrowLeft, Brain, Database } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { MemoryViewer } from '@/features/ai/context/components/MemoryViewer';
import { EntryEditor } from '@/features/ai/context/components/EntryEditor';
import { contextApi } from '@/features/ai/context/services/contextApi';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import { memoryApiService } from '@/shared/services/ai/MemoryApiService';
import { agentsApi } from '@/shared/services/ai';
import type { AiContextEntry, AiAgentSummary, AiPersistentContextSummary } from '@/features/ai/context/types';

interface MemoryPool {
  id: string;
  name: string;
  pool_type: string;
  entry_count: number;
  created_at: string;
}

function MemoryPoolsTab() {
  const [pools, setPools] = useState<MemoryPool[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const load = async () => {
      try {
        setError(null);
        const result = await memoryApiService.getMemoryPools();
        setPools((result.items || []) as unknown as MemoryPool[]);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Failed to load memory pools');
      } finally {
        setLoading(false);
      }
    };
    load();
  }, []);

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <div className="animate-spin rounded-full h-8 w-8 border-2 border-theme-primary border-t-transparent" />
      </div>
    );
  }

  if (error) {
    return (
      <div className="rounded-lg border border-theme-error/30 bg-theme-error/5 p-4">
        <p className="text-sm text-theme-error">{error}</p>
      </div>
    );
  }

  if (pools.length === 0) {
    return (
      <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
        <Database size={48} className="mx-auto text-theme-secondary mb-4" />
        <h3 className="text-lg font-semibold text-theme-primary mb-2">No Memory Pools</h3>
        <p className="text-theme-secondary">
          Shared memory pools will appear here once created
        </p>
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
}

export function AgentMemoryPage() {
  const { agentId } = useParams<{ agentId: string }>();
  const navigate = useNavigate();
  const { showNotification } = useNotifications();

  // WebSocket for real-time updates
  usePageWebSocket({
    pageType: 'ai',
    onDataUpdate: () => {
      // Trigger data refresh if needed
    }
  });

  const [agent, setAgent] = useState<AiAgentSummary | null>(null);
  const [context, setContext] = useState<AiPersistentContextSummary | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [editingEntry, setEditingEntry] = useState<AiContextEntry | null>(null);
  const [isCreating, setIsCreating] = useState(false);
  const [refreshKey, setRefreshKey] = useState(0);
  const [activeTab, setActiveTab] = useState<'agent' | 'pools'>('agent');

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'AI', href: '/app/ai' },
    { label: 'Agents', href: '/app/ai/agents' },
    { label: agent?.name || 'Memory' }
  ];

  useEffect(() => {
    if (agentId) {
      loadAgentMemory();
    }
  }, [agentId]);

  const loadAgentMemory = async () => {
    if (!agentId) return;
    setIsLoading(true);
    try {
      const [agentData, memoryResponse] = await Promise.all([
        agentsApi.getAgent(agentId),
        contextApi.getAgentMemory(agentId),
      ]);

      setAgent({ id: agentData.id, name: agentData.name, agent_type: agentData.agent_type });

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
    setIsLoading(false);
  };

  const handleClearMemory = async () => {
    if (!agentId || !confirm('Are you sure you want to clear all memories for this agent?')) {
      return;
    }

    const response = await contextApi.clearAgentMemory(agentId);
    if (response.success) {
      showNotification(`Cleared ${response.cleared || 0} memories`, 'success');
      setRefreshKey((k) => k + 1);
    } else {
      showNotification(response.error || 'Failed to clear memory', 'error');
    }
  };

  const handleEntrySave = (_entry: AiContextEntry) => {
    showNotification(editingEntry ? 'Memory updated' : 'Memory added', 'success');
    setEditingEntry(null);
    setIsCreating(false);
    setRefreshKey((k) => k + 1);
  };

  const handleEntryDelete = async (entryId: string) => {
    if (!context || !confirm('Are you sure you want to delete this memory?')) {
      return;
    }

    const response = await contextApi.deleteEntry(context.id, entryId);
    if (response.success) {
      showNotification('Memory deleted', 'success');
      setEditingEntry(null);
      setRefreshKey((k) => k + 1);
    } else {
      showNotification(response.error || 'Failed to delete memory', 'error');
    }
  };

  if (isLoading) {
    return (
      <PageContainer title="Loading..." description="" breadcrumbs={breadcrumbs}>
        <div className="flex items-center justify-center py-12">
          <div className="animate-spin rounded-full h-8 w-8 border-2 border-theme-primary border-t-transparent" />
        </div>
      </PageContainer>
    );
  }

  if (!agentId || !agent) {
    return (
      <PageContainer title="Agent Not Found" description="" breadcrumbs={breadcrumbs}>
        <div className="text-center py-12">
          <p className="text-theme-secondary">The agent you're looking for doesn't exist.</p>
          <button
            onClick={() => navigate('/app/ai/agents')}
            className="mt-4 text-theme-primary hover:underline"
          >
            Back to Agents
          </button>
        </div>
      </PageContainer>
    );
  }

  // Show editor modal
  if (editingEntry || isCreating) {
    return (
      <PageContainer
        title={editingEntry ? 'Edit Memory' : 'Add Memory'}
        description={agent.name}
        breadcrumbs={breadcrumbs}
        actions={[
          {
            label: 'Cancel',
            onClick: () => {
              setEditingEntry(null);
              setIsCreating(false);
            },
            variant: 'secondary',
          },
        ]}
      >
        {context && (
          <div className="max-w-2xl mx-auto bg-theme-surface border border-theme rounded-lg p-6">
            <EntryEditor
              entry={editingEntry || undefined}
              contextId={context.id}
              onSave={handleEntrySave}
              onCancel={() => {
                setEditingEntry(null);
                setIsCreating(false);
              }}
              onDelete={editingEntry ? handleEntryDelete : undefined}
            />
          </div>
        )}
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title={`${agent.name} Memory`}
      description="View and manage agent memories"
      breadcrumbs={breadcrumbs}
      actions={[
        {
          label: 'Back to Agent',
          onClick: () => navigate(`/app/ai/agents/${agentId}`),
          variant: 'secondary' as const,
          icon: ArrowLeft,
        },
        {
          label: 'Clear All',
          onClick: handleClearMemory,
          variant: 'danger',
        },
        {
          label: 'Add Memory',
          onClick: () => setIsCreating(true),
          variant: 'primary',
        },
      ]}
    >
      {/* Memory Tabs */}
      <div className="flex gap-1 mb-6 border-b border-theme">
        <button
          type="button"
          onClick={() => setActiveTab('agent')}
          className={`px-4 py-2 text-sm font-medium border-b-2 transition-colors ${
            activeTab === 'agent'
              ? 'border-theme-primary text-theme-primary'
              : 'border-transparent text-theme-secondary hover:text-theme-primary'
          }`}
        >
          <span className="flex items-center gap-2">
            <Brain size={16} />
            Agent Memory
          </span>
        </button>
        <button
          type="button"
          onClick={() => setActiveTab('pools')}
          className={`px-4 py-2 text-sm font-medium border-b-2 transition-colors ${
            activeTab === 'pools'
              ? 'border-theme-primary text-theme-primary'
              : 'border-transparent text-theme-secondary hover:text-theme-primary'
          }`}
        >
          <span className="flex items-center gap-2">
            <Database size={16} />
            Memory Pools
          </span>
        </button>
      </div>

      {activeTab === 'pools' ? (
        <MemoryPoolsTab />
      ) : (
      <div className="space-y-6">
        {/* Context Info */}
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
                onClick={() => navigate(`/app/ai/contexts/${context.id}`)}
                className="px-4 py-2 text-sm text-theme-secondary hover:text-theme-primary transition-colors"
              >
                View Full Context
              </button>
            </div>
          </div>
        )}

        {/* Memory Viewer */}
        <MemoryViewer
          key={refreshKey}
          agentId={agentId}
          onEntrySelect={(entry) => setEditingEntry(entry)}
          onAddEntry={() => setIsCreating(true)}
        />
      </div>
      )}
    </PageContainer>
  );
}
