import React, { useState, useEffect, useCallback } from 'react';
import { Search, Terminal, Users, X, Loader2 } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { workspacesApi } from '@/shared/services/ai/WorkspacesApiService';
import type { McpSessionInfo } from '@/shared/services/ai/WorkspacesApiService';
import { logger } from '@/shared/utils/logger';

interface SessionSearchProps {
  onCreateWorkspace: (name: string, agentIds: string[]) => Promise<void>;
  onClose: () => void;
}

export const SessionSearch: React.FC<SessionSearchProps> = ({
  onCreateWorkspace,
  onClose,
}) => {
  const [sessions, setSessions] = useState<McpSessionInfo[]>([]);
  const [loading, setLoading] = useState(true);
  const [creating, setCreating] = useState(false);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [workspaceName, setWorkspaceName] = useState('');
  const [includeConcierge, setIncludeConcierge] = useState(true);

  const fetchSessions = useCallback(async () => {
    try {
      setLoading(true);
      const data = await workspacesApi.getActiveSessions();
      setSessions(data);
    } catch (err) {
      logger.error('Failed to fetch MCP sessions', err);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchSessions();
  }, [fetchSessions]);

  const toggleSession = (agentId: string) => {
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

      {/* Active Sessions */}
      <div className="px-3 py-2">
        <div className="flex items-center gap-1.5 mb-2">
          <Search className="h-3 w-3 text-theme-text-tertiary" />
          <span className="text-[10px] font-semibold text-theme-text-tertiary uppercase tracking-wider">
            Active Claude Code Sessions
          </span>
        </div>
      </div>

      <div className="flex-1 overflow-y-auto px-3">
        {loading ? (
          <div className="flex items-center justify-center py-8">
            <Loader2 className="h-5 w-5 text-theme-text-tertiary animate-spin" />
          </div>
        ) : sessions.length === 0 ? (
          <div className="text-center py-6">
            <Terminal className="h-8 w-8 text-theme-text-tertiary mx-auto mb-2" />
            <p className="text-xs text-theme-text-tertiary">
              No active MCP sessions found.
            </p>
            <p className="text-xs text-theme-text-tertiary mt-1">
              Start a Claude Code session to see it here.
            </p>
          </div>
        ) : (
          <div className="space-y-1.5">
            {sessions.map((session) => {
              const agentId = session.agent?.id;
              if (!agentId) return null;
              const isSelected = selectedIds.has(agentId);

              return (
                <button
                  key={session.id}
                  onClick={() => toggleSession(agentId)}
                  className={`w-full flex items-start gap-2 p-2 rounded-lg border transition-colors text-left ${
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
                    <Terminal className="h-4 w-4" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-1.5">
                      <span className="text-sm font-medium text-theme-primary truncate">
                        {session.agent?.name || session.display_name || 'MCP Client'}
                      </span>
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
          {selectedIds.size > 0 && ` (${selectedIds.size} session${selectedIds.size > 1 ? 's' : ''})`}
        </Button>
      </div>
    </div>
  );
};
