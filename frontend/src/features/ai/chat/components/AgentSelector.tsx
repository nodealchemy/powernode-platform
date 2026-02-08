import React, { useState, useEffect, useMemo, useRef } from 'react';
import { Bot, ChevronDown, Search } from 'lucide-react';
import apiClient from '@/shared/services/apiClient';

interface Agent {
  id: string;
  name: string;
  agent_type: string;
  status: string;
}

interface AgentSelectorProps {
  selectedAgentId?: string;
  onSelect: (agentId: string) => void;
}

export const AgentSelector: React.FC<AgentSelectorProps> = ({ selectedAgentId, onSelect }) => {
  const [agents, setAgents] = useState<Agent[]>([]);
  const [isOpen, setIsOpen] = useState(false);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const searchRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const fetchAgents = async () => {
      try {
        const response = await apiClient.get('/ai/agents', { params: { status: 'active' } });
        const items = response.data?.data?.items || response.data?.data || [];
        setAgents(Array.isArray(items) ? items : []);
      } catch {
        // Silently handle error
      } finally {
        setLoading(false);
      }
    };
    fetchAgents();
  }, []);

  useEffect(() => {
    if (isOpen) {
      setSearch('');
      setTimeout(() => searchRef.current?.focus(), 0);
    }
  }, [isOpen]);

  const filteredAgents = useMemo(() => {
    if (!search.trim()) return agents;
    const q = search.toLowerCase();
    return agents.filter(a => a.name.toLowerCase().includes(q) || a.agent_type.toLowerCase().includes(q));
  }, [agents, search]);

  const selectedAgent = agents.find(a => a.id === selectedAgentId);

  return (
    <div className="relative">
      <button
        type="button"
        onClick={() => setIsOpen(!isOpen)}
        className="w-full flex items-center justify-between gap-2 px-3 py-2 text-sm border border-theme rounded-lg bg-theme-surface text-theme-primary hover:bg-theme-surface-hover transition-colors"
      >
        <div className="flex items-center gap-2 truncate">
          <Bot className="h-4 w-4 text-theme-info flex-shrink-0" />
          <span className="truncate">
            {loading ? 'Loading...' : selectedAgent?.name || 'Select an agent'}
          </span>
        </div>
        <ChevronDown className={`h-4 w-4 text-theme-secondary flex-shrink-0 transition-transform ${isOpen ? 'rotate-180' : ''}`} />
      </button>

      {isOpen && (
        <div className="absolute bottom-full left-0 right-0 mb-1 bg-theme-surface border border-theme rounded-lg shadow-lg z-50 flex flex-col max-h-72">
          <div className="p-2 border-b border-theme flex-shrink-0">
            <div className="relative">
              <Search className="absolute left-2 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-theme-secondary" />
              <input
                ref={searchRef}
                type="text"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="Search agents..."
                className="w-full pl-7 pr-2 py-1.5 text-sm bg-theme-background border border-theme rounded-md text-theme-primary placeholder:text-theme-secondary focus:outline-none focus:ring-1 focus:ring-theme-primary"
              />
            </div>
          </div>
          <div className="overflow-y-auto">
            {filteredAgents.length === 0 ? (
              <div className="px-3 py-2 text-sm text-theme-secondary">
                {agents.length === 0 ? 'No active agents' : 'No matches'}
              </div>
            ) : (
              filteredAgents.map(agent => (
                <button
                  key={agent.id}
                  type="button"
                  onClick={() => {
                    onSelect(agent.id);
                    setIsOpen(false);
                  }}
                  className={`w-full flex items-center gap-2 px-3 py-2 text-sm text-left hover:bg-theme-surface-hover transition-colors ${
                    agent.id === selectedAgentId ? 'bg-theme-primary/10 text-theme-primary' : 'text-theme-primary'
                  }`}
                >
                  <div className="h-2 w-2 rounded-full bg-theme-success flex-shrink-0" />
                  <span className="truncate">{agent.name}</span>
                  <span className="text-xs text-theme-secondary ml-auto flex-shrink-0">{agent.agent_type}</span>
                </button>
              ))
            )}
          </div>
        </div>
      )}
    </div>
  );
};
