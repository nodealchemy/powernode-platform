// Enhanced Teams Management Page - Multi-Agent Team Orchestration
import React, { useState, useEffect, useCallback } from 'react';
import {
  Plus, Users, UserCog, MessageSquare, Play,
  BarChart3, Copy, ListTodo, Hash, BookOpen
} from 'lucide-react';
import TeamAnalyticsDashboard from '@/features/ai/agent-teams/components/TeamAnalyticsDashboard';
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
  TeamTask,
  TeamMessage,
  TeamTemplate,
  TeamAnalytics
} from '@/shared/services/ai/TeamsApiService';
import { ContextBrowser } from '@/features/ai/memory/components/ContextBrowser';
import {
  TeamsTab,
  RolesTab,
  ChannelsTab,
  ExecutionsTab,
  TasksTab,
  MessagesTab,
  TemplatesTab,
} from '@/features/ai/agent-teams/components/teams-page';

// Type guard for API errors
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

type TabType = 'teams' | 'roles' | 'channels' | 'executions' | 'tasks' | 'messages' | 'templates' | 'knowledge' | 'analytics';

const TeamsPage: React.FC = () => {
  const { confirm, ConfirmationDialog } = useConfirmation();
  const dispatch = useDispatch<AppDispatch>();
  const [activeTab, setActiveTab] = useState<TabType>('teams');
  const [teams, setTeams] = useState<Team[]>([]);
  const [selectedTeam, setSelectedTeam] = useState<Team | null>(null);
  const [roles, setRoles] = useState<TeamRole[]>([]);
  const [channels, setChannels] = useState<TeamChannel[]>([]);
  const [executions, setExecutions] = useState<TeamExecution[]>([]);
  const [tasks, setTasks] = useState<TeamTask[]>([]);
  const [messages, setMessages] = useState<TeamMessage[]>([]);
  const [templates, setTemplates] = useState<TeamTemplate[]>([]);
  const [teamAnalytics, setTeamAnalytics] = useState<TeamAnalytics | null>(null);
  const [loading, setLoading] = useState(true);
  const [selectedExecution, setSelectedExecution] = useState<TeamExecution | null>(null);
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
          setTeams(teams.filter(t => t.id !== teamId));
          if (selectedTeam?.id === teamId) setSelectedTeam(teams.find(t => t.id !== teamId) || null);
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

  const handleLoadExecutionTasks = async (execution: TeamExecution) => {
    setSelectedExecution(execution);
    try {
      const [tasksRes, messagesRes] = await Promise.all([
        teamsApi.listTasks(execution.id),
        teamsApi.listMessages(execution.id)
      ]);
      setTasks(tasksRes.tasks || []);
      setMessages(messagesRes.messages || []);
    } catch (error) {
      dispatch(addNotification({ type: 'error', message: getErrorMessage(error, 'Failed to load execution details') }));
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

  const getStatusColor = (status: string): string => {
    switch (status) {
      case 'active': case 'completed': return 'text-theme-success bg-theme-success/10';
      case 'running': case 'pending': return 'text-theme-warning bg-theme-warning/10';
      case 'paused': return 'text-theme-info bg-theme-info/10';
      case 'failed': case 'cancelled': case 'timeout': return 'text-theme-danger bg-theme-danger/10';
      default: return 'text-theme-secondary bg-theme-surface';
    }
  };

  const { refreshAction } = useRefreshAction({ onRefresh: loadData, loading });

  const tabs = [
    { id: 'teams' as TabType, label: 'Teams', icon: Users },
    { id: 'roles' as TabType, label: 'Roles', icon: UserCog },
    { id: 'channels' as TabType, label: 'Channels', icon: Hash },
    { id: 'executions' as TabType, label: 'Executions', icon: Play },
    { id: 'tasks' as TabType, label: 'Tasks', icon: ListTodo },
    { id: 'messages' as TabType, label: 'Messages', icon: MessageSquare },
    { id: 'templates' as TabType, label: 'Templates', icon: Copy },
    { id: 'knowledge' as TabType, label: 'Knowledge', icon: BookOpen },
    { id: 'analytics' as TabType, label: 'Analytics', icon: BarChart3 }
  ];

  return (
    <PageContainer
      title="Team Orchestration"
      description="Multi-agent team management with roles, channels, executions, tasks, and messaging"
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
      {/* Team Selector */}
      {teams.length > 0 && (
        <div className="flex items-center gap-4 mb-6 p-4 bg-theme-surface border border-theme rounded-lg">
          <label className="text-sm font-medium text-theme-primary">Active Team:</label>
          <select
            value={selectedTeam?.id || ''}
            onChange={(e) => setSelectedTeam(teams.find(t => t.id === e.target.value) || null)}
            className="flex-1 max-w-md px-3 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent"
          >
            {teams.map(team => (
              <option key={team.id} value={team.id}>{team.name} ({team.team_topology}) - {team.status}</option>
            ))}
          </select>
          {selectedTeam && (
            <div className="flex gap-4 text-sm text-theme-secondary">
              <span>{selectedTeam.roles_count || 0} roles</span>
              <span>{selectedTeam.channels_count || 0} channels</span>
            </div>
          )}
        </div>
      )}

      {/* Tabs */}
      <div className="border-b border-theme mb-6">
        <nav className="flex gap-2 overflow-x-auto">
          {tabs.map(tab => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`flex items-center gap-2 px-3 py-2 border-b-2 transition-colors whitespace-nowrap ${
                activeTab === tab.id
                  ? 'border-theme-accent text-theme-accent'
                  : 'border-transparent text-theme-secondary hover:text-theme-primary'
              }`}
            >
              <tab.icon size={16} />
              {tab.label}
            </button>
          ))}
        </nav>
      </div>

      {/* Tab Content */}
      {loading ? (
        <div className="text-center py-12">
          <div className="inline-block animate-spin rounded-full h-8 w-8 border-4 border-theme-accent border-t-theme-primary"></div>
          <p className="mt-4 text-theme-secondary">Loading teams data...</p>
        </div>
      ) : (
        <>
          {activeTab === 'teams' && (
            <TeamsTab teams={teams} selectedTeam={selectedTeam} onSelectTeam={setSelectedTeam} onDeleteTeam={handleDeleteTeam} onCreateClick={() => setShowCreateModal(true)} getStatusColor={getStatusColor} />
          )}
          {activeTab === 'roles' && <RolesTab selectedTeam={selectedTeam} roles={roles} />}
          {activeTab === 'channels' && <ChannelsTab selectedTeam={selectedTeam} channels={channels} />}
          {activeTab === 'executions' && (
            <ExecutionsTab selectedTeam={selectedTeam} executions={executions} onStartExecution={() => setShowExecutionModal(true)} onExecutionAction={handleExecutionAction} onLoadExecutionTasks={handleLoadExecutionTasks} getStatusColor={getStatusColor} />
          )}
          {activeTab === 'tasks' && <TasksTab selectedExecution={selectedExecution} tasks={tasks} getStatusColor={getStatusColor} />}
          {activeTab === 'messages' && <MessagesTab selectedExecution={selectedExecution} messages={messages} />}
          {activeTab === 'templates' && <TemplatesTab templates={templates} onPublishTemplate={handlePublishTemplate} />}

          {/* Knowledge Tab - inline since it uses ContextBrowser */}
          {activeTab === 'knowledge' && (
            <div className="space-y-4">
              {!selectedTeam ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <p className="text-theme-secondary">Select a team to view knowledge</p>
                </div>
              ) : (
                <div>
                  <div className="flex items-center gap-2 mb-4">
                    <BookOpen size={18} className="text-theme-secondary" />
                    <h3 className="text-lg font-medium text-theme-primary">Team Contexts</h3>
                    <span className="text-sm text-theme-secondary">Contexts scoped to agents in this team</span>
                  </div>
                  {roles.filter(r => r.agent_id).length === 0 ? (
                    <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                      <BookOpen size={48} className="mx-auto text-theme-secondary mb-4" />
                      <h3 className="text-lg font-semibold text-theme-primary mb-2">No agent contexts</h3>
                      <p className="text-theme-secondary">Assign agents to team roles to see their knowledge contexts here</p>
                    </div>
                  ) : (
                    <div className="space-y-6">
                      {roles.filter(r => r.agent_id).map(role => (
                        <div key={role.id}>
                          <h4 className="text-sm font-medium text-theme-secondary mb-2">
                            {role.agent_name || role.role_name} — {role.role_type}
                          </h4>
                          <ContextBrowser filters={{ ai_agent_id: role.agent_id! }} linkToDetail />
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              )}
            </div>
          )}

          {/* Analytics Tab */}
          {activeTab === 'analytics' && (
            <div className="space-y-4">
              {!selectedTeam ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <p className="text-theme-secondary">Select a team to view analytics</p>
                </div>
              ) : !teamAnalytics ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <BarChart3 size={48} className="mx-auto text-theme-secondary mb-4" />
                  <h3 className="text-lg font-semibold text-theme-primary mb-2">No analytics data</h3>
                  <p className="text-theme-secondary">Analytics will appear once the team has completed executions</p>
                </div>
              ) : (
                <TeamAnalyticsDashboard analytics={teamAnalytics} onPeriodChange={setPeriodDays} />
              )}
            </div>
          )}
        </>
      )}

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
