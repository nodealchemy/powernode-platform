import React, { useState, useEffect, useCallback } from 'react';
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
import { useAgentModal } from '@/shared/hooks/useAgentModal';
import { useAgentDetail } from '../hooks/useAgentDetail';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotification } from '@/shared/hooks/useNotification';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { useChatWindow } from '@/features/ai/chat/context/ChatWindowContext';
import { agentsApi } from '@/shared/services/ai';
import { Modal } from '@/shared/components/ui/Modal';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/shared/components/ui/Tabs';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { DropdownMenu } from '@/shared/components/ui/DropdownMenu';
import { EntityLink } from '@/shared/components/entity';
import { AgentDetailStatsCards } from './AgentDetailStatsCards';
import { AgentConfigTab } from './detail-tabs/AgentConfigTab';
import { AgentHistoryTab } from './detail-tabs/AgentHistoryTab';
import { AgentTeamsTab } from './detail-tabs/AgentTeamsTab';
import { AgentSkillsTab } from './detail-tabs/AgentSkillsTab';
import { AgentWorkspacesTab } from './detail-tabs/AgentWorkspacesTab';
import { EditAgentModal } from './EditAgentModal';
import { STATUS_CONFIG, AGENT_TYPE_LABELS, TRUST_CONFIG } from '../constants/agentConstants';
import { cn } from '@/shared/utils/cn';

