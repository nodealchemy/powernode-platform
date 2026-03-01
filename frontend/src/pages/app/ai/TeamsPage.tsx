// Teams Management Page - List/Detail Layout with 5 Consolidated Tabs
import React, { useState, useEffect, useCallback } from 'react';
import { Plus, Users, Play } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Modal } from '@/shared/components/ui/Modal';
import { useDispatch } from 'react-redux';
import { addNotification } from '@/shared/services/slices/uiSlice';
import { AppDispatch } from '@/shared/services';
import { useAiOrchestrationWebSocket } from '@/shared/hooks/useAiOrchestrationWebSocket';
import { useRefreshAction } from '@/shared/hooks/useRefreshAction';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import {
  teamsApi,
  Team,
  TeamRole,
  TeamChannel,
  TeamExecution,
  TeamTemplate,
  TeamAnalytics
} from '@/shared/services/ai/TeamsApiService';
import { TeamListPanel } from '@/features/ai/agent-teams/components/TeamListPanel';
import { TeamDetailPanel } from '@/features/ai/agent-teams/components/TeamDetailPanel';

interface ApiErrorResponse {
  response?: { data?: { error?: string } };
}

function isApiError(error: unknown): error is ApiErrorResponse {
  return typeof error === 'object' && error !== null && 'response' in error;
}

function getErrorMessage(error: unknown, fallback: string): string {
  if (isApiError(error)) return error.response?.data?.error || fallback;
  if (error instanceof Error) return error.message;
  return fallback;
}

