import React, { useState, useEffect, useCallback } from 'react';
import { Users, Play, Trash2, Settings, BookOpen, BarChart3, Wrench, Loader2 } from 'lucide-react';
import { useTeamModal } from '@/shared/hooks/useTeamModal';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotification } from '@/shared/hooks/useNotification';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { Modal } from '@/shared/components/ui/Modal';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { TeamOverviewTab } from './TeamOverviewTab';
import { TeamExecutionTab } from './TeamExecutionTab';
import { TeamConfigTab } from './TeamConfigTab';
import { TeamSkillCoverageTab } from './TeamSkillCoverageTab';
import TeamAnalyticsDashboard from './TeamAnalyticsDashboard';
import { ContextBrowser } from '@/features/ai/memory/components/ContextBrowser';
import { teamsApi } from '@/shared/services/ai/TeamsApiService';
import type { Team, TeamRole, TeamChannel, TeamExecution, TeamTemplate, TeamAnalytics } from '@/shared/services/ai/TeamsApiService';
import { STATUS_CONFIG, TOPOLOGY_LABELS } from '../constants/teamConstants';

const DETAIL_TABS = [
  { id: 'overview', label: 'Overview', icon: <Users className="h-3.5 w-3.5" /> },
  { id: 'execution', label: 'Execution', icon: <Play className="h-3.5 w-3.5" /> },
  { id: 'skills', label: 'Skills', icon: <Wrench className="h-3.5 w-3.5" /> },
  { id: 'configuration', label: 'Configuration', icon: <Settings className="h-3.5 w-3.5" /> },
  { id: 'knowledge', label: 'Knowledge', icon: <BookOpen className="h-3.5 w-3.5" /> },
  { id: 'analytics', label: 'Analytics', icon: <BarChart3 className="h-3.5 w-3.5" /> },
];

