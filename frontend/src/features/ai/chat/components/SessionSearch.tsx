import React, { useState, useEffect, useCallback, useMemo } from 'react';
import { Search, Terminal, Sparkles, Users, X, Loader2 } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { workspacesApi } from '@/shared/services/ai/WorkspacesApiService';
import type { McpSessionInfo } from '@/shared/services/ai/WorkspacesApiService';
import apiClient from '@/shared/services/apiClient';
import { logger } from '@/shared/utils/logger';

interface AgentInfo {
  id: string;
  name: string;
  agent_type: string;
  status: string;
  is_concierge?: boolean;
}

interface SessionSearchProps {
  onCreateWorkspace: (name: string, agentIds: string[]) => Promise<void>;
  onClose: () => void;
}

export const SessionSearch: React.FC<SessionSearchProps> = ({
  onCreateWorkspace,
  onClose,
}) => {
  const [sessions, setSessions] = useState<McpSessionInfo[]>([]);
  const [agents, setAgents] = useState<AgentInfo[]>([]);
  const [loadingSessions, setLoadingSessions] = useState(true);
  const [loadingAgents, setLoadingAgents] = useState(true);
  const [creating, setCreating] = useState(false);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [workspaceName, setWorkspaceName] = useState('');
  const [includeConcierge, setIncludeConcierge] = useState(true);
  const [search, setSearch] = useState('');

  const fetchSessions = useCallback(async () => {
    try {
      setLoadingSessions(true);
      const data = await workspacesApi.getActiveSessions();
      setSessions(data);
    } catch (err) {
      logger.error('Failed to fetch MCP sessions', err);
    } finally {
      setLoadingSessions(false);
    }
  }, []);

  const fetchAgents = useCallback(async () => {
    try {
      setLoadingAgents(true);
      const response = await apiClient.get('/ai/agents', { params: { status: 'active' } });
      const items = response.data?.data?.items || response.data?.data || [];
      setAgents(Array.isArray(items) ? items : []);
    } catch (err) {
      logger.error('Failed to fetch agents', err);
    } finally {
      setLoadingAgents(false);
    }
  }, []);

  useEffect(() => {
    fetchSessions();
    fetchAgents();
  }, [fetchSessions, fetchAgents]);

  // Collect MCP session agent IDs so we don't show duplicates in the AI agents list
  const mcpAgentIds = useMemo(() => new Set(sessions.map(s => s.agent?.id).filter(Boolean)), [sessions]);

  // AI agents: exclude concierge (has its own toggle) and agents already shown in MCP sessions
  const aiAgents = useMemo(() => {
    const filtered = agents.filter(a =>
      !a.is_concierge && !mcpAgentIds.has(a.id)
    );
    if (!search.trim()) return filtered;
    const q = search.toLowerCase();
    return filtered.filter(a => a.name.toLowerCase().includes(q));
  }, [agents, mcpAgentIds, search]);

  // Filter MCP sessions by search
  const filteredSessions = useMemo(() => {
    if (!search.trim()) return sessions;
    const q = search.toLowerCase();
    return sessions.filter(s =>
      (s.agent?.name || s.display_name || '').toLowerCase().includes(q)
    );
  }, [sessions, search]);

  const toggleAgent = (agentId: string) => {
    setSelectedIds(prev => {
      const next = new Set(prev);
      if (next.has(agentId)) {
        next.delete(agentId);
      } else {
        next.add(agentId);
      }
      return next;
    });
  };

  const handleCreate = async () => {
    if (!workspaceName.trim()) return;

    try {
      setCreating(true);
      const agentIds = Array.from(selectedIds);
      await onCreateWorkspace(workspaceName.trim(), agentIds);
      onClose();
    } catch (err) {
      logger.error('Failed to create workspace', err);
    } finally {
      setCreating(false);
    }
  };

  const formatTimestamp = (ts: string) => {
    const date = new Date(ts);
    const now = new Date();
    const diffMs = now.getTime() - date.getTime();
    const diffMin = Math.floor(diffMs / 60000);

    if (diffMin < 1) return 'Just now';
    if (diffMin < 60) return `${diffMin}m ago`;
    const diffHr = Math.floor(diffMin / 60);
    if (diffHr < 24) return `${diffHr}h ago`;
    return date.toLocaleDateString();
  };

  const loading = loadingSessions && loadingAgents;

  return (
    <div className="flex flex-col h-full bg-theme-surface border-r border-theme">
      {/* Header */}
      <div className="flex items-center justify-between px-3 py-3 border-b border-theme">
        <h3 className="text-sm font-semibold text-theme-primary">New Workspace</h3>
        <Button variant="ghost" size="xs" iconOnly onClick={onClose} title="Close">
          <X className="h-4 w-4" />
        </Button>
      </div>

      {/* Workspace Name */}
      <div className="px-3 py-2 border-b border-theme">
        <label className="block text-xs font-medium text-theme-secondary mb-1">
          Workspace Name
        </label>
        <input
          type="text"
          value={workspaceName}
          onChange={(e) => setWorkspaceName(e.target.value)}
          placeholder="My Workspace"
          className="w-full px-2 py-1.5 text-sm bg-theme-background border border-theme rounded text-theme-primary placeholder:text-theme-text-tertiary focus:outline-none focus:ring-1 focus:ring-theme-interactive-primary"
          maxLength={100}
        />
      </div>

      {/* Include Concierge Toggle */}
      <div className="px-3 py-2 border-b border-theme">
        <label className="flex items-center gap-2 cursor-pointer">
          <input
            type="checkbox"
            checked={includeConcierge}
            onChange={(e) => setIncludeConcierge(e.target.checked)}
            className="rounded border-theme text-theme-interactive-primary focus:ring-theme-interactive-primary"
          />
          <span className="text-xs text-theme-secondary">Include Concierge</span>
        </label>
      </div>

      {/* Search */}
      <div className="px-3 py-2 border-b border-theme">
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

      <div className="flex-1 overflow-y-auto">
        {loading ? (
          <div className="flex items-center justify-center py-8">
            <Loader2 className="h-5 w-5 text-theme-text-tertiary animate-spin" />
          </div>
        ) : (
          <>
            {/* Active MCP Sessions */}
            {filteredSessions.length > 0 && (
              <div>
                <div className="px-3 py-1.5 flex items-center gap-1.5">
                  <Terminal className="h-3 w-3 text-theme-text-tertiary" />
                  <span className="text-[10px] font-semibold text-theme-text-tertiary uppercase tracking-wider">
                    Active MCP Sessions
                  </span>
                </div>
                <div className="px-3 space-y-1.5 pb-2">
                  {filteredSessions.map((session) => {
                    const agentId = session.agent?.id;
                    if (!agentId) return null;
                    const isSelected = selectedIds.has(agentId);
                    const rawName = session.agent?.name || session.display_name || 'MCP Client';
                    const seqMatch = rawName.match(/#(\d+)$/);
                    const sessionDisplayName = seqMatch ? rawName.slice(0, seqMatch.index).trim() : rawName;
                    const sessionSeqNum = seqMatch?.[1];

                    return (
                      <button
                        key={session.id}
                        onClick={() => toggleAgent(agentId)}
                        className={`w-full flex items-start gap-2 p-2 rounded-lg border transition-colors text-left ${
                          isSelected
                            ? 'border-theme-interactive-primary/60 bg-theme-interactive-primary/5'
                            : 'border-theme/40 hover:bg-theme-surface-hover'
                        }`}
                      >
                        <div className={`flex-shrink-0 w-8 h-8 rounded-md flex items-center justify-center ${
                          isSelected
                            ? 'bg-theme-info/10 text-theme-info'
                            : 'bg-theme-surface text-theme-secondary'
                        }`}>
                          <Terminal className="h-4 w-4" />
                        </div>
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center gap-1.5">
                            <span className="text-sm font-medium text-theme-primary truncate">
                              {sessionDisplayName}
                            </span>
                            {sessionSeqNum && (
                              <span className="flex-shrink-0 min-w-[1.25rem] h-5 px-1 bg-theme-info/15 text-theme-info text-[10px] font-bold rounded flex items-center justify-center">
                                #{sessionSeqNum}
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
                          <div className="flex items-center gap-2 mt-0.5">
                            {session.oauth_application && (
                              <span className="text-[10px] text-theme-text-tertiary">
                                {session.oauth_application.name}
                              </span>
                            )}
                            <span className="text-[10px] text-theme-text-tertiary">
                              {session.user.name}
                            </span>
                          </div>
                          <span className="text-[10px] text-theme-text-tertiary">
                            {formatTimestamp(session.last_activity_at || session.created_at)}
                          </span>
                        </div>
                      </button>
                    );
                  })}
                </div>
              </div>
            )}

            {/* AI Agents */}
            <div>
              {filteredSessions.length > 0 && <div className="border-t border-theme" />}
              <div className="px-3 py-1.5 flex items-center gap-1.5">
                <Sparkles className="h-3 w-3 text-theme-text-tertiary" />
                <span className="text-[10px] font-semibold text-theme-text-tertiary uppercase tracking-wider">
                  AI Agents
                </span>
              </div>
              <div className="px-3 space-y-1.5 pb-2">
                {loadingAgents ? (
                  <div className="flex items-center justify-center py-4">
                    <Loader2 className="h-4 w-4 text-theme-text-tertiary animate-spin" />
                  </div>
                ) : aiAgents.length === 0 ? (
                  <p className="text-xs text-theme-text-tertiary py-2">
                    {search.trim() ? 'No matching agents' : 'No AI agents available'}
                  </p>
                ) : (
                  aiAgents.map((agent) => {
                    const isSelected = selectedIds.has(agent.id);
                    const agentSeqMatch = agent.name.match(/#(\d+)$/);
                    const agentDisplayName = agentSeqMatch ? agent.name.slice(0, agentSeqMatch.index).trim() : agent.name;
                    const agentSeqNum = agentSeqMatch?.[1];

                    return (
                      <button
                        key={agent.id}
                        onClick={() => toggleAgent(agent.id)}
                        className={`w-full flex items-center gap-2 p-2 rounded-lg border transition-colors text-left ${
                          isSelected
                            ? 'border-theme-interactive-primary/60 bg-theme-interactive-primary/5'
                            : 'border-theme/40 hover:bg-theme-surface-hover'
                        }`}
                      >
                        <div className={`flex-shrink-0 w-8 h-8 rounded-md flex items-center justify-center ${
                          isSelected
                            ? 'bg-theme-interactive-primary/10 text-theme-interactive-primary'
                            : 'bg-theme-surface text-theme-secondary'
                        }`}>
                          <Sparkles className="h-4 w-4" />
                        </div>
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center gap-1.5">
                            <span className="text-sm font-medium text-theme-primary truncate">
                              {agentDisplayName}
                            </span>
                            {agentSeqNum && (
                              <span className="flex-shrink-0 min-w-[1.25rem] h-5 px-1 bg-theme-info/15 text-theme-info text-[10px] font-bold rounded flex items-center justify-center">
                                #{agentSeqNum}
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
                        <span className="inline-flex items-center gap-0.5 px-1.5 py-0.5 text-[10px] font-medium bg-theme-interactive-primary/10 text-theme-interactive-primary rounded-full">
                          {agent.agent_type === 'mcp_client' ? 'MCP' : 'AI'}
                        </span>
                      </button>
                    );
                  })
                )}
              </div>
            </div>

            {/* Empty state when both lists are empty */}
            {filteredSessions.length === 0 && aiAgents.length === 0 && !loadingAgents && !loadingSessions && (
              <div className="text-center py-6 px-3">
                <Users className="h-8 w-8 text-theme-text-tertiary mx-auto mb-2" />
                <p className="text-xs text-theme-text-tertiary">
                  {search.trim() ? 'No matching agents found.' : 'No agents available.'}
                </p>
              </div>
            )}
          </>
        )}
      </div>

      {/* Create Button */}
      <div className="px-3 py-3 border-t border-theme">
        <Button
          variant="primary"
          size="sm"
          onClick={handleCreate}
          disabled={creating || !workspaceName.trim()}
          className="w-full"
        >
          {creating ? (
            <Loader2 className="h-4 w-4 mr-1.5 animate-spin" />
          ) : (
            <Users className="h-4 w-4 mr-1.5" />
          )}
          Create Workspace
          {selectedIds.size > 0 && ` (${selectedIds.size} agent${selectedIds.size > 1 ? 's' : ''})`}
        </Button>
      </div>
    </div>
  );
};
