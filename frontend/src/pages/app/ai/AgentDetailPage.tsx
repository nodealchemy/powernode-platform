import React, { useState, useEffect, useCallback } from 'react';
import { useParams, useNavigate, useLocation } from 'react-router-dom';
import {
  MessageSquare, ArrowLeft, BookOpen, Lightbulb, Copy, Settings, Play, Pause, Archive, Trash2, Shield,
} from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotification } from '@/shared/hooks/useNotification';
import { agentsApi, intelligenceApi } from '@/shared/services/ai';
import type { ExperienceReplay, IntelligenceSummary } from '@/shared/services/ai/IntelligenceApiService';
import { AgentConnectionsGraph } from '@/features/ai/agents/components/AgentConnectionsGraph';
import { ContextBrowser } from '@/features/ai/memory/components/ContextBrowser';
import { useChatWindow } from '@/features/ai/chat/context/ChatWindowContext';
import { useAgentDetail } from '@/features/ai/agents/hooks/useAgentDetail';
import { AgentDetailStatsCards } from '@/features/ai/agents/components/AgentDetailStatsCards';
import { AgentPerformanceSummary } from '@/features/ai/agents/components/AgentPerformanceSummary';
import { AgentConfigTab } from '@/features/ai/agents/components/detail-tabs/AgentConfigTab';
import { AgentHistoryTab } from '@/features/ai/agents/components/detail-tabs/AgentHistoryTab';
import { AgentTeamsTab } from '@/features/ai/agents/components/detail-tabs/AgentTeamsTab';
import { AgentSkillsTab } from '@/features/ai/agents/components/detail-tabs/AgentSkillsTab';
import { AgentWorkspacesTab } from '@/features/ai/agents/components/detail-tabs/AgentWorkspacesTab';
import { AgentMemoryTab } from '@/features/ai/agents/components/detail-tabs/AgentMemoryTab';
import { EditAgentModal } from '@/features/ai/agents/components/EditAgentModal';
import { STATUS_CONFIG, AGENT_TYPE_LABELS, TRUST_CONFIG } from '@/features/ai/agents/constants/agentConstants';

// fc-43: the one agent detail surface. The former global AgentDetailModal's
// tabs and manage actions live here, and the per-agent memory page is the
// Memory tab at the same URL. Each tab is at its own path.
const tabs = [
  { id: 'overview', label: 'Overview', path: '/' },
  { id: 'history', label: 'History', path: '/history' },
  { id: 'teams', label: 'Teams', path: '/teams' },
  { id: 'skills', label: 'Skills', path: '/skills' },
  { id: 'workspaces', label: 'Workspaces', path: '/workspaces' },
  // Gated like the endpoints they read: ContextsController and
  // AgentMemoryController authorize ai.context.read / ai.memory.read.
  { id: 'knowledge', label: 'Knowledge', path: '/knowledge', permissions: ['ai.context.read'] },
  { id: 'memory', label: 'Memory', path: '/memory', permissions: ['ai.memory.read'] },
  { id: 'intelligence', label: 'Intelligence', path: '/intelligence' },
  { id: 'connections', label: 'Connections', path: '/connections' },
];

