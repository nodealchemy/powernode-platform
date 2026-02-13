import { useState, useEffect, useMemo, useCallback } from 'react';
import { Link } from 'react-router-dom';
import { Archive, ArchiveRestore, Copy } from 'lucide-react';
import { contextApi } from '../api/contextApi';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import type { AiPersistentContextSummary, ContextType, ContextScope } from '../types/context';

interface ContextBrowserProps {
  onSelect?: (context: AiPersistentContextSummary) => void;
  selectedId?: string;
  filters?: {
    context_type?: ContextType;
    scope?: ContextScope;
    ai_agent_id?: string;
  };
  showArchived?: boolean;
  linkToDetail?: boolean;
}

export function ContextBrowser({
  onSelect,
  selectedId,
  filters,
  showArchived: showArchivedProp = false,
  linkToDetail = true,
}: ContextBrowserProps) {
  const { showNotification } = useNotifications();
  const { confirm, ConfirmationDialog } = useConfirmation();
  const [contexts, setContexts] = useState<AiPersistentContextSummary[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [typeFilter, setTypeFilter] = useState<ContextType | ''>(filters?.context_type || '');
  const [scopeFilter, setScopeFilter] = useState<ContextScope | ''>(filters?.scope || '');
  const [showArchived, setShowArchived] = useState(showArchivedProp);
  const [cloneTargetId, setCloneTargetId] = useState<string | null>(null);
  const [cloneName, setCloneName] = useState('');

  useEffect(() => {
    loadContexts();
  }, [showArchived]);

  const loadContexts = async () => {
    setIsLoading(true);
    const response = await contextApi.getContexts(1, 100, {
      ...filters,
      is_archived: showArchived,
    });
    if (response.success && response.data) {
      setContexts(response.data.contexts);
    }
    setIsLoading(false);
  };

  const handleArchive = useCallback((id: string, e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    const ctxName = contexts.find(c => c.id === id)?.name || 'this context';
    confirm({
      title: 'Archive Context',
      message: `Are you sure you want to archive "${ctxName}"? It can be restored later from the archived view.`,
      confirmLabel: 'Archive',
      variant: 'warning',
      onConfirm: async () => {
        const response = await contextApi.archiveContext(id);
        if (response.success) {
          showNotification('Context archived', 'success');
          loadContexts();
        } else {
          showNotification(response.error || 'Failed to archive', 'error');
        }
      },
    });
  }, [showNotification, contexts, confirm]);

  const handleRestore = useCallback(async (id: string, e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    const response = await contextApi.restoreContext(id);
    if (response.success) {
      showNotification('Context restored', 'success');
      loadContexts();
    } else {
      showNotification(response.error || 'Failed to restore', 'error');
    }
  }, [showNotification]);

  const handleClone = useCallback(async () => {
    if (!cloneTargetId || !cloneName.trim()) return;
    const response = await contextApi.cloneContext(cloneTargetId, cloneName);
    if (response.success) {
      showNotification('Context cloned', 'success');
      setCloneTargetId(null);
      setCloneName('');
      loadContexts();
    } else {
      showNotification(response.error || 'Failed to clone', 'error');
    }
  }, [cloneTargetId, cloneName, showNotification]);

  const filteredContexts = useMemo(() => {
    return contexts.filter((ctx) => {
      const matchesSearch =
        !searchQuery ||
        ctx.name.toLowerCase().includes(searchQuery.toLowerCase());
      const matchesType = !typeFilter || ctx.context_type === typeFilter;
      const matchesScope = !scopeFilter || ctx.scope === scopeFilter;
      return matchesSearch && matchesType && matchesScope;
    });
  }, [contexts, searchQuery, typeFilter, scopeFilter]);

  const contextTypes: { value: ContextType | ''; label: string }[] = [
    { value: '', label: 'All Types' },
    { value: 'agent_memory', label: 'Agent Memory' },
    { value: 'knowledge_base', label: 'Knowledge Base' },
    { value: 'shared_context', label: 'Shared Context' },
  ];

  const contextScopes: { value: ContextScope | ''; label: string }[] = [
    { value: '', label: 'All Scopes' },
    { value: 'account', label: 'Account' },
    { value: 'agent', label: 'Agent' },
    { value: 'team', label: 'Team' },
    { value: 'workflow', label: 'Workflow' },
  ];

  const renderContextCard = (context: AiPersistentContextSummary) => {
    const content = (
      <div
        className={`p-4 bg-theme-surface border rounded-lg transition-colors ${
          selectedId === context.id
            ? 'border-theme-interactive-primary bg-theme-surface-selected'
            : 'border-theme hover:border-theme-secondary'
        } ${onSelect ? 'cursor-pointer' : ''}`}
        onClick={() => onSelect?.(context)}
      >
        <div className="flex items-start gap-3">
          <div className="text-2xl">
            {contextApi.getContextTypeIcon(context.context_type)}
          </div>
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2">
              <h3 className="font-medium text-theme-primary truncate">
                {context.name}
              </h3>
              {context.is_archived && (
                <span className="px-1.5 py-0.5 text-xs bg-theme-surface text-theme-tertiary rounded">
                  Archived
                </span>
              )}
            </div>
            <div className="flex items-center gap-2 mt-1 text-sm text-theme-secondary">
              <span>{contextApi.getContextTypeLabel(context.context_type)}</span>
              <span>•</span>
              <span>{contextApi.getScopeLabel(context.scope)}</span>
            </div>
            <div className="flex items-center gap-4 mt-2 text-xs text-theme-tertiary">
              <span>{context.entry_count} entries</span>
              <span>{contextApi.formatBytes(context.data_size_bytes)}</span>
              {context.last_accessed_at && (
                <span>
                  Last accessed {new Date(context.last_accessed_at).toLocaleDateString()}
                </span>
              )}
            </div>
            {context.ai_agent && (
              <div className="mt-2 text-xs text-theme-secondary">
                Agent: {context.ai_agent.name}
              </div>
            )}
            {/* Card Actions */}
            <div className="flex items-center gap-1 mt-3 pt-2 border-t border-theme">
              <button
                onClick={(e) => {
                  e.preventDefault();
                  e.stopPropagation();
                  setCloneTargetId(context.id);
                  setCloneName(`${context.name} (Copy)`);
                }}
                className="p-1 text-theme-tertiary hover:text-theme-primary transition-colors"
                title="Clone context"
              >
                <Copy size={14} />
              </button>
              {context.is_archived ? (
                <button
                  onClick={(e) => handleRestore(context.id, e)}
                  className="p-1 text-theme-tertiary hover:text-theme-success transition-colors"
                  title="Restore context"
                >
                  <ArchiveRestore size={14} />
                </button>
              ) : (
                <button
                  onClick={(e) => handleArchive(context.id, e)}
                  className="p-1 text-theme-tertiary hover:text-theme-warning transition-colors"
                  title="Archive context"
                >
                  <Archive size={14} />
                </button>
              )}
            </div>
          </div>
        </div>
      </div>
    );

    if (linkToDetail && !onSelect) {
      return (
        <Link key={context.id} to={`/app/ai/contexts/${context.id}`}>
          {content}
        </Link>
      );
    }

    return <div key={context.id}>{content}</div>;
  };

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-12">
        <div className="animate-spin rounded-full h-8 w-8 border-2 border-theme-primary border-t-transparent" />
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {/* Filters */}
      <div className="flex flex-col sm:flex-row gap-3">
        <div className="flex-1">
          <Input
            type="text"
            placeholder="Search contexts..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
          />
        </div>
        <Select
          value={typeFilter}
          onChange={(value) => setTypeFilter(value as ContextType | '')}
          options={contextTypes}
          fullWidth={false}
          className="min-w-[140px]"
        />
        <Select
          value={scopeFilter}
          onChange={(value) => setScopeFilter(value as ContextScope | '')}
          options={contextScopes}
          fullWidth={false}
          className="min-w-[140px]"
        />
        <button
          onClick={() => setShowArchived(!showArchived)}
          className={`px-3 py-2 text-sm rounded-md border transition-colors ${
            showArchived
              ? 'bg-theme-info/10 text-theme-info border-theme-info/30'
              : 'bg-theme-surface text-theme-secondary border-theme hover:text-theme-primary'
          }`}
        >
          <Archive size={14} className="inline mr-1" />
          {showArchived ? 'Showing Archived' : 'Show Archived'}
        </button>
      </div>

      {/* Results */}
      {filteredContexts.length === 0 ? (
        <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
          <div className="text-4xl mb-4">📦</div>
          <p className="text-theme-secondary">No contexts found</p>
          {(searchQuery || typeFilter || scopeFilter) && (
            <button
              onClick={() => {
                setSearchQuery('');
                setTypeFilter('');
                setScopeFilter('');
              }}
              className="mt-2 text-sm text-theme-primary hover:underline"
            >
              Clear filters
            </button>
          )}
        </div>
      ) : (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
          {filteredContexts.map(renderContextCard)}
        </div>
      )}

      {ConfirmationDialog}

      {/* Clone Modal */}
      {cloneTargetId && (
        <div className="fixed inset-0 bg-theme-bg/80 flex items-center justify-center z-50 p-4">
          <div className="bg-theme-surface rounded-lg border border-theme w-full max-w-md p-6">
            <h3 className="text-lg font-medium text-theme-primary mb-4">Clone Context</h3>
            <div className="mb-4">
              <label className="block text-sm font-medium text-theme-primary mb-1">New Name</label>
              <input
                type="text"
                value={cloneName}
                onChange={(e) => setCloneName(e.target.value)}
                className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
                autoFocus
              />
            </div>
            <div className="flex justify-end gap-3">
              <button
                onClick={() => { setCloneTargetId(null); setCloneName(''); }}
                className="btn-theme btn-theme-secondary"
              >
                Cancel
              </button>
              <button
                onClick={handleClone}
                disabled={!cloneName.trim()}
                className="btn-theme btn-theme-primary"
              >
                Clone
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
