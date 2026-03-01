import React, { useState, useEffect, useCallback } from 'react';
import { Loader2, MessageSquare } from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import { useChatWindow } from '@/features/ai/chat/context/ChatWindowContext';
import { workspacesApi } from '@/shared/services/ai';
import type { WorkspaceInfo, WorkspaceMember } from '@/shared/services/ai/WorkspacesApiService';

interface AgentWorkspacesTabProps {
  agentId: string;
}

interface AgentWorkspace extends WorkspaceInfo {
  role?: string;
}

function timeAgo(dateStr: string | null): string {
  if (!dateStr) return 'No activity';
  const diff = Date.now() - new Date(dateStr).getTime();
  const minutes = Math.floor(diff / 60000);
  if (minutes < 1) return 'just now';
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  return `${days}d ago`;
}

export const AgentWorkspacesTab: React.FC<AgentWorkspacesTabProps> = ({ agentId }) => {
  const { openConversation } = useChatWindow();
  const [workspaces, setWorkspaces] = useState<AgentWorkspace[]>([]);
  const [loading, setLoading] = useState(true);

  const handleOpenWorkspace = useCallback((ws: AgentWorkspace) => {
    openConversation(agentId, ws.title, ws.conversation_id, {
      isWorkspace: true,
      teamId: ws.team_id,
    });
  }, [agentId, openConversation]);

  useEffect(() => {
    let cancelled = false;

    async function load() {
      try {
        setLoading(true);
        const allWorkspaces = await workspacesApi.getWorkspaces();

        // Fetch details for workspaces that have members, to find agent membership
        const detailResults = await Promise.allSettled(
          allWorkspaces
            .filter((ws) => ws.member_count > 0)
            .map((ws) => workspacesApi.getWorkspace(ws.id))
        );

        const agentWorkspaces: AgentWorkspace[] = [];
        let wsIndex = 0;
        for (const ws of allWorkspaces) {
          if (ws.member_count === 0) continue;
          const result = detailResults[wsIndex];
          wsIndex++;
          if (result?.status !== 'fulfilled') continue;
          const members: WorkspaceMember[] = result.value.members || [];
          const agentMember = members.find((m) => m.id === agentId);
          if (agentMember) {
            agentWorkspaces.push({ ...ws, role: agentMember.role });
          }
        }

        if (!cancelled) {
          setWorkspaces(agentWorkspaces);
        }
      } catch {
        // Silently fail
      } finally {
        if (!cancelled) setLoading(false);
      }
    }

    load();
    return () => { cancelled = true; };
  }, [agentId]);

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <Loader2 className="w-5 h-5 text-theme-secondary animate-spin" />
      </div>
    );
  }

  if (workspaces.length === 0) {
    return (
      <div className="text-center py-12">
        <MessageSquare className="w-10 h-10 text-theme-tertiary mx-auto mb-3" />
        <p className="text-sm text-theme-secondary">This agent is not in any workspaces</p>
      </div>
    );
  }

  return (
    <div className="space-y-2">
      {workspaces.map((ws) => (
        <div
          key={ws.id}
          className="flex items-center justify-between px-4 py-3 border border-theme rounded-lg bg-theme-surface hover:bg-theme-surface-hover transition-colors"
        >
          <div className="flex items-center gap-3 min-w-0">
            <MessageSquare className="w-4 h-4 text-theme-secondary flex-shrink-0" />
            <div className="min-w-0">
              <span className="text-sm font-medium text-theme-primary truncate block">
                {ws.title}
              </span>
              <div className="flex items-center gap-2 mt-0.5">
                {ws.role && (
                  <span className="text-[10px] text-theme-tertiary">Role: {ws.role}</span>
                )}
                <span className="text-[10px] text-theme-tertiary">
                  {ws.member_count} member{ws.member_count !== 1 ? 's' : ''}
                </span>
                <span className="text-[10px] text-theme-tertiary">
                  {ws.message_count} msg{ws.message_count !== 1 ? 's' : ''}
                </span>
              </div>
            </div>
          </div>
          <div className="flex items-center gap-2 flex-shrink-0">
            <span className="text-[10px] text-theme-tertiary whitespace-nowrap">
              {timeAgo(ws.last_activity_at)}
            </span>
            {ws.is_collaborative && (
              <Badge variant="info" size="xs">Collab</Badge>
            )}
            <button
              onClick={() => handleOpenWorkspace(ws)}
              className="inline-flex items-center gap-1 px-2 py-1 text-xs font-medium text-theme-secondary border border-theme rounded hover:bg-theme-surface-hover hover:text-theme-primary transition-colors"
              title="Open workspace"
            >
              <MessageSquare className="w-3 h-3" />
              Chat
            </button>
          </div>
        </div>
      ))}
    </div>
  );
};
