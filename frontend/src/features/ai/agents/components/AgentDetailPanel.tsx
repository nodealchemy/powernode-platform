import React from 'react';
import {
  Brain,
  MessageSquare,
  Settings,
  Play,
  Pause,
  Trash2,
  Loader2,
} from 'lucide-react';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/shared/components/ui/Tabs';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { AgentDetailStatsCards } from './AgentDetailStatsCards';
import { AgentConfigTab } from './detail-tabs/AgentConfigTab';
import { AgentHistoryTab } from './detail-tabs/AgentHistoryTab';
import { AgentTeamsTab } from './detail-tabs/AgentTeamsTab';
import { AgentSkillsTab } from './detail-tabs/AgentSkillsTab';
import { AgentWorkspacesTab } from './detail-tabs/AgentWorkspacesTab';
import { cn } from '@/shared/utils/cn';
import type { AiAgent } from '@/shared/types/ai';
import type { AgentStats } from '@/shared/services/ai/types/agent-api-types';

const STATUS_CONFIG: Record<AiAgent['status'], {
  variant: 'success' | 'warning' | 'danger' | 'info' | 'outline';
  label: string;
}> = {
  active: { variant: 'success', label: 'Active' },
  inactive: { variant: 'outline', label: 'Inactive' },
  error: { variant: 'danger', label: 'Error' },
};

const AGENT_TYPE_LABELS: Record<string, string> = {
  assistant: 'Assistant',
  code_assistant: 'Code',
  data_analyst: 'Data',
  content_generator: 'Content',
  image_generator: 'Image',
  workflow_optimizer: 'Workflow',
  workflow_operations: 'Ops',
};

interface AgentDetailPanelProps {
  agent: AiAgent | null;
  stats: AgentStats | null;
  loading: boolean;
  error: string | null;
  activeTab: string;
  onActiveTabChange: (tab: string) => void;
  onChat: () => void;
  onEdit: () => void;
  onToggleStatus: () => void;
  onDelete: () => void;
  canManage: boolean;
}

export const AgentDetailPanel: React.FC<AgentDetailPanelProps> = ({
  agent,
  stats,
  loading,
  error,
  activeTab,
  onActiveTabChange,
  onChat,
  onEdit,
  onToggleStatus,
  onDelete,
  canManage,
}) => {
  // Empty state
  if (!agent && !loading && !error) {
    return (
      <div className="flex-1 flex items-center justify-center">
        <div className="text-center">
          <Brain className="w-12 h-12 text-theme-tertiary mx-auto mb-3" />
          <p className="text-sm text-theme-secondary">Select an agent to view details</p>
        </div>
      </div>
    );
  }

  // Loading state
  if (loading && !agent) {
    return (
      <div className="flex-1 flex items-center justify-center">
        <Loader2 className="w-6 h-6 text-theme-secondary animate-spin" />
      </div>
    );
  }

  // Error state
  if (error && !agent) {
    return (
      <div className="flex-1 flex items-center justify-center">
        <p className="text-sm text-theme-error">{error}</p>
      </div>
    );
  }

  if (!agent) return null;

  const status = STATUS_CONFIG[agent.status] || STATUS_CONFIG.inactive;
  const successRate = stats?.success_rate ?? agent.execution_stats?.success_rate ?? 0;

  return (
    <div className="flex-1 overflow-y-auto p-6">
      <div className="space-y-6">
        {/* Header */}
        <div className="flex items-start justify-between">
          <div className="flex items-center gap-3">
            <div className="h-10 w-10 bg-theme-info bg-opacity-10 rounded-lg flex items-center justify-center">
              <Brain className="h-5 w-5 text-theme-info" />
            </div>
            <div>
              <h2 className="text-lg font-semibold text-theme-primary">{agent.name}</h2>
              <div className="flex items-center gap-2 mt-0.5">
                <Badge variant={status.variant} size="sm">{status.label}</Badge>
                <Badge variant="outline" size="xs">
                  {AGENT_TYPE_LABELS[agent.agent_type] || agent.agent_type}
                </Badge>
                {agent.provider?.name && (
                  <span className="text-xs text-theme-tertiary">
                    {agent.provider.name}{agent.model ? ` · ${agent.model}` : ''}
                  </span>
                )}
              </div>
            </div>
          </div>

          {/* Action buttons */}
          <div className="flex items-center gap-1.5">
            <Button variant="outline" size="sm" onClick={onChat}>
              <MessageSquare className="h-3.5 w-3.5 mr-1" />
              Chat
            </Button>
            {canManage && (
              <>
                <Button variant="ghost" size="sm" onClick={onEdit}>
                  <Settings className="h-3.5 w-3.5 mr-1" />
                  Edit
                </Button>
                <Button
                  variant={agent.status === 'active' ? 'warning' : 'success'}
                  size="sm"
                  onClick={onToggleStatus}
                >
                  {agent.status === 'active'
                    ? <><Pause className="h-3.5 w-3.5 mr-1" />Pause</>
                    : <><Play className="h-3.5 w-3.5 mr-1" />Resume</>
                  }
                </Button>
                <Button variant="danger" size="sm" iconOnly onClick={onDelete} title="Delete agent">
                  <Trash2 className="h-3.5 w-3.5" />
                </Button>
              </>
            )}
          </div>
        </div>

        {/* Success Rate Bar */}
        {stats && stats.total_executions > 0 && (
          <div>
            <div className="flex items-center justify-between mb-1.5">
              <span className="text-xs text-theme-secondary">Success Rate</span>
              <span className={cn(
                'text-xs font-medium',
                successRate >= 80 ? 'text-theme-success' :
                successRate >= 50 ? 'text-theme-warning' :
                'text-theme-error'
              )}>
                {successRate}%
              </span>
            </div>
            <div className="h-2 bg-theme-bg-secondary rounded-full overflow-hidden">
              <div
                className={cn(
                  'h-full rounded-full transition-all duration-500',
                  successRate >= 80 ? 'bg-theme-status-success' :
                  successRate >= 50 ? 'bg-theme-status-warning' :
                  'bg-theme-status-error'
                )}
                style={{ width: `${successRate}%` }}
              />
            </div>
          </div>
        )}

        {/* Stats Cards */}
        {stats && stats.total_executions > 0 && <AgentDetailStatsCards stats={stats} />}

        {/* Tabs */}
        <Tabs value={activeTab} onValueChange={onActiveTabChange}>
          <TabsList>
            <TabsTrigger value="config">Config</TabsTrigger>
            <TabsTrigger value="history">History</TabsTrigger>
            <TabsTrigger value="teams">Teams</TabsTrigger>
            <TabsTrigger value="skills">Skills</TabsTrigger>
            <TabsTrigger value="workspaces">Workspaces</TabsTrigger>
          </TabsList>

          <TabsContent value="config" className="mt-4">
            <AgentConfigTab agent={agent} />
          </TabsContent>

          <TabsContent value="history" className="mt-4">
            <AgentHistoryTab agentId={agent.id} />
          </TabsContent>

          <TabsContent value="teams" className="mt-4">
            <AgentTeamsTab agentId={agent.id} />
          </TabsContent>

          <TabsContent value="skills" className="mt-4">
            <AgentSkillsTab agentId={agent.id} />
          </TabsContent>

          <TabsContent value="workspaces" className="mt-4">
            <AgentWorkspacesTab agentId={agent.id} />
          </TabsContent>
        </Tabs>
      </div>
    </div>
  );
};
