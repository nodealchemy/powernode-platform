import { useState, useEffect, useCallback } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { EntryEditor } from '@/features/ai/context/components/EntryEditor';
import { SearchResults } from '@/features/ai/context/components/SearchResults';
import { ImportExportModal } from '@/features/ai/context/components/ImportExportModal';
import { contextApi } from '@/features/ai/context/services/contextApi';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import type {
  AiPersistentContext,
  AiContextEntrySummary,
  AiContextEntry,
  ContextStatsResponse,
  EntryType,
} from '@/features/ai/context/types';

export function ContextDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { showNotification } = useNotifications();

  // WebSocket for real-time updates
  const { isConnected: _wsConnected } = usePageWebSocket({
    pageType: 'ai',
    onDataUpdate: () => {
      // Trigger data refresh if needed
    }
  });

  const [context, setContext] = useState<AiPersistentContext | null>(null);
  const [entries, setEntries] = useState<AiContextEntrySummary[]>([]);
  const [stats, setStats] = useState<ContextStatsResponse['data'] | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [activeTab, setActiveTab] = useState<'entries' | 'search' | 'settings'>('entries');
  const [editingEntry, setEditingEntry] = useState<AiContextEntry | null>(null);
  const [isCreating, setIsCreating] = useState(false);
  const [showImportExport, setShowImportExport] = useState(false);
  const [selectedType, setSelectedType] = useState<EntryType | ''>('');
  const [searchQuery, setSearchQuery] = useState('');

  useEffect(() => {
    if (id) {
      loadContext();
      loadEntries();
      loadStats();
    }
  }, [id]);

  useEffect(() => {
    if (id) {
      loadEntries();
    }
  }, [selectedType, searchQuery]);

  const loadContext = async () => {
    if (!id) return;
    setIsLoading(true);
    const response = await contextApi.getContext(id);
    if (response.success && response.data) {
      setContext(response.data.context);
    } else {
      showNotification(response.error || 'Failed to load context', 'error');
    }
    setIsLoading(false);
  };

  const loadEntries = async () => {
    if (!id) return;
    const response = await contextApi.getEntries(id, 1, 100, {
      entry_type: selectedType || undefined,
      q: searchQuery || undefined,
    });
    if (response.success && response.data) {
      setEntries(response.data.entries);
    }
  };

  const loadStats = async () => {
    if (!id) return;
    const response = await contextApi.getContextStats(id);
    if (response.success && response.data) {
      setStats(response.data);
    }
  };

  const handleArchive = useCallback(async () => {
    if (!id || !confirm('Are you sure you want to archive this context?')) return;
    const response = await contextApi.archiveContext(id);
    if (response.success) {
      showNotification('Context archived', 'success');
      loadContext();
    } else {
      showNotification(response.error || 'Failed to archive context', 'error');
    }
  }, [id, showNotification]);

  const handleRestore = useCallback(async () => {
    if (!id) return;
    const response = await contextApi.restoreContext(id);
    if (response.success) {
      showNotification('Context restored', 'success');
      loadContext();
    } else {
      showNotification(response.error || 'Failed to restore context', 'error');
    }
  }, [id, showNotification]);

  const handleDelete = useCallback(async () => {
    if (!id || !confirm('Are you sure you want to permanently delete this context? This cannot be undone.')) {
      return;
    }
    const response = await contextApi.deleteContext(id);
    if (response.success) {
      showNotification('Context deleted', 'success');
      navigate('/app/ai/contexts');
    } else {
      showNotification(response.error || 'Failed to delete context', 'error');
    }
  }, [id, navigate, showNotification]);

  const handleEntrySave = (_entry: AiContextEntry) => {
    showNotification(editingEntry ? 'Entry updated' : 'Entry created', 'success');
    setEditingEntry(null);
    setIsCreating(false);
    loadEntries();
    loadStats();
  };

  const handleEntryDelete = async (entryId: string) => {
    if (!id || !confirm('Are you sure you want to delete this entry?')) return;
    const response = await contextApi.deleteEntry(id, entryId);
    if (response.success) {
      showNotification('Entry deleted', 'success');
      setEditingEntry(null);
      loadEntries();
      loadStats();
    } else {
      showNotification(response.error || 'Failed to delete entry', 'error');
    }
  };

  const handleExpandEntry = async (entry: AiContextEntrySummary) => {
    if (!id) return;
    const response = await contextApi.getEntry(id, entry.id);
    if (response.success && response.data) {
      setEditingEntry(response.data.entry);
    }
  };

  const entryTypes: { value: EntryType | ''; label: string }[] = [
    { value: '', label: 'All Types' },
    { value: 'fact', label: 'Facts' },
    { value: 'preference', label: 'Preferences' },
    { value: 'interaction', label: 'Interactions' },
    { value: 'knowledge', label: 'Knowledge' },
    { value: 'skill', label: 'Skills' },
    { value: 'relationship', label: 'Relationships' },
    { value: 'goal', label: 'Goals' },
    { value: 'constraint', label: 'Constraints' },
  ];

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'AI', href: '/app/ai' },
    { label: 'Contexts', href: '/app/ai/contexts' },
    { label: context?.name || 'Context Details' }
  ];

  if (isLoading) {
    return (
      <PageContainer title="Loading..." description="" breadcrumbs={breadcrumbs}>
        <div className="flex items-center justify-center py-12">
          <div className="animate-spin rounded-full h-8 w-8 border-2 border-theme-primary border-t-transparent" />
        </div>
      </PageContainer>
    );
  }

  if (!context) {
    return (
      <PageContainer title="Context Not Found" description="" breadcrumbs={breadcrumbs}>
        <div className="text-center py-12">
          <p className="text-theme-secondary">The context you're looking for doesn't exist.</p>
          <button
            onClick={() => navigate('/app/ai/contexts')}
            className="mt-4 text-theme-primary hover:underline"
          >
            Back to Knowledge Base
          </button>
        </div>
      </PageContainer>
    );
  }

  // Entry editor view
  if (editingEntry || isCreating) {
    return (
      <PageContainer
        title={editingEntry ? 'Edit Entry' : 'New Entry'}
        description={context.name}
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
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title={context.name}
      description={contextApi.getContextTypeLabel(context.context_type)}
      breadcrumbs={breadcrumbs}
      actions={[
        {
          label: 'Import/Export',
          onClick: () => setShowImportExport(true),
          variant: 'secondary',
        },
        {
          label: 'Add Entry',
          onClick: () => setIsCreating(true),
          variant: 'primary',
        },
      ]}
    >
      <div className="space-y-6">
        {/* Header Info */}
        <div className="flex items-start gap-4">
          <div className="text-3xl">
            {contextApi.getContextTypeIcon(context.context_type)}
          </div>
          <div className="flex-1">
            <div className="flex items-center gap-2">
              <h2 className="text-xl font-semibold text-theme-primary">{context.name}</h2>
              {context.is_archived && (
                <span className="px-2 py-0.5 text-xs bg-theme-surface text-theme-tertiary rounded">
                  Archived
                </span>
              )}
            </div>
            {context.description && (
              <p className="text-theme-secondary mt-1">{context.description}</p>
            )}
            <div className="flex items-center gap-4 mt-2 text-sm text-theme-tertiary">
              <span>{contextApi.getScopeLabel(context.scope)}</span>
              <span>v{context.version}</span>
              {context.ai_agent && <span>Agent: {context.ai_agent.name}</span>}
            </div>
          </div>
        </div>

        {/* Stats */}
        {stats && (
          <div className="grid grid-cols-2 md:grid-cols-5 gap-4">
            <div className="bg-theme-surface border border-theme rounded-lg p-4">
              <p className="text-xs text-theme-tertiary">Total Entries</p>
              <p className="text-2xl font-semibold text-theme-primary mt-1">
                {stats.stats.total_entries}
              </p>
            </div>
            <div className="bg-theme-surface border border-theme rounded-lg p-4">
              <p className="text-xs text-theme-tertiary">Data Size</p>
              <p className="text-2xl font-semibold text-theme-primary mt-1">
                {contextApi.formatBytes(stats.stats.data_size_bytes)}
              </p>
            </div>
            <div className="bg-theme-surface border border-theme rounded-lg p-4">
              <p className="text-xs text-theme-tertiary">With Embeddings</p>
              <p className="text-2xl font-semibold text-theme-primary mt-1">
                {stats.stats.entries_with_embeddings}
              </p>
            </div>
            <div className="bg-theme-surface border border-theme rounded-lg p-4">
              <p className="text-xs text-theme-tertiary">Avg Importance</p>
              <p className="text-2xl font-semibold text-theme-primary mt-1">
                {(stats.stats.avg_importance_score * 100).toFixed(0)}%
              </p>
            </div>
            <div className="bg-theme-surface border border-theme rounded-lg p-4">
              <p className="text-xs text-theme-tertiary">Total Accesses</p>
              <p className="text-2xl font-semibold text-theme-primary mt-1">
                {stats.stats.access_count_total}
              </p>
            </div>
          </div>
        )}

        {/* Tabs */}
        <div className="border-b border-theme">
          <nav className="flex gap-6">
            {(['entries', 'search', 'settings'] as const).map((tab) => (
              <button
                key={tab}
                onClick={() => setActiveTab(tab)}
                className={`pb-3 text-sm font-medium border-b-2 transition-colors ${
                  activeTab === tab
                    ? 'border-theme-primary text-theme-primary'
                    : 'border-transparent text-theme-secondary hover:text-theme-primary'
                }`}
              >
                {tab.charAt(0).toUpperCase() + tab.slice(1)}
              </button>
            ))}
          </nav>
        </div>

        {/* Tab Content */}
        {activeTab === 'entries' && (
          <div className="space-y-4">
            {/* Filters */}
            <div className="flex gap-3">
              <input
                type="text"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder="Filter entries..."
                className="flex-1 px-4 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary placeholder-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary"
              />
              <select
                value={selectedType}
                onChange={(e) => setSelectedType(e.target.value as EntryType | '')}
                className="px-4 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
              >
                {entryTypes.map((type) => (
                  <option key={type.value} value={type.value}>
                    {type.label}
                  </option>
                ))}
              </select>
            </div>

            {/* Entries List */}
            {entries.length === 0 ? (
              <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                <div className="text-4xl mb-4">📄</div>
                <h3 className="text-lg font-medium text-theme-primary">No entries yet</h3>
                <p className="text-theme-secondary mt-1">Add your first entry to this context</p>
                <button
                  onClick={() => setIsCreating(true)}
                  className="mt-4 px-4 py-2 bg-theme-interactive-primary text-white rounded-lg hover:bg-theme-interactive-primary-hover transition-colors"
                >
                  Add Entry
                </button>
              </div>
            ) : (
              <div className="space-y-2">
                {entries.map((entry) => (
                  <button
                    key={entry.id}
                    onClick={() => handleExpandEntry(entry)}
                    className="w-full text-left p-4 bg-theme-surface border border-theme rounded-lg hover:border-theme-primary transition-colors"
                  >
                    <div className="flex items-start justify-between gap-3">
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2">
                          <span
                            className={`px-2 py-0.5 text-xs rounded ${contextApi.getEntryTypeColor(entry.entry_type)}`}
                          >
                            {contextApi.getEntryTypeLabel(entry.entry_type)}
                          </span>
                          <span className="font-mono text-sm text-theme-primary truncate">
                            {entry.key}
                          </span>
                        </div>
                        {entry.content_text && (
                          <p className="text-sm text-theme-secondary mt-1 line-clamp-2">
                            {entry.content_text}
                          </p>
                        )}
                        <div className="flex items-center gap-4 mt-2 text-xs text-theme-tertiary">
                          <span className={contextApi.getImportanceColor(entry.importance_score)}>
                            {contextApi.formatImportanceScore(entry.importance_score)}
                          </span>
                          <span>{entry.access_count} accesses</span>
                          {entry.tags.length > 0 && (
                            <span>{entry.tags.slice(0, 3).join(', ')}</span>
                          )}
                        </div>
                      </div>
                      <span className="text-theme-tertiary">→</span>
                    </div>
                  </button>
                ))}
              </div>
            )}
          </div>
        )}

        {activeTab === 'search' && <SearchResults contextId={context.id} />}

        {activeTab === 'settings' && (
          <div className="space-y-6 max-w-2xl">
            {/* Retention Policy */}
            <div className="bg-theme-surface border border-theme rounded-lg p-6">
              <h3 className="text-lg font-medium text-theme-primary mb-4">Retention Policy</h3>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <p className="text-xs text-theme-tertiary">Max Entries</p>
                  <p className="text-theme-primary">
                    {context.retention_policy?.max_entries || 'Unlimited'}
                  </p>
                </div>
                <div>
                  <p className="text-xs text-theme-tertiary">Max Age</p>
                  <p className="text-theme-primary">
                    {context.retention_policy?.max_age_days
                      ? `${context.retention_policy.max_age_days} days`
                      : 'Never expire'}
                  </p>
                </div>
                <div>
                  <p className="text-xs text-theme-tertiary">Auto Archive After</p>
                  <p className="text-theme-primary">
                    {context.retention_policy?.auto_archive_days
                      ? `${context.retention_policy.auto_archive_days} days`
                      : 'Never'}
                  </p>
                </div>
                <div>
                  <p className="text-xs text-theme-tertiary">Importance Threshold</p>
                  <p className="text-theme-primary">
                    {context.retention_policy?.importance_threshold
                      ? `${(context.retention_policy.importance_threshold * 100).toFixed(0)}%`
                      : 'None'}
                  </p>
                </div>
              </div>
            </div>

            {/* Danger Zone */}
            <div className="bg-theme-surface border border-theme-error rounded-lg p-6">
              <h3 className="text-lg font-medium text-theme-error mb-4">Danger Zone</h3>
              <div className="space-y-4">
                {context.is_archived ? (
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="font-medium text-theme-primary">Restore Context</p>
                      <p className="text-sm text-theme-secondary">
                        Make this context active again
                      </p>
                    </div>
                    <button
                      onClick={handleRestore}
                      className="px-4 py-2 bg-theme-interactive-primary text-white rounded-lg hover:bg-theme-interactive-primary-hover transition-colors"
                    >
                      Restore
                    </button>
                  </div>
                ) : (
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="font-medium text-theme-primary">Archive Context</p>
                      <p className="text-sm text-theme-secondary">
                        Hide from active list, can be restored later
                      </p>
                    </div>
                    <button
                      onClick={handleArchive}
                      className="px-4 py-2 bg-theme-warning text-white rounded-lg hover:bg-opacity-90 transition-colors"
                    >
                      Archive
                    </button>
                  </div>
                )}
                <div className="flex items-center justify-between pt-4 border-t border-theme">
                  <div>
                    <p className="font-medium text-theme-error">Delete Context</p>
                    <p className="text-sm text-theme-secondary">
                      Permanently delete this context and all entries
                    </p>
                  </div>
                  <button
                    onClick={handleDelete}
                    className="px-4 py-2 bg-theme-error text-white rounded-lg hover:bg-opacity-90 transition-colors"
                  >
                    Delete
                  </button>
                </div>
              </div>
            </div>
          </div>
        )}
      </div>

      {/* Import/Export Modal */}
      <ImportExportModal
        contextId={context.id}
        contextName={context.name}
        isOpen={showImportExport}
        onClose={() => setShowImportExport(false)}
        onComplete={() => {
          loadEntries();
          loadStats();
        }}
      />
    </PageContainer>
  );
}