// ---- Intelligence Tab Content ----
const IntelligenceContent: React.FC<{ agentId: string }> = ({ agentId }) => {
  const [summary, setSummary] = useState<IntelligenceSummary | null>(null);
  const [replays, setReplays] = useState<ExperienceReplay[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const load = async () => {
      setLoading(true);
      const [summaryRes, replaysRes] = await Promise.all([
        intelligenceApi.getIntelligenceSummary(agentId).catch(() => null),
        intelligenceApi.getExperienceReplays(agentId, { per_page: 10 }).catch(() => null),
      ]);
      if (summaryRes?.summary) setSummary(summaryRes.summary);
      if (replaysRes?.items) setReplays(replaysRes.items);
      setLoading(false);
    };
    load();
  }, [agentId]);

  if (loading) return <LoadingSpinner size="md" className="py-8" message="Loading intelligence data..." />;

  return (
    <div className="space-y-6">
      {/* Summary Cards */}
      {summary && (
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <Card className="p-4 text-center">
            <div className="text-2xl font-bold text-theme-primary">{summary.experience_replays.active}</div>
            <div className="text-xs text-theme-tertiary">Active Replays</div>
            <div className="text-xs text-theme-secondary mt-1">Avg Quality: {(summary.experience_replays.avg_quality * 100).toFixed(0)}%</div>
          </Card>
          <Card className="p-4 text-center">
            <div className="text-2xl font-bold text-theme-primary">{(summary.experience_replays.avg_effectiveness * 100).toFixed(0)}%</div>
            <div className="text-xs text-theme-tertiary">Replay Effectiveness</div>
            <div className="text-xs text-theme-secondary mt-1">{summary.experience_replays.total} total</div>
          </Card>
        </div>
      )}

      {/* Experience Replays */}
      <Card className="p-6">
        <div className="flex items-center gap-2 mb-4">
          <Lightbulb size={18} className="text-theme-warning-fg" />
          <h3 className="text-lg font-medium text-theme-primary">Experience Replays</h3>
          <Badge variant="secondary" size="sm">{replays.length}</Badge>
        </div>
        {replays.length === 0 ? (
          <p className="text-sm text-theme-tertiary">No experience replays captured yet. Replays are created from successful executions.</p>
        ) : (
          <div className="space-y-3">
            {replays.map(r => (
              <div key={r.id} className="border border-theme rounded-lg p-3">
                <div className="flex items-start justify-between mb-2">
                  <div className="flex items-center gap-2">
                    <Badge variant={r.status === 'active' ? 'success' : 'secondary'} size="sm">{r.status}</Badge>
                    <span className="text-xs text-theme-tertiary">{new Date(r.created_at).toLocaleDateString()}</span>
                  </div>
                  <div className="flex items-center gap-3 text-xs">
                    <span className="text-theme-secondary">Quality: <strong>{((r.quality_score || 0) * 100).toFixed(0)}%</strong></span>
                    <span className="text-theme-secondary">Effect: <strong>{((r.effectiveness_score || 0) * 100).toFixed(0)}%</strong></span>
                    <span className="text-theme-tertiary">Injected {r.injection_count}x</span>
                  </div>
                </div>
                <p className="text-sm text-theme-secondary line-clamp-2">{r.compressed_example}</p>
              </div>
            ))}
          </div>
        )}
      </Card>

    </div>
  );
};