export const AgentDetailModal: React.FC = () => {
  const { agentId, isOpen, closeAgent } = useAgentModal();
  const { agent, stats, analytics, loading, error, reload } = useAgentDetail(agentId);
  const { hasPermission } = usePermissions();
  const { showNotification } = useNotification();
  const { openConversationMaximized } = useChatWindow();
  const { confirm, ConfirmationDialog } = useConfirmation();

  const canManage = hasPermission('ai.agents.manage');

  const [activeDetailTab, setActiveDetailTab] = useState('config');
  const [showEditModal, setShowEditModal] = useState(false);

  // Reset tab when agent changes
  useEffect(() => {
    setActiveDetailTab('config');
  }, [agentId]);

  // --- Action handlers ---

  const handleChat = useCallback(() => {
    if (agent) {
      openConversationMaximized(agent.id, agent.name);
    }
  }, [agent, openConversationMaximized]);

  const handleClone = useCallback(async () => {
    if (!agent) return;
    try {
      const cloned = await agentsApi.cloneAgent(agent.id);
      showNotification(`Cloned as "${cloned.name}"`, 'success');
      reload();
    } catch {
      showNotification('Failed to clone agent', 'error');
    }
  }, [agent, reload, showNotification]);

  const handleEdit = useCallback(() => {
    setShowEditModal(true);
  }, []);

  const handleToggleStatus = useCallback(async () => {
    if (!agent) return;
    try {
      if (agent.status === 'active') {
        await agentsApi.pauseAgent(agent.id);
        showNotification(`${agent.name} paused`, 'success');
      } else {
        await agentsApi.resumeAgent(agent.id);
        showNotification(`${agent.name} resumed`, 'success');
      }
      reload();
    } catch {
      showNotification('Failed to update agent status', 'error');
    }
  }, [agent, reload, showNotification]);

  const handleArchive = useCallback(async () => {
    if (!agent) return;
    try {
      await agentsApi.archiveAgent(agent.id);
      showNotification(`${agent.name} archived`, 'success');
      closeAgent();
    } catch {
      showNotification('Failed to archive agent', 'error');
    }
  }, [agent, closeAgent, showNotification]);

  const handleDelete = useCallback(() => {
    if (!agent) return;
    confirm({
      title: 'Delete Agent',
      message: `Are you sure you want to delete "${agent.name}"? This action cannot be undone.`,
      confirmLabel: 'Delete',
      variant: 'danger',
      onConfirm: async () => {
        await agentsApi.deleteAgent(agent.id);
        showNotification(`${agent.name} deleted`, 'success');
        closeAgent();
      },
    });
  }, [agent, confirm, closeAgent, showNotification]);

  const handleAgentUpdated = useCallback(() => {
    setShowEditModal(false);
    reload();
  }, [reload]);

  const handleAgentDeleted = useCallback(() => {
    setShowEditModal(false);
    closeAgent();
  }, [closeAgent]);

  // --- Derived data ---

  const status = agent ? (STATUS_CONFIG[agent.status] || STATUS_CONFIG.inactive) : null;
  const successRate = stats?.success_rate ?? agent?.execution_stats?.success_rate ?? 0;
  const trustLevel = agent ? (agent as { trust_level?: string }).trust_level : undefined;
  const trustConfig = trustLevel ? TRUST_CONFIG[trustLevel] : undefined;
  const version = agent
    ? (agent as { mcp_tool_manifest?: { version?: string } }).mcp_tool_manifest?.version
    : undefined;

  // --- Modal content ---

  const renderContent = () => {
    // Loading state
    if (loading && !agent) {
      return (
        <div className="flex items-center justify-center py-20">
          <Loader2 className="w-6 h-6 text-theme-secondary animate-spin" />
        </div>
      );
    }

    // Error state
    if (error && !agent) {
      return (
        <div className="flex items-center justify-center py-20">
          <p className="text-sm text-theme-error-fg">{error}</p>
        </div>
      );
    }

    if (!agent || !status) return null;

    return (
      <div className="space-y-6">
        {/* Header */}
        <div className="flex items-start justify-between">
          <div className="flex items-center gap-3">
            <div>
              <div className="flex items-center gap-2">
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
                    {agent.provider.id ? (
                      <EntityLink type="ai_provider" id={agent.provider.id} label={agent.provider.name} className="text-xs" />
                    ) : (
                      agent.provider.name
                    )}
                    {agent.model ? ` · ${agent.model}` : ''}
                  </span>
                )}
              </div>
            </div>
          </div>

          {/* Action buttons */}
          <div className="flex items-center gap-1.5">
            <Button variant="outline" size="sm" onClick={handleChat}>
              <MessageSquare className="h-3.5 w-3.5 mr-1" />
              Chat
            </Button>
            {canManage && (
              <>
                <Button variant="outline" size="sm" onClick={handleClone} title="Clone agent">
                  <Copy className="h-3.5 w-3.5 mr-1" />
                  Clone
                </Button>
                <Button variant="outline" size="sm" onClick={handleEdit}>
                  <Settings className="h-3.5 w-3.5 mr-1" />
                  Edit
                </Button>
                <Button
                  variant={agent.status === 'active' ? 'warning' : 'success'}
                  size="sm"
                  onClick={handleToggleStatus}
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
                    { icon: Archive, label: 'Archive', onClick: handleArchive },
                    { icon: Trash2, label: 'Delete', onClick: handleDelete, danger: true },
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
                successRate >= 80 ? 'text-theme-success-fg' :
                successRate >= 50 ? 'text-theme-warning-fg' :
                'text-theme-error-fg'
              )}>
                {successRate}%
              </span>
            </div>
            <div className="h-2 bg-theme-background-secondary rounded-full overflow-hidden">
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
        <Tabs value={activeDetailTab} onValueChange={setActiveDetailTab}>
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
    );
  };

  return (
    <>
      <Modal
        isOpen={isOpen}
        onClose={closeAgent}
        title={agent?.name ?? 'Agent'}
        icon={<Brain className="w-6 h-6" />}
        maxWidth="5xl"
        variant="centered"
        disableContentScroll
      >
        {renderContent()}
      </Modal>

      <EditAgentModal
        isOpen={showEditModal}
        onClose={() => setShowEditModal(false)}
        agent={agent}
        onAgentUpdated={handleAgentUpdated}
        onAgentDeleted={handleAgentDeleted}
      />

      {ConfirmationDialog}
    </>
  );
};
