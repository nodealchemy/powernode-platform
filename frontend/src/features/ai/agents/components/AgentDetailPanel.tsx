import React from 'react';
import {
  Brain,
  MessageSquare,
  Settings,
  Play,
  Pause,
  Trash2,
  Loader2,
  Copy,
  MoreVertical,
  Shield,
  Archive,
} from 'lucide-react';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/shared/components/ui/Tabs';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { DropdownMenu } from '@/shared/components/ui/DropdownMenu';
import { AgentDetailStatsCards } from './AgentDetailStatsCards';
import { AgentConfigTab } from './detail-tabs/AgentConfigTab';
import { AgentHistoryTab } from './detail-tabs/AgentHistoryTab';
import { AgentTeamsTab } from './detail-tabs/AgentTeamsTab';
import { AgentSkillsTab } from './detail-tabs/AgentSkillsTab';
import { AgentWorkspacesTab } from './detail-tabs/AgentWorkspacesTab';
import { cn } from '@/shared/utils/cn';
import type { AiAgent } from '@/shared/types/ai';
import type { AgentStats, AgentAnalytics } from '@/shared/services/ai/types/agent-api-types';

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

const TRUST_CONFIG: Record<string, {
  variant: 'outline' | 'info' | 'success' | 'primary';
  label: string;
  icon?: boolean;
}> = {
  supervised: { variant: 'outline', label: 'Supervised', icon: true },
  monitored: { variant: 'info', label: 'Monitored' },
  trusted: { variant: 'success', label: 'Trusted' },
  autonomous: { variant: 'primary', label: 'Autonomous' },
};

interface AgentDetailPanelProps {
  agent: AiAgent | null;
  stats: AgentStats | null;
  analytics: AgentAnalytics | null;
  loading: boolean;
  error: string | null;
  activeTab: string;
  onActiveTabChange: (tab: string) => void;
  onChat: () => void;
  onEdit: () => void;
  onClone: () => void;
  onToggleStatus: () => void;
  onDelete: () => void;
  onArchive: () => void;
  canManage: boolean;
}

export const AgentDetailPanel: React.FC<AgentDetailPanelProps> = ({
  agent,
  stats,
  analytics,
  loading,
  error,
  activeTab,
  onActiveTabChange,
  onChat,
  onEdit,
  onClone,
  onToggleStatus,
  onDelete,
  onArchive,
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
  const trustLevel = (agent as { trust_level?: string }).trust_level;
  const trustConfig = trustLevel ? TRUST_CONFIG[trustLevel] : undefined;
  const version = (agent as { mcp_tool_manifest?: { version?: string } }).mcp_tool_manifest?.version;

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
                {trustConfig && (
                  <Badge variant={trustConfig.variant} size="xs">
                    {trustConfig.icon && <Shield className="h-2.5 w-2.5 mr-0.5" />}
                    {trustConfig.label}
                  </Badge>
                )}
                {version && (
                  <Badge variant="outline" size="xs">v{version}</Badge>
                )}
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
                <Button variant="outline" size="sm" onClick={onClone} title="Clone agent">
                  <Copy className="h-3.5 w-3.5 mr-1" />
                  Clone
                </Button>
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
                <DropdownMenu
                  trigger={
                    <Button variant="ghost" size="sm" iconOnly title="More actions">
                      <MoreVertical className="h-3.5 w-3.5" />
                    </Button>
                  }
                  items={[
                    { icon: Archive, label: 'Archive', onClick: onArchive },
                    { icon: Trash2, label: 'Delete', onClick: onDelete, danger: true },
                  ]}
                  align="right"
                  width="w-40"
                />
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

        {/* Analytics Sparkline */}
        {analytics?.execution_trends && analytics.execution_trends.length > 1 && (() => {
          const trends = analytics.execution_trends;
          const maxCount = Math.max(...trends.map(t => t.count), 1);
          const svgWidth = 200;
          const svgHeight = 32;
          const points = trends.map((t, i) => {
            const x = (i / (trends.length - 1)) * svgWidth;
            const y = svgHeight - (t.count / maxCount) * (svgHeight - 4) - 2;
            return `${x},${y}`;
          }).join(' ');

          return (
            <div>
              <div className="flex items-center justify-between mb-1">
                <span className="text-xs text-theme-secondary">Executions (30d)</span>
                <span className="text-xs text-theme-tertiary">{trends.length} days</span>
              </div>
              <svg
                viewBox={`0 0 ${svgWidth} ${svgHeight}`}
                preserveAspectRatio="none"
                className="w-full"
                style={{ height: `${svgHeight}px` }}
              >
                <polyline
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="1.5"
                  className="text-theme-interactive-primary"
                  points={points}
                />
              </svg>
            </div>
          );
        })()}

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
