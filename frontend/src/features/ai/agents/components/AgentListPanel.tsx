import React, { useState, useCallback, useEffect, useMemo, useRef } from 'react';
import { Plus, Brain, Search } from 'lucide-react';
import { ResizableListPanel } from '@/shared/components/layout/ResizableListPanel';
import { AgentListItem } from './AgentListItem';
import { agentsApi } from '@/shared/services/ai';
import type { AiAgent } from '@/shared/types/ai';

type TabId = 'all' | 'active' | 'inactive' | 'error';

const TABS: { id: TabId; label: string }[] = [
  { id: 'all', label: 'All' },
  { id: 'active', label: 'Active' },
  { id: 'inactive', label: 'Inactive' },
  { id: 'error', label: 'Error' },
];

const TAB_STATUS_MAP: Record<TabId, AiAgent['status'][] | null> = {
  all: null,
  active: ['active'],
  inactive: ['inactive'],
  error: ['error'],
};

const STATUS_DOT: Record<AiAgent['status'], string> = {
  active: 'bg-theme-success',
  inactive: 'bg-theme-secondary',
  error: 'bg-theme-error',
};

interface AgentListPanelProps {
  selectedAgentId: string | null;
  onSelectAgent: (agent: AiAgent) => void;
  onCreateAgent: () => void;
  refreshKey?: number;
}

export const AgentListPanel: React.FC<AgentListPanelProps> = ({
  selectedAgentId,
  onSelectAgent,
  onCreateAgent,
  refreshKey,
}) => {
  const [agents, setAgents] = useState<AiAgent[]>([]);
  const [loading, setLoading] = useState(true);
  const [activeTab, setActiveTab] = useState<TabId>('all');
  const [search, setSearch] = useState('');
  const [focusIndex, setFocusIndex] = useState(-1);
  const listRef = useRef<HTMLDivElement>(null);

  const loadAgents = useCallback(async () => {
    try {
      setLoading(true);
      const response = await agentsApi.getAgents({ per_page: 100 });
      setAgents(response.items || []);
    } catch {
      // Silently fail — list will show empty state
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadAgents();
  }, [loadAgents]);

  // Reload when refreshKey changes
  useEffect(() => {
    if (refreshKey && refreshKey > 0) {
      loadAgents();
    }
  }, [refreshKey, loadAgents]);

  // Filter by tab + search
  const filteredAgents = useMemo(() => {
    let filtered = agents;
    const statuses = TAB_STATUS_MAP[activeTab];
    if (statuses) {
      filtered = filtered.filter(a => statuses.includes(a.status));
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
  }, [agents, activeTab, search]);

  // Stats
  const activeCount = agents.filter(a => a.status === 'active').length;

  // Keyboard navigation
  const handleKeyDown = useCallback((e: React.KeyboardEvent) => {
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      setFocusIndex(prev => Math.min(prev + 1, filteredAgents.length - 1));
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      setFocusIndex(prev => Math.max(prev - 1, 0));
    } else if (e.key === 'Enter' && focusIndex >= 0 && focusIndex < filteredAgents.length) {
      e.preventDefault();
      onSelectAgent(filteredAgents[focusIndex]);
    } else if (e.key === 'Escape') {
      e.preventDefault();
      setFocusIndex(-1);
    }
  }, [filteredAgents, focusIndex, onSelectAgent]);

  // Scroll focused item into view
  useEffect(() => {
    if (focusIndex >= 0 && listRef.current) {
      const items = listRef.current.querySelectorAll('[data-list-item]');
      items[focusIndex]?.scrollIntoView({ block: 'nearest' });
    }
  }, [focusIndex]);

  return (
    <ResizableListPanel
      storageKeyPrefix="agents-panel"
      title="Agents"
      onKeyDown={handleKeyDown}
      headerAction={
        <button
          onClick={onCreateAgent}
          className="btn-theme btn-theme-primary text-xs px-2 py-1 flex items-center gap-1"
          title="New Agent"
        >
          <Plus className="h-3.5 w-3.5" />
          <span className="hidden sm:inline">New</span>
        </button>
      }
      tabPills={
        <div className="flex px-3 pt-2 pb-1 gap-1">
          {TABS.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`flex-1 px-2 py-1 text-xs font-medium rounded transition-colors ${
                activeTab === tab.id
                  ? 'bg-theme-interactive-primary/10 text-theme-accent'
                  : 'text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-hover'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>
      }
      search={
        <div className="px-3 py-2">
          <div className="relative">
            <Search className="absolute left-2 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-theme-tertiary" />
            <input
              type="text"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search agents..."
              className="w-full pl-7 pr-2 py-1.5 text-xs bg-theme-background border border-theme rounded text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:ring-1 focus:ring-theme-accent"
            />
          </div>
        </div>
      }
      footer={
        agents.length > 0 ? (
          <div className="px-3 py-2 border-t border-theme text-[10px] text-theme-tertiary flex gap-3">
            <span>{activeCount} active</span>
            <span>{agents.length} total</span>
          </div>
        ) : undefined
      }
      collapsedContent={
        <>
          <button
            onClick={onCreateAgent}
            className="w-8 h-8 rounded-md flex items-center justify-center text-theme-accent hover:bg-theme-surface-hover transition-colors"
            title="New Agent"
          >
            <Plus className="h-4 w-4" />
          </button>
          {agents.filter(a => a.status === 'active').slice(0, 10).map((a) => (
            <button
              key={a.id}
              onClick={() => onSelectAgent(a)}
              title={a.name}
              className={`w-8 h-8 rounded-md flex items-center justify-center transition-colors ${
                selectedAgentId === a.id
                  ? 'bg-theme-interactive-primary/10'
                  : 'hover:bg-theme-surface-hover'
              }`}
            >
              <span className={`w-2.5 h-2.5 rounded-full ${STATUS_DOT[a.status] || 'bg-theme-secondary'}`} />
            </button>
          ))}
        </>
      }
    >
      <div ref={listRef}>
        {loading && agents.length === 0 ? (
          <div className="text-center py-8 text-theme-secondary text-xs">Loading...</div>
        ) : filteredAgents.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-8 px-4">
            <Brain className="w-8 h-8 text-theme-tertiary mb-2" />
            <span className="text-xs text-theme-tertiary text-center">
              {search ? 'No matching agents' : 'No agents'}
            </span>
          </div>
        ) : (
          filteredAgents.map((agent, idx) => (
            <div
              key={agent.id}
              className={focusIndex === idx ? 'ring-1 ring-inset ring-theme-accent/50' : ''}
            >
              <AgentListItem
                agent={agent}
                isSelected={selectedAgentId === agent.id}
                onClick={() => onSelectAgent(agent)}
              />
            </div>
          ))
        )}
      </div>
    </ResizableListPanel>
  );
};