export const TeamDetailModal: React.FC = () => {
  const { teamId, isOpen, closeTeam } = useTeamModal();
  const { hasPermission } = usePermissions();
  const { showNotification } = useNotification();
  const { confirm, ConfirmationDialog } = useConfirmation();

  const canManage = hasPermission('ai.agents.manage');

  const [team, setTeam] = useState<Team | null>(null);
  const [roles, setRoles] = useState<TeamRole[]>([]);
  const [channels, setChannels] = useState<TeamChannel[]>([]);
  const [executions, setExecutions] = useState<TeamExecution[]>([]);
  const [templates, setTemplates] = useState<TeamTemplate[]>([]);
  const [teamAnalytics, setTeamAnalytics] = useState<TeamAnalytics | null>(null);
  const [loading, setLoading] = useState(false);
  const [activeTab, setActiveTab] = useState('overview');
  const [periodDays, setPeriodDays] = useState(30);

  useEffect(() => {
    if (!isOpen || !teamId) return;
    setActiveTab('overview');
    loadTeamDetail(teamId);
  }, [teamId, isOpen]);

  const loadTeamDetail = useCallback(async (id: string) => {
    setLoading(true);
    try {
      const [teamRes, rolesRes, channelsRes, executionsRes, templatesRes, analyticsRes] = await Promise.all([
        teamsApi.getTeam(id),
        teamsApi.listRoles(id),
        teamsApi.listChannels(id),
        teamsApi.listExecutions(id),
        teamsApi.listTemplates(),
        teamsApi.getTeamAnalytics(id, periodDays).catch(() => null),
      ]);
      // Handle both { team: Team } wrapper and direct Team response
      const teamData = (teamRes as { team?: Team }).team ?? teamRes;
      setTeam(teamData);
      setRoles(rolesRes.roles || []);
      setChannels(channelsRes.channels || []);
      setExecutions(executionsRes.executions || []);
      setTemplates(templatesRes.templates || []);
      setTeamAnalytics(analyticsRes);
    } catch {
      // Error handled by empty state
    } finally {
      setLoading(false);
    }
  }, [periodDays]);

  const handlePeriodChange = useCallback((days: number) => {
    setPeriodDays(days);
    if (teamId) {
      teamsApi.getTeamAnalytics(teamId, days)
        .then(setTeamAnalytics)
        .catch(() => setTeamAnalytics(null));
    }
  }, [teamId]);

  // --- Action handlers ---

  const handleExecute = useCallback(() => {
    if (!team) return;
    // Trigger execution through the team execution tab
    setActiveTab('execution');
  }, [team]);

  const handleDelete = useCallback(() => {
    if (!team) return;
    confirm({
      title: 'Delete Team',
      message: `Are you sure you want to delete "${team.name}"? This action cannot be undone.`,
      confirmLabel: 'Delete',
      variant: 'danger',
      onConfirm: async () => {
        await teamsApi.deleteTeam(team.id);
        showNotification(`${team.name} deleted`, 'success');
        closeTeam();
      },
    });
  }, [team, confirm, closeTeam, showNotification]);

  const handleExecutionAction = useCallback(async (executionId: string, action: 'pause' | 'resume' | 'cancel') => {
    try {
      if (action === 'pause') {
        await teamsApi.pauseExecution(executionId);
      } else if (action === 'resume') {
        await teamsApi.resumeExecution(executionId);
      } else {
        await teamsApi.cancelExecution(executionId);
      }
      showNotification(`Execution ${action}d`, 'success');
      if (teamId) loadTeamDetail(teamId);
    } catch {
      showNotification(`Failed to ${action} execution`, 'error');
    }
  }, [teamId, loadTeamDetail, showNotification]);

  const handlePublishTemplate = useCallback(async (templateId: string) => {
    try {
      await teamsApi.publishTemplate(templateId);
      showNotification('Template published', 'success');
      if (teamId) loadTeamDetail(teamId);
    } catch {
      showNotification('Failed to publish template', 'error');
    }
  }, [teamId, loadTeamDetail, showNotification]);

  // --- Render ---

  const renderContent = () => {
    if (loading && !team) {
      return (
        <div className="flex items-center justify-center py-20">
          <Loader2 className="w-6 h-6 text-theme-secondary animate-spin" />
        </div>
      );
    }

    if (!team) {
      return (
        <div className="flex items-center justify-center py-20">
          <p className="text-sm text-theme-tertiary">Team not found</p>
        </div>
      );
    }

    const statusConfig = STATUS_CONFIG[team.status] || STATUS_CONFIG.active;

    return (
      <div className="space-y-6">
        {/* Header */}
        <div className="flex items-start justify-between">
          <div className="flex items-center gap-3">
            <div className="h-10 w-10 bg-theme-info-bg rounded-lg flex items-center justify-center">
              <Users className="h-5 w-5 text-theme-info-fg" />
            </div>
            <div>
              <h2 className="text-lg font-semibold text-theme-primary">{team.name}</h2>
              <div className="flex items-center gap-2 mt-0.5">
                <Badge variant={statusConfig.variant} size="sm">{statusConfig.label}</Badge>
                <Badge variant="outline" size="xs">{TOPOLOGY_LABELS[team.team_topology] || team.team_topology}</Badge>
                {team.roles_count != null && (
                  <span className="text-xs text-theme-tertiary">{team.roles_count} roles {'\u00b7'} {team.channels_count ?? 0} channels</span>
                )}
              </div>
            </div>
          </div>

          {/* Action buttons */}
          <div className="flex items-center gap-1.5">
            <Button variant="outline" size="sm" onClick={handleExecute}>
              <Play className="h-3.5 w-3.5 mr-1" />
              Execute
            </Button>
            {canManage && (
              <Button variant="danger" size="sm" onClick={handleDelete}>
                <Trash2 className="h-3.5 w-3.5 mr-1" />
                Delete
              </Button>
            )}
          </div>
        </div>

        {/* Tabs */}
        <TabContainer
          tabs={DETAIL_TABS}
          activeTab={activeTab}
          onTabChange={setActiveTab}
          variant="underline"
          size="sm"
          compact
        >
          <TabPanel tabId="overview" activeTab={activeTab}>
            <TeamOverviewTab team={team} roles={roles} onDeleteTeam={() => handleDelete()} />
          </TabPanel>
          <TabPanel tabId="execution" activeTab={activeTab}>
            <TeamExecutionTab
              team={team}
              executions={executions}
              onStartExecution={handleExecute}
              onExecutionAction={handleExecutionAction}
            />
          </TabPanel>
          <TabPanel tabId="skills" activeTab={activeTab}>
            <TeamSkillCoverageTab teamId={team.id} />
          </TabPanel>
          <TabPanel tabId="configuration" activeTab={activeTab}>
            <TeamConfigTab
              roles={roles}
              channels={channels}
              templates={templates}
              onPublishTemplate={handlePublishTemplate}
            />
          </TabPanel>
          <TabPanel tabId="knowledge" activeTab={activeTab}>
            <ContextBrowser linkToDetail />
          </TabPanel>
          <TabPanel tabId="analytics" activeTab={activeTab}>
            {teamAnalytics ? (
              <TeamAnalyticsDashboard analytics={teamAnalytics} onPeriodChange={handlePeriodChange} />
            ) : (
              <EmptyAnalytics />
            )}
          </TabPanel>
        </TabContainer>
      </div>
    );
  };

  return (
    <>
      <Modal
        isOpen={isOpen}
        onClose={closeTeam}
        title=""
        maxWidth="5xl"
        variant="centered"
        disableContentScroll
      >
        {renderContent()}
      </Modal>

      {ConfirmationDialog}
    </>
  );
};

function EmptyAnalytics() {
  return (
    <div className="flex flex-col items-center justify-center py-12 px-4">
      <BarChart3 className="w-10 h-10 text-theme-tertiary mb-3" />
      <p className="text-sm text-theme-tertiary">No analytics data available yet</p>
      <p className="text-xs text-theme-tertiary mt-1">Run some team executions to see analytics</p>
    </div>
  );
}
