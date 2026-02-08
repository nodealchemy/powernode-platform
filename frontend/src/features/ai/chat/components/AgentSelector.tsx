import React, { useState, useEffect } from 'react';
import { Bot, ChevronDown } from 'lucide-react';
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
        <div className="absolute top-full left-0 right-0 mt-1 bg-theme-surface border border-theme rounded-lg shadow-lg z-50 max-h-60 overflow-y-auto">
          {agents.length === 0 ? (
            <div className="px-3 py-2 text-sm text-theme-secondary">No active agents</div>
          ) : (
            agents.map(agent => (
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
      )}
    </div>
  );
};
