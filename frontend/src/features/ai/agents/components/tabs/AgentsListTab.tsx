import React from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Brain, Play, Pause, Settings, Clock, MessageSquare, Plus, Search,
} from 'lucide-react';
import { useChatWindow } from '@/features/ai/chat/context/ChatWindowContext';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { ViewToggle } from '@/shared/components/ui/ViewToggle';
import type { AiAgent } from '@/shared/types/ai';

interface AgentsListTabProps {
  filteredAgents: AiAgent[];
  agentsLoading: boolean;
  agentSearchQuery: string;
  onSearchChange: (query: string) => void;
  agentViewMode: 'grid' | 'list';
  onViewModeChange: (mode: 'grid' | 'list') => void;
  canCreateAgents: boolean;
  canManageAgents: boolean;
  onCreateAgent: () => void;
  onToggleStatus: (agent: AiAgent) => void;
  onEditAgent: (agent: AiAgent) => void;
  onChatWithAgent: (agent: AiAgent) => void;
}

function getAgentStatusBadge(status: string) {
  switch (status) {
    case 'active':
      return <Badge variant="success" size="sm">Active</Badge>;
    case 'paused':
    case 'inactive':
      return <Badge variant="secondary" size="sm">Inactive</Badge>;
    case 'error':
      return <Badge variant="danger" size="sm">Error</Badge>;
    default:
      return <Badge variant="outline" size="sm">Unknown</Badge>;
  }
}