export const AgentDetailPage: React.FC = () => {
  const { agentId } = useParams<{ agentId: string }>();
  const navigate = useNavigate();
  const location = useLocation();
  const { openConversationMaximized } = useChatWindow();
  const { hasPermission } = usePermissions();
  const { showNotification } = useNotification();
  const { confirm, ConfirmationDialog } = useConfirmation();
  const { agent, stats, analytics, error, reload } = useAgentDetail(agentId ?? null);
  const [showEditModal, setShowEditModal] = useState(false);

  const canManage = hasPermission('ai.agents.manage');
  const basePath = `/app/ai/agents/${agentId}`;

  // The first path segment after the agent picks the tab; a tab the viewer
  // may not see falls back to Overview rather than rendering its panel.
  const segment = location.pathname.startsWith(basePath)
    ? location.pathname.slice(basePath.length).split('/')[1] || ''
    : '';
  const matched = tabs.find((t) => t.path === `/${segment}`);
  const activeTab = matched && (!matched.permissions || matched.permissions.every((p) => hasPermission(p)))
    ? matched.id
    : 'overview';

  useEffect(() => {
    if (error && !agent) navigate('/app/ai/agents');
  }, [error, agent, navigate]);

  const goToList = useCallback(() => navigate('/app/ai/agents'), [navigate]);

  const handleClone = useCallback(async () => {
    if (!agent) return;
    try {
      const cloned = await agentsApi.cloneAgent(agent.id);
      showNotification(`Cloned as "${cloned.name}"`, 'success');
      navigate(`/app/ai/agents/${cloned.id}`);
    } catch {
      showNotification('Failed to clone agent', 'error');
    }
  }, [agent, navigate, showNotification]);

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
      goToList();
    } catch {
      showNotification('Failed to archive agent', 'error');
    }
  }, [agent, goToList, showNotification]);

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
        goToList();
      },
    });
  }, [agent, confirm, goToList, showNotification]);

  if (!agent) {
    return <LoadingSpinner size="lg" className="py-12" message="Loading agent..." />;
  }

  const status = STATUS_CONFIG[agent.status] || STATUS_CONFIG.inactive;
  const trustLevel = (agent as { trust_level?: string }).trust_level;
  const trustConfig = trustLevel ? TRUST_CONFIG[trustLevel] : undefined;
  const version = (agent as { mcp_tool_manifest?: { version?: string } }).mcp_tool_manifest?.version;

  const pageActions = [
    { id: 'back', label: 'Back to Agents', onClick: goToList, variant: 'secondary' as const, icon: ArrowLeft },
    {
      id: 'chat',
      label: 'Chat',
      onClick: () => openConversationMaximized(agent.id, agent.name),
      variant: 'outline' as const,
      icon: MessageSquare,
    },
    ...(canManage
      ? [
          { id: 'clone', label: 'Clone', onClick: handleClone, variant: 'outline' as const, icon: Copy },
          { id: 'edit', label: 'Edit', onClick: () => setShowEditModal(true), variant: 'outline' as const, icon: Settings },
          agent.status === 'active'
            ? { id: 'pause', label: 'Pause', onClick: handleToggleStatus, variant: 'warning' as const, icon: Pause }
            : { id: 'resume', label: 'Resume', onClick: handleToggleStatus, variant: 'success' as const, icon: Play },
          { id: 'archive', label: 'Archive', onClick: handleArchive, variant: 'secondary' as const, icon: Archive },
          { id: 'delete', label: 'Delete', onClick: handleDelete, variant: 'danger' as const, icon: Trash2 },
        ]
      : []),
  ];

  const getBreadcrumbs = () => {
    const base: Array<{ label: string; href?: string }> = [
      { label: 'Dashboard', href: '/app' },
      { label: 'AI', href: '/app/ai' },
      { label: 'Agents', href: '/app/ai/agents' },
      { label: agent.name },
    ];
    const activeTabInfo = tabs.find(t => t.id === activeTab);
    if (activeTabInfo && activeTab !== 'overview') {
      base.push({ label: activeTabInfo.label });
    }
    return base;
  };

  return (
    <PageContainer
      title={agent.name}
      description={agent.description || 'AI Agent'}
      breadcrumbs={getBreadcrumbs()}
      actions={pageActions}
    >
      <TabContainer
        tabs={tabs}
        activeTab={activeTab}
        basePath={basePath}
        variant="underline"
        className="mb-6"
      >
        <TabPanel tabId="overview" activeTab={activeTab}>
          <div className="space-y-6">
            <div className="flex flex-wrap items-center gap-2">
              <Badge variant={status.variant} size="sm">{status.label}</Badge>
              <Badge variant="outline" size="xs">{AGENT_TYPE_LABELS[agent.agent_type] || agent.agent_type}</Badge>
              {trustConfig && (
                <Badge variant={trustConfig.variant} size="xs">
                  {trustConfig.icon && <Shield className="h-2.5 w-2.5 mr-0.5" />}
                  {trustConfig.label}
                </Badge>
              )}
              {version && <Badge variant="outline" size="xs">v{version}</Badge>}
            </div>

            <AgentPerformanceSummary
              stats={stats}
              analytics={analytics}
              fallbackSuccessRate={agent.execution_stats?.success_rate ?? 0}
            />
            {stats && stats.total_executions > 0 && <AgentDetailStatsCards stats={stats} />}

            <AgentConfigTab agent={agent} />
          </div>
        </TabPanel>

        <TabPanel tabId="history" activeTab={activeTab}>
          <AgentHistoryTab agentId={agent.id} />
        </TabPanel>

        <TabPanel tabId="teams" activeTab={activeTab}>
          <AgentTeamsTab agentId={agent.id} />
        </TabPanel>

        <TabPanel tabId="skills" activeTab={activeTab}>
          <div className="space-y-4">
            <div className="text-xs">
              <button
                type="button"
                onClick={() => navigate('/app/ai/skills/graph')}
                className="text-theme-info-fg hover:underline"
              >
                View skills in graph →
              </button>
            </div>
            <AgentSkillsTab agentId={agent.id} />
          </div>
        </TabPanel>

        <TabPanel tabId="workspaces" activeTab={activeTab}>
          <AgentWorkspacesTab agentId={agent.id} />
        </TabPanel>

        <TabPanel tabId="knowledge" activeTab={activeTab}>
          <div className="space-y-4">
            <div className="flex items-center gap-2 mb-4">
              <BookOpen size={18} className="text-theme-secondary" />
              <h3 className="text-lg font-medium text-theme-primary">Agent Knowledge & Contexts</h3>
            </div>
            <ContextBrowser
              filters={{ ai_agent_id: agent.id }}
              linkToDetail
            />
          </div>
        </TabPanel>

        <TabPanel tabId="memory" activeTab={activeTab}>
          <AgentMemoryTab agentId={agent.id} />
        </TabPanel>

        <TabPanel tabId="intelligence" activeTab={activeTab}>
          <IntelligenceContent agentId={agent.id} />
        </TabPanel>

        <TabPanel tabId="connections" activeTab={activeTab}>
          <AgentConnectionsGraph agentId={agent.id} />
        </TabPanel>
      </TabContainer>

      <EditAgentModal
        isOpen={showEditModal}
        onClose={() => setShowEditModal(false)}
        agent={agent}
        onAgentUpdated={() => {
          setShowEditModal(false);
          reload();
        }}
        onAgentDeleted={() => {
          setShowEditModal(false);
          goToList();
        }}
      />

      {ConfirmationDialog}
    </PageContainer>
  );
};

export default AgentDetailPage;
