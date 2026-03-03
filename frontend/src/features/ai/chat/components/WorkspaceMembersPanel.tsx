import React, { useState, useEffect, useCallback, useMemo } from 'react';
import { Users, Plus, Trash2, X, Loader2, Search } from 'lucide-react';
import { workspacesApi } from '@/shared/services/ai';
import type { WorkspaceMember } from '@/shared/services/ai/WorkspacesApiService';
import apiClient from '@/shared/services/apiClient';
import { useNotifications } from '@/shared/hooks/useNotifications';

interface Agent {
  id: string;
  name: string;
  agent_type: string;
  status: string;
  is_concierge?: boolean;
}

const TYPE_LABELS: Record<string, string> = {
  concierge: 'Concierge',
  llm: 'AI Agents',
  mcp_client: 'MCP Clients',
  tool: 'Tool Agents',
};

const TYPE_ORDER = ['concierge', 'llm', 'mcp_client', 'tool'];

function groupLabel(type: string): string {
  return TYPE_LABELS[type] || type.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
}

interface WorkspaceMembersPanelProps {
  conversationId: string;
  onClose: () => void;
}

export const WorkspaceMembersPanel: React.FC<WorkspaceMembersPanelProps> = ({
  conversationId,
  onClose,
}) => {
  const { addNotification } = useNotifications();
  const [members, setMembers] = useState<WorkspaceMember[]>([]);
  const [agents, setAgents] = useState<Agent[]>([]);
  const [searchQuery, setSearchQuery] = useState('');
  const [loading, setLoading] = useState(true);
  const [addingId, setAddingId] = useState<string | null>(null);
  const [removingId, setRemovingId] = useState<string | null>(null);

  const fetchMembers = useCallback(async () => {
    try {
      const data = await workspacesApi.getWorkspace(conversationId);
      setMembers(data.members || []);
    } catch (err: unknown) {
      const status = (err as { response?: { status?: number } })?.response?.status;
      if (status === 404) {
        addNotification({ type: 'error', message: 'This conversation is not a workspace' });
        onClose();
      } else {
        addNotification({ type: 'error', message: 'Failed to load workspace members' });
      }
    }
  }, [conversationId, addNotification, onClose]);

  const fetchAgents = useCallback(async () => {
    try {
      const response = await apiClient.get('/ai/agents', { params: { status: 'active' } });
      const items = response.data?.data?.items || response.data?.data || [];
      setAgents(Array.isArray(items) ? items : []);
    } catch {
      // Agents list is non-critical
    }
  }, []);

  useEffect(() => {
    const load = async () => {
      setLoading(true);
      await Promise.all([fetchMembers(), fetchAgents()]);
      setLoading(false);
    };
    load();
  }, [fetchMembers, fetchAgents]);

  // Available agents: exclude existing members, filter by search, group by type
  const groupedAgents = useMemo(() => {
    const memberIds = new Set(members.map((m) => m.id));
    const query = searchQuery.toLowerCase();

    const available = agents
      .filter((a) => !memberIds.has(a.id))
      .filter((a) => !a.is_concierge)
      .filter((a) => a.name.toLowerCase().includes(query));

    const groups = new Map<string, Agent[]>();
    for (const agent of available) {
      const type = agent.agent_type || 'other';
      if (!groups.has(type)) groups.set(type, []);
      groups.get(type)!.push(agent);
    }

    // Sort groups: known types in TYPE_ORDER first, then alphabetical
    const sortedKeys = [...groups.keys()].sort((a, b) => {
      const ai = TYPE_ORDER.indexOf(a);
      const bi = TYPE_ORDER.indexOf(b);
      if (ai !== -1 && bi !== -1) return ai - bi;
      if (ai !== -1) return -1;
      if (bi !== -1) return 1;
      return a.localeCompare(b);
    });

    // Sort agents within each group alphabetically
    for (const agents of groups.values()) {
      agents.sort((a, b) => a.name.localeCompare(b.name));
    }

    return sortedKeys.map((key) => ({ type: key, label: groupLabel(key), agents: groups.get(key)! }));
  }, [agents, members, searchQuery]);

  const handleAdd = async (agentId: string) => {
    setAddingId(agentId);
    try {
      await workspacesApi.inviteAgent(conversationId, agentId);
      addNotification({ type: 'success', message: 'Agent added to workspace' });
      await fetchMembers();
      window.dispatchEvent(new CustomEvent('powernode:workspace-members-changed', {
        detail: { conversationId }
      }));
    } catch {
      addNotification({ type: 'error', message: 'Failed to add agent' });
    } finally {
      setAddingId(null);
    }
  };

  const handleRemove = async (agentId: string) => {
    setRemovingId(agentId);
    try {
      await workspacesApi.removeMember(conversationId, agentId);
      addNotification({ type: 'success', message: 'Member removed from workspace' });
      await fetchMembers();
      window.dispatchEvent(new CustomEvent('powernode:workspace-members-changed', {
        detail: { conversationId }
      }));
    } catch {
      addNotification({ type: 'error', message: 'Failed to remove member' });
    } finally {
      setRemovingId(null);
    }
  };

  const totalAvailable = groupedAgents.reduce((sum, g) => sum + g.agents.length, 0);

  return (
    <div
      className="absolute right-0 top-full mt-1 z-50 bg-theme-surface border border-theme rounded-lg shadow-lg w-[280px] select-auto"
      onClick={(e) => e.stopPropagation()}
      onPointerDown={(e) => e.stopPropagation()}
      onMouseDown={(e) => e.stopPropagation()}
    >
      {/* Header */}
      <div className="flex items-center justify-between px-3 py-2 border-b border-theme">
        <div className="flex items-center gap-1.5 text-xs font-semibold text-theme-primary">
          <Users className="h-3.5 w-3.5" />
          Workspace Members
        </div>
        <button
          type="button"
          onClick={onClose}
          className="p-0.5 rounded hover:bg-theme-surface-hover text-theme-secondary transition-colors"
        >
          <X className="h-3.5 w-3.5" />
        </button>
      </div>

      {loading ? (
        <div className="flex items-center justify-center py-8">
          <Loader2 className="h-4 w-4 animate-spin text-theme-secondary" />
        </div>
      ) : (
        <div className="max-h-[400px] overflow-y-auto">
          {/* Current members */}
          {members.length > 0 && (
            <div>
              <div className="px-3 py-1.5 text-[10px] font-semibold text-theme-tertiary uppercase tracking-wider">
                Members ({members.length})
              </div>
              {members.map((member) => (
                <div
                  key={member.id}
                  className="flex items-center justify-between px-3 py-1.5 hover:bg-theme-surface-hover transition-colors group"
                >
                  <div className="min-w-0">
                    <div className="flex items-center gap-1.5">
                      <div className="h-1.5 w-1.5 rounded-full bg-theme-success shrink-0" />
                      <span className="text-xs text-theme-primary truncate">{member.name}</span>
                    </div>
                    <div className="flex items-center gap-1 ml-3 mt-0.5">
                      <span className="text-[10px] px-1.5 py-0.5 rounded bg-theme-surface-secondary text-theme-secondary">
                        {member.role}
                      </span>
                      <span className="text-[10px] text-theme-tertiary">{member.agent_type}</span>
                    </div>
                  </div>
                  {!member.is_concierge && !member.is_lead && (
                    <button
                      type="button"
                      onClick={() => handleRemove(member.id)}
                      disabled={removingId === member.id}
                      className="p-1 rounded text-theme-tertiary hover:text-theme-danger hover:bg-theme-surface-hover transition-colors disabled:opacity-50 shrink-0"
                      title="Remove member"
                    >
                      {removingId === member.id ? (
                        <Loader2 className="h-3 w-3 animate-spin" />
                      ) : (
                        <Trash2 className="h-3 w-3" />
                      )}
                    </button>
                  )}
                </div>
              ))}
            </div>
          )}

          {/* Add members section */}
          <div className={members.length > 0 ? 'border-t border-theme' : ''}>
            {/* Search */}
            <div className="flex items-center gap-1.5 px-3 py-1.5 border-b border-theme">
              <Search className="h-3 w-3 text-theme-secondary shrink-0" />
              <input
                type="text"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder="Search agents..."
                className="flex-1 text-xs bg-transparent text-theme-primary placeholder:text-theme-tertiary outline-none min-w-0"
              />
            </div>

            {/* Grouped agent list */}
            {totalAvailable === 0 ? (
              <div className="px-3 py-3 text-[10px] text-theme-tertiary text-center">
                {searchQuery ? 'No agents match your search' : 'All agents are already members'}
              </div>
            ) : (
              groupedAgents.map((group) => (
                <div key={group.type}>
                  <div className="px-3 py-1.5 text-[10px] font-semibold text-theme-tertiary uppercase tracking-wider">
                    {group.label}
                  </div>
                  {group.agents.map((agent) => (
                    <button
                      key={agent.id}
                      type="button"
                      disabled={addingId === agent.id}
                      onClick={() => handleAdd(agent.id)}
                      className="w-full flex items-center justify-between px-3 py-1.5 text-left hover:bg-theme-surface-hover transition-colors group/item disabled:opacity-50"
                    >
                      <span className="text-xs text-theme-primary truncate">{agent.name}</span>
                      {addingId === agent.id ? (
                        <Loader2 className="h-3 w-3 animate-spin text-theme-secondary shrink-0" />
                      ) : (
                        <Plus className="h-3 w-3 text-theme-secondary opacity-0 group-hover/item:opacity-100 transition-opacity shrink-0" />
                      )}
                    </button>
                  ))}
                </div>
              ))
            )}
          </div>
        </div>
      )}
    </div>
  );
};