export const AgentsListTab: React.FC<AgentsListTabProps> = ({
  filteredAgents,
  agentsLoading,
  agentSearchQuery,
  onSearchChange,
  agentViewMode,
  onViewModeChange,
  canCreateAgents,
  canManageAgents,
  onCreateAgent,
  onToggleStatus,
  onEditAgent,
  onChatWithAgent,
}) => {
  const navigate = useNavigate();
  const { openConversationMaximized } = useChatWindow();

  const renderAgentCard = (agent: AiAgent) => (
    <Card
      key={agent.id}
      className="p-6 cursor-pointer hover:border-theme-info transition-colors"
      onClick={() => navigate(`/app/ai/agents/${agent.id}`)}
    >
      <div className="flex items-start justify-between mb-4">
        <div className="flex items-start gap-3">
          <div className="h-10 w-10 bg-theme-info bg-opacity-10 rounded-lg flex items-center justify-center">
            <Brain className="h-5 w-5 text-theme-info" />
          </div>
          <div>
            <h3 className="font-semibold text-theme-primary">{agent.name}</h3>
            <p className="text-sm text-theme-tertiary">{agent.description}</p>
          </div>
        </div>
        {getAgentStatusBadge(agent.status)}
      </div>

      <div className="space-y-3">
        <div className="flex items-center justify-between text-sm">
          <span className="text-theme-tertiary">AI Provider</span>
          <span className="text-theme-primary">{agent.provider?.name || 'N/A'}</span>
        </div>
        <div className="flex items-center justify-between text-sm">
          <span className="text-theme-tertiary">Model</span>
          <span className="text-theme-primary">{agent.model || 'N/A'}</span>
        </div>
        {agent.skill_slugs && agent.skill_slugs.length > 0 && (
          <div className="flex items-center justify-between text-sm">
            <span className="text-theme-tertiary">Skills</span>
            <div className="flex flex-wrap gap-1 justify-end">
              {agent.skill_slugs.slice(0, 3).map((slug) => (
                <Badge key={slug} variant="info" size="sm">{slug}</Badge>
              ))}
              {agent.skill_slugs.length > 3 && (
                <Badge variant="outline" size="sm">+{agent.skill_slugs.length - 3}</Badge>
              )}
            </div>
          </div>
        )}
        <div className="flex items-center justify-between text-sm">
          <span className="text-theme-tertiary">Executions</span>
          <span className="text-theme-primary">{agent.execution_stats?.total_executions || 0}</span>
        </div>
        {agent.updated_at && (
          <div className="flex items-center justify-between text-sm">
            <span className="text-theme-tertiary">Last Updated</span>
            <span className="text-theme-primary flex items-center gap-1">
              <Clock className="h-3 w-3" />
              {new Date(agent.updated_at).toLocaleDateString()}
            </span>
          </div>
        )}
      </div>

      <div className="flex items-center justify-between mt-4 pt-4 border-t border-theme" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center gap-2">
          {canManageAgents && (
            <Button
              variant={agent.status === 'active' ? 'warning' : 'success'}
              size="sm"
              className="flex items-center gap-1.5 min-w-[100px] justify-center"
              onClick={() => onToggleStatus(agent)}
            >
              {agent.status === 'active' ? (
                <><Pause className="h-3 w-3" />Pause</>
              ) : (
                <><Play className="h-3 w-3" />Start</>
              )}
            </Button>
          )}
          <Button
            variant="outline"
            size="sm"
            className="flex items-center gap-1.5 min-w-[80px] justify-center"
            onClick={() => onChatWithAgent(agent)}
          >
            <MessageSquare className="h-3 w-3" />Chat
          </Button>
        </div>
        <div className="flex items-center gap-2">
          <Button
            variant="outline"
            size="sm"
            className="flex items-center gap-1.5 min-w-[80px] justify-center"
            onClick={() => openConversationMaximized(agent.id, agent.name)}
          >
            Full Chat
          </Button>
          <Button
            variant="outline"
            size="sm"
            className="flex items-center gap-1.5 min-w-[80px] justify-center"
            onClick={() => onEditAgent(agent)}
          >
            <Settings className="h-3 w-3" />Manage
          </Button>
        </div>
      </div>
    </Card>
  );

  return (
    <>
      {/* Search + View Toggle */}
      <div className="flex items-center justify-between mb-6 gap-4">
        <div className="flex-1 min-w-64 max-w-sm">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-theme-muted" />
            <Input
              placeholder="Search agents..."
              value={agentSearchQuery}
              onChange={(e) => onSearchChange(e.target.value)}
              className="pl-10"
            />
          </div>
        </div>
        <ViewToggle viewMode={agentViewMode} onViewModeChange={onViewModeChange} />
      </div>

      {agentsLoading ? (
        <LoadingSpinner size="lg" className="py-12" message="Loading AI agents..." />
      ) : filteredAgents.length === 0 ? (
        <EmptyState
          icon={Brain}
          title="No AI agents found"
          description="Create your first AI agent to get started with automation"
          action={
            canCreateAgents ? (
              <Button variant="primary" size="md" className="flex items-center gap-2" onClick={onCreateAgent}>
                <Plus className="h-4 w-4" />Create Agent
              </Button>
            ) : undefined
          }
        />
      ) : agentViewMode === 'grid' ? (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
          {filteredAgents.map(renderAgentCard)}
        </div>
      ) : (
        <div className="bg-theme-surface border border-theme rounded-lg overflow-hidden">
          <table className="w-full">
            <thead>
              <tr className="border-b border-theme bg-theme-background">
                <th className="text-left px-4 py-3 text-xs font-semibold text-theme-secondary uppercase tracking-wide">Name</th>
                <th className="text-left px-4 py-3 text-xs font-semibold text-theme-secondary uppercase tracking-wide">Provider / Model</th>
                <th className="text-center px-4 py-3 text-xs font-semibold text-theme-secondary uppercase tracking-wide">Status</th>
                <th className="text-center px-4 py-3 text-xs font-semibold text-theme-secondary uppercase tracking-wide">Executions</th>
                <th className="text-right px-4 py-3 text-xs font-semibold text-theme-secondary uppercase tracking-wide">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-theme">
              {filteredAgents.map((agent) => (
                <tr
                  key={agent.id}
                  className="hover:bg-theme-background/50 transition-colors cursor-pointer"
                  onClick={() => navigate(`/app/ai/agents/${agent.id}`)}
                >
                  <td className="px-4 py-3">
                    <div>
                      <span className="text-sm font-medium text-theme-primary">{agent.name}</span>
                      {agent.description && (
                        <p className="text-xs text-theme-secondary line-clamp-1 mt-0.5">{agent.description}</p>
                      )}
                    </div>
                  </td>
                  <td className="px-4 py-3">
                    <div className="text-sm text-theme-primary">{agent.provider?.name || 'N/A'}</div>
                    <div className="text-xs text-theme-secondary">{agent.model || 'N/A'}</div>
                  </td>
                  <td className="px-4 py-3 text-center">
                    {getAgentStatusBadge(agent.status)}
                  </td>
                  <td className="px-4 py-3 text-center">
                    <span className="text-sm text-theme-primary">{agent.execution_stats?.total_executions || 0}</span>
                  </td>
                  <td className="px-4 py-3" onClick={(e) => e.stopPropagation()}>
                    <div className="flex items-center justify-end gap-1">
                      <button
                        onClick={() => onChatWithAgent(agent)}
                        className="p-1.5 rounded text-theme-secondary hover:bg-theme-accent hover:text-theme-primary transition-colors"
                        title="Chat"
                      >
                        <MessageSquare size={14} />
                      </button>
                      {canManageAgents && (
                        <button
                          onClick={() => onToggleStatus(agent)}
                          className="p-1.5 rounded text-theme-secondary hover:bg-theme-accent hover:text-theme-primary transition-colors"
                          title={agent.status === 'active' ? 'Pause' : 'Start'}
                        >
                          {agent.status === 'active' ? <Pause size={14} /> : <Play size={14} />}
                        </button>
                      )}
                      <button
                        onClick={() => onEditAgent(agent)}
                        className="p-1.5 rounded text-theme-secondary hover:bg-theme-accent hover:text-theme-primary transition-colors"
                        title="Manage"
                      >
                        <Settings size={14} />
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </>
  );
};
