import React, { useState, useEffect, useCallback, useMemo } from 'react';
import { Loader2, Sparkles, Terminal, X, Search, MessageSquare } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { useChatWindow } from '../context/ChatWindowContext';
import apiClient from '@/shared/services/apiClient';

interface AgentInfo {
  id: string;
  name: string;
  agent_type: string;
  status: string;
  is_concierge?: boolean;
}

interface ConversationCreatorProps {
  onComplete: () => void;
}

export const ConversationCreator: React.FC<ConversationCreatorProps> = ({ onComplete }) => {
  const { state, openConversation, openConcierge, switchTab, setMode } = useChatWindow();
  const [agents, setAgents] = useState<AgentInfo[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedAgentId, setSelectedAgentId] = useState('');
  const [starting, setStarting] = useState(false);
  const [conciergeLoading, setConciergeLoading] = useState(false);
  const [search, setSearch] = useState('');

  useEffect(() => {
    const fetchAgents = async () => {
      try {
        const response = await apiClient.get('/ai/agents', { params: { status: 'active' } });
        const items = response.data?.data?.items || response.data?.data || [];
        setAgents(Array.isArray(items) ? items : []);
      } catch {
        // Silent
      } finally {
        setLoading(false);
      }
    };
    fetchAgents();
  }, []);

  const conciergeAgent = useMemo(() => agents.find(a => a.is_concierge), [agents]);
  const regularAgents = useMemo(() => agents.filter(a => !a.is_concierge), [agents]);

  // Group agents by type, sorted: AI assistants first, then MCP clients
  const groupedAgents = useMemo(() => {
    const filtered = search.trim()
      ? regularAgents.filter(a => a.name.toLowerCase().includes(search.toLowerCase()))
      : regularAgents;

    const aiAgents = filtered
      .filter(a => a.agent_type === 'assistant')
      .sort((a, b) => a.name.localeCompare(b.name));

    const mcpAgents = filtered
      .filter(a => a.agent_type === 'mcp_client')
      .sort((a, b) => a.name.localeCompare(b.name));

    const otherAgents = filtered
      .filter(a => a.agent_type !== 'assistant' && a.agent_type !== 'mcp_client')
      .sort((a, b) => a.name.localeCompare(b.name));

    return { aiAgents, mcpAgents, otherAgents };
  }, [regularAgents, search]);

  const totalFiltered = groupedAgents.aiAgents.length + groupedAgents.mcpAgents.length + groupedAgents.otherAgents.length;

  const handleStart = useCallback(async () => {
    if (!selectedAgentId) return;
    setStarting(true);
    try {
      await openConversation(selectedAgentId, '');
      onComplete();
    } finally {
      setStarting(false);
    }
  }, [selectedAgentId, openConversation, onComplete]);

  const handleConcierge = useCallback(async () => {
    setConciergeLoading(true);
    try {
      await openConcierge();
      onComplete();
    } finally {
      setConciergeLoading(false);
    }
  }, [openConcierge, onComplete]);

  const handleCancel = useCallback(() => {
    if (state.tabs.length > 0) {
      switchTab(state.tabs[0].id);
    } else {
      setMode('closed');
    }
  }, [state.tabs, switchTab, setMode]);

  const showCancel = state.tabs.length > 0 || !state.showSidebar;

  const renderAgentCard = (agent: AgentInfo) => {
    const isSelected = agent.id === selectedAgentId;
    const isMcp = agent.agent_type === 'mcp_client';
    const seqMatch = agent.name.match(/#(\d+)$/);
    const displayName = seqMatch ? agent.name.slice(0, seqMatch.index).trim() : agent.name;
    const seqNum = seqMatch?.[1];

    return (
      <button
        key={agent.id}
        onClick={() => setSelectedAgentId(isSelected ? '' : agent.id)}
        className={`w-full flex items-center gap-2 p-2 rounded-lg border transition-colors text-left ${
          isSelected
            ? 'border-theme-interactive-primary/60 bg-theme-interactive-primary/5'
            : 'border-theme/40 hover:bg-theme-surface-hover'
        }`}
      >
        <div className={`flex-shrink-0 w-8 h-8 rounded-md flex items-center justify-center ${
          isSelected
            ? isMcp ? 'bg-theme-info/10 text-theme-info' : 'bg-theme-interactive-primary/10 text-theme-interactive-primary'
            : 'bg-theme-surface text-theme-secondary'
        }`}>
          {isMcp ? <Terminal className="h-4 w-4" /> : <Sparkles className="h-4 w-4" />}
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-1.5">
            <span className="text-sm font-medium text-theme-primary truncate">
              {displayName}
            </span>
            {seqNum && (
              <span className="flex-shrink-0 min-w-[1.25rem] h-5 px-1 bg-theme-info/15 text-theme-info text-[10px] font-bold rounded flex items-center justify-center">
                #{seqNum}
              </span>
            )}
            {isSelected && (
              <span className="flex-shrink-0 w-4 h-4 bg-theme-interactive-primary rounded-full flex items-center justify-center">
                <svg className="w-2.5 h-2.5 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={3} d="M5 13l4 4L19 7" />
                </svg>
              </span>
            )}
          </div>
        </div>
        <span className={`inline-flex items-center gap-0.5 px-1.5 py-0.5 text-[10px] font-medium rounded-full flex-shrink-0 ${
          isMcp
            ? 'bg-theme-info/10 text-theme-info'
            : 'bg-theme-interactive-primary/10 text-theme-interactive-primary'
        }`}>
          {isMcp ? 'MCP' : 'AI'}
        </span>
      </button>
    );
  };

  return (
    <div className="flex flex-col h-full bg-theme-background">
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-3 border-b border-theme">
        <h3 className="text-sm font-semibold text-theme-primary">New Conversation</h3>
        {showCancel && (
          <Button variant="ghost" size="xs" iconOnly onClick={handleCancel} title="Cancel">
            <X className="h-4 w-4" />
          </Button>
        )}
      </div>

      {/* Quick start: Concierge */}
      {conciergeAgent && (
        <div className="px-4 py-3 border-b border-theme">
          <Button
            variant="primary"
            size="sm"
            onClick={handleConcierge}
            disabled={conciergeLoading}
            className="w-full"
          >
            {conciergeLoading ? (
              <Loader2 className="h-4 w-4 mr-1.5 animate-spin" />
            ) : (
              <Sparkles className="h-4 w-4 mr-1.5" />
            )}
            Chat with Concierge
          </Button>
        </div>
      )}

      {/* Search */}
      <div className="px-4 py-2 border-b border-theme">
        <div className="relative">
          <Search className="absolute left-2 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-theme-secondary" />
          <input
            type="text"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search agents..."
            className="w-full pl-7 pr-2 py-1.5 text-sm bg-theme-background border border-theme rounded-md text-theme-primary placeholder:text-theme-text-tertiary focus:outline-none focus:ring-1 focus:ring-theme-interactive-primary"
          />
        </div>
      </div>

      {/* Agent list — grouped by type */}
      <div className="flex-1 overflow-y-auto">
        {loading ? (
          <div className="flex items-center justify-center py-8">
            <Loader2 className="h-5 w-5 text-theme-text-tertiary animate-spin" />
          </div>
        ) : totalFiltered === 0 ? (
          <div className="text-center py-6 px-4">
            <MessageSquare className="h-8 w-8 text-theme-text-tertiary mx-auto mb-2" />
            <p className="text-xs text-theme-text-tertiary">
              {search.trim() ? 'No matching agents' : 'No agents available'}
            </p>
          </div>
        ) : (
          <>
            {/* AI Agents */}
            {groupedAgents.aiAgents.length > 0 && (
              <div>
                <div className="px-4 py-1.5 flex items-center gap-1.5">
                  <Sparkles className="h-3 w-3 text-theme-text-tertiary" />
                  <span className="text-[10px] font-semibold text-theme-text-tertiary uppercase tracking-wider">
                    AI Agents
                  </span>
                </div>
                <div className="px-4 space-y-1.5 pb-2">
                  {groupedAgents.aiAgents.map(renderAgentCard)}
                </div>
              </div>
            )}

            {/* MCP Clients */}
            {groupedAgents.mcpAgents.length > 0 && (
              <div>
                {groupedAgents.aiAgents.length > 0 && <div className="border-t border-theme" />}
                <div className="px-4 py-1.5 flex items-center gap-1.5">
                  <Terminal className="h-3 w-3 text-theme-text-tertiary" />
                  <span className="text-[10px] font-semibold text-theme-text-tertiary uppercase tracking-wider">
                    MCP Clients
                  </span>
                </div>
                <div className="px-4 space-y-1.5 pb-2">
                  {groupedAgents.mcpAgents.map(renderAgentCard)}
                </div>
              </div>
            )}

            {/* Other */}
            {groupedAgents.otherAgents.length > 0 && (
              <div>
                {(groupedAgents.aiAgents.length > 0 || groupedAgents.mcpAgents.length > 0) && (
                  <div className="border-t border-theme" />
                )}
                <div className="px-4 py-1.5">
                  <span className="text-[10px] font-semibold text-theme-text-tertiary uppercase tracking-wider">
                    Other
                  </span>
                </div>
                <div className="px-4 space-y-1.5 pb-2">
                  {groupedAgents.otherAgents.map(renderAgentCard)}
                </div>
              </div>
            )}
          </>
        )}
      </div>

      {/* Footer action */}
      <div className="px-4 py-3 border-t border-theme">
        <Button
          variant="primary"
          size="sm"
          onClick={handleStart}
          disabled={!selectedAgentId || starting}
          className="w-full"
        >
          {starting ? (
            <Loader2 className="h-4 w-4 mr-1.5 animate-spin" />
          ) : (
            <MessageSquare className="h-4 w-4 mr-1.5" />
          )}
          Start Conversation
        </Button>
      </div>
    </div>
  );
};
