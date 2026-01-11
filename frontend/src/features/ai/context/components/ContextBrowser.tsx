import { useState, useEffect, useMemo } from 'react';
import { Link } from 'react-router-dom';
import { contextApi } from '../services/contextApi';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';
import type { AiPersistentContextSummary, ContextType, ContextScope } from '../types';

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
  showArchived = false,
  linkToDetail = true,
}: ContextBrowserProps) {
  const [contexts, setContexts] = useState<AiPersistentContextSummary[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [typeFilter, setTypeFilter] = useState<ContextType | ''>(filters?.context_type || '');
  const [scopeFilter, setScopeFilter] = useState<ContextScope | ''>(filters?.scope || '');

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
    </div>
  );
}
