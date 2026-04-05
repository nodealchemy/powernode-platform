import React, { useState, useCallback, useEffect, useMemo } from 'react';
import {
  Search, ChevronRight, ArrowDown, ArrowUp,
  Brain, Eye, Pencil, Copy, Pause, Play, Archive, MoreHorizontal,
  MessageSquare, Shield, Loader2,
} from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { DropdownMenu } from '@/shared/components/ui/DropdownMenu';
import { useAgentModal } from '@/shared/hooks/useAgentModal';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotification } from '@/shared/hooks/useNotification';
import { useChatWindow } from '@/features/ai/chat/context/ChatWindowContext';
import { agentsApi } from '@/shared/services/ai';
import { AgentExpandedRow } from './AgentExpandedRow';
import { EditAgentModal } from './EditAgentModal';
import {
  STATUS_CONFIG, STATUS_TABS, TAB_STATUS_MAP,
  AGENT_TYPE_LABELS, TRUST_CONFIG, SORT_OPTIONS,
  timeAgo,
} from '../constants/agentConstants';
import type { StatusTabId } from '../constants/agentConstants';
import { cn } from '@/shared/utils/cn';
import type { AiAgent } from '@/shared/types/ai';

export const AgentsIndexTable: React.FC = () => {
  const [agents, setAgents] = useState<AiAgent[]>([]);
  const [loading, setLoading] = useState(true);
  const [expandedRows, setExpandedRows] = useState<Set<string>>(new Set());
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState<StatusTabId>('all');
  const [sortBy, setSortBy] = useState('updated_at');
  const [sortOrder, setSortOrder] = useState<'asc' | 'desc'>('desc');
  const [typeFilter, setTypeFilter] = useState('');
  const [myAgentsOnly, setMyAgentsOnly] = useState(false);
  const [refreshKey, setRefreshKey] = useState(0);
  const [editAgent, setEditAgent] = useState<AiAgent | null>(null);

  const { openAgent } = useAgentModal();
  const { hasPermission } = usePermissions();
  const { showNotification } = useNotification();
  const { openConversationMaximized } = useChatWindow();

  const canManage = hasPermission('ai.agents.manage');

  // --- Data fetching ---

  const loadAgents = useCallback(async () => {
    try {
      setLoading(true);
      const response = await agentsApi.getAgents({
        per_page: 100,
        sort: sortBy,
        order: sortOrder,
        ...(myAgentsOnly ? { my_agents: true } : {}),
      });
      setAgents(response.items || []);
    } catch {
      // Silently fail — table will show empty state
    } finally {
      setLoading(false);
    }
  }, [sortBy, sortOrder, myAgentsOnly]);

  useEffect(() => {
    loadAgents();
  }, [loadAgents]);

  useEffect(() => {
    if (refreshKey > 0) {
      loadAgents();
    }
  }, [refreshKey, loadAgents]);

  // --- Filtering ---

  const filteredAgents = useMemo(() => {
    let filtered = agents;
    const statuses = TAB_STATUS_MAP[statusFilter];
    if (statuses) {
      filtered = filtered.filter(a => statuses.includes(a.status));
    }
    if (typeFilter) {
      filtered = filtered.filter(a => a.agent_type === typeFilter);
    }
    if (search.trim()) {
      const q = search.toLowerCase();
      filtered = filtered.filter(a =>
        a.name.toLowerCase().includes(q) ||
        (a.description && a.description.toLowerCase().includes(q)) ||
        (a.provider?.name && a.provider.name.toLowerCase().includes(q)) ||
        (a.model && a.model.toLowerCase().includes(q))
      );
    }
    return filtered;
  }, [agents, statusFilter, search, typeFilter]);

  // --- Handlers ---

  const toggleExpand = useCallback((id: string) => {
    setExpandedRows(prev => {
      const next = new Set(prev);
      if (next.has(id)) {
        next.delete(id);
      } else {
        next.add(id);
      }
      return next;
    });
  }, []);

  const handleSortClick = useCallback((key: string) => {
    if (sortBy === key) {
      setSortOrder(prev => (prev === 'desc' ? 'asc' : 'desc'));
    } else {
      setSortBy(key);
      setSortOrder('desc');
    }
  }, [sortBy]);

  const handleQuickClone = useCallback(async (agent: AiAgent) => {
    try {
      const cloned = await agentsApi.cloneAgent(agent.id);
      showNotification(`Cloned as "${cloned.name}"`, 'success');
      setRefreshKey(prev => prev + 1);
    } catch {
      showNotification('Failed to clone agent', 'error');
    }
  }, [showNotification]);

  const handleQuickToggleStatus = useCallback(async (agent: AiAgent) => {
    try {
      if (agent.status === 'active') {
        await agentsApi.pauseAgent(agent.id);
        showNotification(`${agent.name} paused`, 'success');
      } else {
        await agentsApi.resumeAgent(agent.id);
        showNotification(`${agent.name} resumed`, 'success');
      }
      setRefreshKey(prev => prev + 1);
    } catch {
      showNotification('Failed to update agent status', 'error');
    }
  }, [showNotification]);

  const handleQuickArchive = useCallback(async (agent: AiAgent) => {
    try {
      await agentsApi.archiveAgent(agent.id);
      showNotification(`${agent.name} archived`, 'success');
      setRefreshKey(prev => prev + 1);
    } catch {
      showNotification('Failed to archive agent', 'error');
    }
  }, [showNotification]);

  const handleChat = useCallback((agent: AiAgent) => {
    openConversationMaximized(agent.id, agent.name);
  }, [openConversationMaximized]);

  // --- Render ---

  return (
    <div>
      {/* Filter toolbar */}
      <div className="flex items-center gap-3 mb-4 flex-wrap">
        {/* Search input */}
        <div className="relative flex-1 min-w-[200px] max-w-sm">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-theme-tertiary" />
          <input
            type="text"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search agents..."
            className="w-full pl-9 pr-3 py-2 text-sm bg-theme-background border border-theme rounded-lg text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:ring-1 focus:ring-theme-accent"
          />
        </div>

        {/* Status filter pills */}
        <div className="flex gap-1">
          {STATUS_TABS.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setStatusFilter(tab.id)}
              className={cn(
                'px-3 py-1.5 text-xs font-medium rounded-md transition-colors',
                statusFilter === tab.id
                  ? 'bg-theme-interactive-primary/10 text-theme-accent border border-theme-accent/30'
                  : 'text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-hover border border-transparent'
              )}
            >
              {tab.label}
            </button>
          ))}
        </div>

        {/* Type filter select */}
        <select
          value={typeFilter}
          onChange={(e) => setTypeFilter(e.target.value)}
          className="px-3 py-1.5 text-xs bg-theme-background border border-theme rounded-md text-theme-primary focus:outline-none focus:ring-1 focus:ring-theme-accent"
        >
          <option value="">All types</option>
          {Object.entries(AGENT_TYPE_LABELS).map(([value, label]) => (
            <option key={value} value={value}>{label}</option>
          ))}
        </select>

        {/* My Agents toggle */}
        <button
          onClick={() => setMyAgentsOnly(prev => !prev)}
          className={cn(
            'px-3 py-1.5 text-xs font-medium rounded-md transition-colors',
            myAgentsOnly
              ? 'bg-theme-interactive-primary/10 text-theme-accent border border-theme-accent/30'
              : 'text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-hover border border-transparent'
          )}
        >
          Mine
        </button>

        {/* Sort pills */}
        <div className="flex gap-1">
          {SORT_OPTIONS.map((opt) => (
            <button
              key={opt.key}
              onClick={() => handleSortClick(opt.key)}
              className={cn(
                'inline-flex items-center gap-0.5 px-2 py-1.5 text-xs font-medium rounded-md transition-colors',
                sortBy === opt.key
                  ? 'bg-theme-interactive-primary/10 text-theme-accent border border-theme-accent/30'
                  : 'text-theme-tertiary hover:text-theme-secondary hover:bg-theme-surface-hover border border-transparent'
              )}
            >
              {opt.label}
              {sortBy === opt.key && (
                sortOrder === 'desc'
                  ? <ArrowDown className="h-3 w-3" />
                  : <ArrowUp className="h-3 w-3" />
              )}
            </button>
          ))}
        </div>
      </div>

      {/* Table */}
      <div className="bg-theme-surface border border-theme rounded-lg overflow-hidden">
        <table className="min-w-full divide-y divide-theme">
          <thead className="bg-theme-background">
            <tr>
              <th className="w-10 px-3 py-3" />
              <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">Name</th>
              <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">Status</th>
              <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">Provider</th>
              <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">Trust</th>
              <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">Last Run</th>
              <th className="w-36 px-3 py-3" />
            </tr>
          </thead>
          <tbody className="divide-y divide-theme">
            {filteredAgents.map((agent) => (
              <React.Fragment key={agent.id}>
                {/* Main row */}
                <tr
                  className={cn(
                    'hover:bg-theme-surface-hover transition-colors cursor-pointer',
                    expandedRows.has(agent.id) && 'bg-theme-surface-hover'
                  )}
                  onClick={() => toggleExpand(agent.id)}
                >
                  <td className="px-3 py-3">
                    <div className={cn(
                      'transition-transform duration-200',
                      expandedRows.has(agent.id) && 'rotate-90'
                    )}>
                      <ChevronRight className={cn(
                        'h-4 w-4',
                        expandedRows.has(agent.id) ? 'text-theme-accent' : 'text-theme-tertiary'
                      )} />
                    </div>
                  </td>
                  <td className="px-4 py-3">
                    <div className="flex items-center gap-2">
                      <span className={cn('w-2 h-2 rounded-full flex-shrink-0', STATUS_CONFIG[agent.status]?.dot || 'bg-theme-secondary')} />
                      <div className="min-w-0">
                        <div className="text-sm font-medium text-theme-primary truncate">{agent.name}</div>
                        {agent.description && (
                          <div className="text-xs text-theme-tertiary truncate max-w-xs">{agent.description}</div>
                        )}
                      </div>
                    </div>
                  </td>
                  <td className="px-4 py-3">
                    <Badge variant={STATUS_CONFIG[agent.status]?.variant || 'outline'} size="sm">
                      {STATUS_CONFIG[agent.status]?.label || agent.status}
                    </Badge>
                  </td>
                  <td className="px-4 py-3">
                    <span className="text-sm text-theme-secondary">
                      {agent.provider?.name || '\u2014'}{agent.model ? ` \u00b7 ${agent.model}` : ''}
                    </span>
                  </td>
                  <td className="px-4 py-3">
                    {renderTrustBadge(agent)}
                  </td>
                  <td className="px-4 py-3">
                    <span className="text-sm text-theme-tertiary">{timeAgo(agent.updated_at)}</span>
                  </td>
                  <td className="px-3 py-3">
                    <div className="flex items-center gap-0.5" onClick={(e) => e.stopPropagation()}>
                      <Button variant="ghost" size="sm" iconOnly onClick={() => openAgent(agent.id)} title="View details">
                        <Eye className="h-3.5 w-3.5" />
                      </Button>
                      <Button variant="ghost" size="sm" iconOnly onClick={() => handleChat(agent)} title="Chat">
                        <MessageSquare className="h-3.5 w-3.5" />
                      </Button>
                      {canManage && (
                        <>
                          <Button variant="ghost" size="sm" iconOnly onClick={() => setEditAgent(agent)} title="Edit">
                            <Pencil className="h-3.5 w-3.5" />
                          </Button>
                          <Button variant="ghost" size="sm" iconOnly onClick={() => handleQuickClone(agent)} title="Clone">
                            <Copy className="h-3.5 w-3.5" />
                          </Button>
                          <Button
                            variant="ghost"
                            size="sm"
                            iconOnly
                            onClick={() => handleQuickToggleStatus(agent)}
                            title={agent.status === 'active' ? 'Pause' : 'Resume'}
                          >
                            {agent.status === 'active'
                              ? <Pause className="h-3.5 w-3.5" />
                              : <Play className="h-3.5 w-3.5" />
                            }
                          </Button>
                          <DropdownMenu
                            trigger={
                              <Button variant="ghost" size="sm" iconOnly title="More actions">
                                <MoreHorizontal className="h-3.5 w-3.5" />
                              </Button>
                            }
                            items={[
                              { icon: Archive, label: 'Archive', onClick: () => handleQuickArchive(agent) },
                            ]}
                            align="right"
                            width="w-36"
                          />
                        </>
                      )}
                    </div>
                  </td>
                </tr>

                {/* Expanded row */}
                {expandedRows.has(agent.id) && (
                  <AgentExpandedRow agent={agent} />
                )}
              </React.Fragment>
            ))}
          </tbody>
        </table>

        {/* Empty state */}
        {!loading && filteredAgents.length === 0 && (
          <div className="flex flex-col items-center justify-center py-12 px-4">
            <Brain className="w-10 h-10 text-theme-tertiary mb-3" />
            <p className="text-sm text-theme-tertiary">{search ? 'No matching agents' : 'No agents found'}</p>
          </div>
        )}

        {/* Loading state */}
        {loading && agents.length === 0 && (
          <div className="flex items-center justify-center py-12">
            <Loader2 className="w-6 h-6 text-theme-secondary animate-spin" />
          </div>
        )}
      </div>

      {/* Footer */}
      {agents.length > 0 && (
        <div className="flex items-center justify-between mt-3 text-xs text-theme-tertiary">
          <span>Showing {filteredAgents.length} of {agents.length} agents</span>
          <span>{agents.filter(a => a.status === 'active').length} active</span>
        </div>
      )}

      {/* Edit Agent Modal */}
      <EditAgentModal
        isOpen={!!editAgent}
        onClose={() => setEditAgent(null)}
        agent={editAgent}
        onAgentUpdated={() => { setEditAgent(null); setRefreshKey(prev => prev + 1); }}
        onAgentDeleted={() => { setEditAgent(null); setRefreshKey(prev => prev + 1); }}
      />
    </div>
  );
};

// --- Helpers ---

function renderTrustBadge(agent: AiAgent): React.ReactNode {
  const trustLevel = (agent as AiAgent & { trust_level?: string }).trust_level;
  const trustConfig = trustLevel ? TRUST_CONFIG[trustLevel] : undefined;
  if (!trustConfig) {
    return <span className="text-sm text-theme-tertiary">{'\u2014'}</span>;
  }
  return (
    <Badge variant={trustConfig.variant} size="xs">
      {trustConfig.icon && <Shield className="h-2.5 w-2.5 mr-0.5" />}
      {trustConfig.label}
    </Badge>
  );
}