const TeamsPage: React.FC = () => {
  const { confirm, ConfirmationDialog } = useConfirmation();
  const dispatch = useDispatch<AppDispatch>();
  const [teams, setTeams] = useState<Team[]>([]);
  const [selectedTeam, setSelectedTeam] = useState<Team | null>(null);
  const [roles, setRoles] = useState<TeamRole[]>([]);
  const [channels, setChannels] = useState<TeamChannel[]>([]);
  const [executions, setExecutions] = useState<TeamExecution[]>([]);
  const [templates, setTemplates] = useState<TeamTemplate[]>([]);
  const [teamAnalytics, setTeamAnalytics] = useState<TeamAnalytics | null>(null);
  const [loading, setLoading] = useState(true);
  const [periodDays, setPeriodDays] = useState(30);

  // Create team modal
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [newTeamName, setNewTeamName] = useState('');
  const [newTeamDescription, setNewTeamDescription] = useState('');
  const [newTeamTopology, setNewTeamTopology] = useState<string>('hierarchical');

  // Start execution modal
  const [showExecutionModal, setShowExecutionModal] = useState(false);
  const [executionObjective, setExecutionObjective] = useState('');

  useAiOrchestrationWebSocket({
    onWorkflowRunEvent: (event) => {
      if (['run_completed', 'run_failed', 'run_started'].includes(event.type)) {
        if (selectedTeam) loadTeamData(selectedTeam.id);
      }
    }
  });

  useEffect(() => { loadData(); }, []);

  const loadTeamData = useCallback(async (teamId: string) => {
    try {
      const [rolesRes, channelsRes, executionsRes, analyticsRes] = await Promise.all([
        teamsApi.listRoles(teamId),
        teamsApi.listChannels(teamId),
        teamsApi.listExecutions(teamId),
        teamsApi.getTeamAnalytics(teamId, periodDays).catch(() => null)
      ]);
      setRoles(rolesRes.roles || []);
      setChannels(channelsRes.channels || []);
      setExecutions(executionsRes.executions || []);
      setTeamAnalytics(analyticsRes);
    } catch (error) {
      dispatch(addNotification({ type: 'error', message: getErrorMessage(error, 'Failed to load team details') }));
    }
  }, [dispatch, periodDays]);

  useEffect(() => {
    if (selectedTeam) loadTeamData(selectedTeam.id);
  }, [selectedTeam, loadTeamData]);

  const loadData = async () => {
    try {
      setLoading(true);
      const [teamsRes, templatesRes] = await Promise.all([
        teamsApi.listTeams(),
        teamsApi.listTemplates()
      ]);
      setTeams(teamsRes.teams || []);
      setTemplates(templatesRes.templates || []);
      if (teamsRes.teams?.length > 0 && !selectedTeam) setSelectedTeam(teamsRes.teams[0]);
    } catch (error) {
      dispatch(addNotification({ type: 'error', message: getErrorMessage(error, 'Failed to load teams data') }));
    } finally {
      setLoading(false);
    }
  };

  const handleCreateTeam = async () => {
    if (!newTeamName.trim()) return;
    try {
      const team = await teamsApi.createTeam({
        name: newTeamName,
        description: newTeamDescription || undefined,
        team_topology: newTeamTopology as Team['team_topology']
      });
      dispatch(addNotification({ type: 'success', message: 'Team created' }));
      setTeams([...teams, team]);
      setSelectedTeam(team);
      setShowCreateModal(false);
      setNewTeamName('');
      setNewTeamDescription('');
    } catch (error) {
      dispatch(addNotification({ type: 'error', message: getErrorMessage(error, 'Failed to create team') }));
    }
  };

  const handleDeleteTeam = (teamId: string) => {
    const teamName = teams.find(t => t.id === teamId)?.name || 'this team';
    confirm({
      title: 'Delete Team',
      message: `Are you sure you want to delete "${teamName}"? This will permanently remove all roles, channels, and execution history.`,
      confirmLabel: 'Delete',
      variant: 'danger',
      onConfirm: async () => {
        try {
          await teamsApi.deleteTeam(teamId);
          dispatch(addNotification({ type: 'success', message: 'Team deleted' }));
          const remaining = teams.filter(t => t.id !== teamId);
          setTeams(remaining);
          if (selectedTeam?.id === teamId) setSelectedTeam(remaining[0] || null);
        } catch (error) {
          dispatch(addNotification({ type: 'error', message: getErrorMessage(error, 'Failed to delete team') }));
        }
      },
    });
  };

  const handleStartExecution = async () => {
    if (!selectedTeam || !executionObjective.trim()) return;
    try {
      const execution = await teamsApi.startExecution(selectedTeam.id, { objective: executionObjective });
      dispatch(addNotification({ type: 'success', message: 'Execution started' }));
      setExecutions([execution, ...executions]);
      setShowExecutionModal(false);
      setExecutionObjective('');
    } catch (error) {
      dispatch(addNotification({ type: 'error', message: getErrorMessage(error, 'Failed to start execution') }));
    }
  };

  const handleExecutionAction = async (executionId: string, action: 'pause' | 'resume' | 'cancel') => {
    try {
      if (action === 'pause') await teamsApi.pauseExecution(executionId);
      else if (action === 'resume') await teamsApi.resumeExecution(executionId);
      else await teamsApi.cancelExecution(executionId, 'Cancelled by user');
      dispatch(addNotification({ type: 'success', message: `Execution ${action}d` }));
      if (selectedTeam) loadTeamData(selectedTeam.id);
    } catch (error) {
      dispatch(addNotification({ type: 'error', message: getErrorMessage(error, `Failed to ${action} execution`) }));
    }
  };

  const handlePublishTemplate = async (templateId: string) => {
    try {
      await teamsApi.publishTemplate(templateId);
      dispatch(addNotification({ type: 'success', message: 'Template published' }));
      loadData();
    } catch (error) {
      dispatch(addNotification({ type: 'error', message: getErrorMessage(error, 'Failed to publish template') }));
    }
  };

  const { refreshAction } = useRefreshAction({ onRefresh: loadData, loading });

  return (
    <PageContainer
      title="Team Orchestration"
      description="Multi-agent team management and execution"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'AI', href: '/app/ai' },
        { label: 'Teams' }
      ]}
      actions={[
        refreshAction,
        { id: 'start-execution', label: 'Start Execution', onClick: () => setShowExecutionModal(true), icon: Play, variant: 'secondary' as const, disabled: !selectedTeam },
        { id: 'create-team', label: 'Create Team', onClick: () => setShowCreateModal(true), icon: Plus, variant: 'primary' as const }
      ]}
    >
      <div className="flex h-[calc(100vh-12rem)]">
        <TeamListPanel
          teams={teams}
          selectedTeam={selectedTeam}
          onSelectTeam={setSelectedTeam}
          onCreateClick={() => setShowCreateModal(true)}
          loading={loading}
        />

        <TeamDetailPanel
          team={selectedTeam}
          roles={roles}
          channels={channels}
          executions={executions}
          templates={templates}
          teamAnalytics={teamAnalytics}
          onDeleteTeam={handleDeleteTeam}
          onStartExecution={() => setShowExecutionModal(true)}
          onExecutionAction={handleExecutionAction}
          onPublishTemplate={handlePublishTemplate}
          onPeriodChange={setPeriodDays}
          loading={loading}
        />
      </div>

      {/* Create Team Modal */}
      <Modal
        isOpen={showCreateModal}
        onClose={() => setShowCreateModal(false)}
        title="Create Team"
        maxWidth="md"
        icon={<Users />}
        footer={
          <div className="flex justify-end gap-3">
            <button onClick={() => setShowCreateModal(false)} className="btn-theme btn-theme-secondary">Cancel</button>
            <button onClick={handleCreateTeam} disabled={!newTeamName.trim()} className="btn-theme btn-theme-primary">Create</button>
          </div>
        }
      >
        <div className="space-y-4 p-4">
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Name</label>
            <input type="text" value={newTeamName} onChange={(e) => setNewTeamName(e.target.value)} placeholder="Team name" className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent" />
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Topology</label>
            <select value={newTeamTopology} onChange={(e) => setNewTeamTopology(e.target.value)} className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent">
              <option value="hierarchical">Hierarchical</option>
              <option value="flat">Flat</option>
              <option value="mesh">Mesh</option>
              <option value="pipeline">Pipeline</option>
              <option value="hybrid">Hybrid</option>
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Description</label>
            <textarea value={newTeamDescription} onChange={(e) => setNewTeamDescription(e.target.value)} placeholder="Optional description" rows={3} className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent" />
          </div>
        </div>
      </Modal>

      {/* Start Execution Modal */}
      <Modal
        isOpen={showExecutionModal}
        onClose={() => setShowExecutionModal(false)}
        title="Start Team Execution"
        maxWidth="md"
        icon={<Play />}
        footer={
          <div className="flex justify-end gap-3">
            <button onClick={() => setShowExecutionModal(false)} className="btn-theme btn-theme-secondary">Cancel</button>
            <button onClick={handleStartExecution} disabled={!executionObjective.trim()} className="btn-theme btn-theme-primary">Start</button>
          </div>
        }
      >
        <div className="space-y-4 p-4">
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Team</label>
            <p className="text-sm text-theme-secondary">{selectedTeam?.name || 'No team selected'}</p>
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Objective</label>
            <textarea value={executionObjective} onChange={(e) => setExecutionObjective(e.target.value)} placeholder="Describe the objective for this execution..." rows={4} className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent" />
          </div>
        </div>
      </Modal>

      {ConfirmationDialog}
    </PageContainer>
  );
};

export default TeamsPage;
