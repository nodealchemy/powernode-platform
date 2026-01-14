import { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { MemoryViewer } from '@/features/ai/context/components/MemoryViewer';
import { EntryEditor } from '@/features/ai/context/components/EntryEditor';
import { contextApi } from '@/features/ai/context/services/contextApi';
import { useNotifications } from '@/shared/hooks/useNotifications';
import type { AiContextEntry, AiAgentSummary, AiPersistentContextSummary } from '@/features/ai/context/types';

export function AgentMemoryPage() {
  const { agentId } = useParams<{ agentId: string }>();
  const navigate = useNavigate();
  const { showNotification } = useNotifications();
  const [agent, setAgent] = useState<AiAgentSummary | null>(null);
  const [context, setContext] = useState<AiPersistentContextSummary | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [editingEntry, setEditingEntry] = useState<AiContextEntry | null>(null);
  const [isCreating, setIsCreating] = useState(false);
  const [refreshKey, setRefreshKey] = useState(0);

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
    const response = await contextApi.getAgentMemory(agentId);
    if (response.success && response.data) {
      setAgent(response.data.agent);
      setContext(response.data.context);
    } else {
      showNotification(response.error || 'Failed to load agent memory', 'error');
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
      <div className="space-y-6">
        {/* Context Info */}
        {context && (
          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                <div className="text-2xl">🧠</div>
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
    </PageContainer>
  );
}
