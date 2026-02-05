// Enhanced Teams Management Page - Multi-Agent Team Orchestration
import React, { useState, useEffect, useCallback } from 'react';
import {
  Plus, Users, UserCog, MessageSquare, Play, Pause, Square,
  BarChart3, Copy, ArrowRightLeft, ListTodo, Hash, Trash2
} from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Modal } from '@/shared/components/ui/Modal';
import { useDispatch } from 'react-redux';
import { addNotification } from '@/shared/services/slices/uiSlice';
import { AppDispatch } from '@/shared/services';
import { useAiOrchestrationWebSocket } from '@/shared/hooks/useAiOrchestrationWebSocket';
import { useRefreshAction } from '@/shared/hooks/useRefreshAction';
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

// Type guard for API errors
interface ApiErrorResponse {
  response?: {
    data?: {
      error?: string;
    };
  };
}

function isApiError(error: unknown): error is ApiErrorResponse {
  return typeof error === 'object' && error !== null && 'response' in error;
}

function getErrorMessage(error: unknown, fallback: string): string {
  if (isApiError(error)) {
    return error.response?.data?.error || fallback;
  }
  if (error instanceof Error) {
    return error.message;
  }
  return fallback;
}

type TabType = 'teams' | 'roles' | 'channels' | 'executions' | 'tasks' | 'messages' | 'templates' | 'analytics';

const TeamsPage: React.FC = () => {
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
        if (selectedTeam) {
          loadTeamData(selectedTeam.id);
        }
      }
    }
  });

  useEffect(() => {
    loadData();
  }, []);

  const loadTeamData = useCallback(async (teamId: string) => {
    try {
      const [rolesRes, channelsRes, executionsRes, analyticsRes] = await Promise.all([
        teamsApi.listRoles(teamId),
        teamsApi.listChannels(teamId),
        teamsApi.listExecutions(teamId),
        teamsApi.getTeamAnalytics(teamId).catch(() => null)
      ]);
      setRoles(rolesRes.roles || []);
      setChannels(channelsRes.channels || []);
      setExecutions(executionsRes.executions || []);
      setTeamAnalytics(analyticsRes);
    } catch (error) {
      dispatch(addNotification({
        type: 'error',
        message: getErrorMessage(error, 'Failed to load team details')
      }));
    }
  }, [dispatch]);

  useEffect(() => {
    if (selectedTeam) {
      loadTeamData(selectedTeam.id);
    }
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
      if (teamsRes.teams?.length > 0 && !selectedTeam) {
        setSelectedTeam(teamsRes.teams[0]);
      }
    } catch (error) {
      dispatch(addNotification({
        type: 'error',
        message: getErrorMessage(error, 'Failed to load teams data')
      }));
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

  const handleDeleteTeam = async (teamId: string) => {
    try {
      await teamsApi.deleteTeam(teamId);
      dispatch(addNotification({ type: 'success', message: 'Team deleted' }));
      setTeams(teams.filter(t => t.id !== teamId));
      if (selectedTeam?.id === teamId) {
        setSelectedTeam(teams.find(t => t.id !== teamId) || null);
      }
    } catch (error) {
      dispatch(addNotification({ type: 'error', message: getErrorMessage(error, 'Failed to delete team') }));
    }
  };

  const handleStartExecution = async () => {
    if (!selectedTeam || !executionObjective.trim()) return;
    try {
      const execution = await teamsApi.startExecution(selectedTeam.id, {
        objective: executionObjective
      });
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
      if (action === 'pause') {
        await teamsApi.pauseExecution(executionId);
      } else if (action === 'resume') {
        await teamsApi.resumeExecution(executionId);
      } else {
        await teamsApi.cancelExecution(executionId, 'Cancelled by user');
      }
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
      case 'draft': case 'inactive': return 'text-theme-secondary bg-theme-surface';
      default: return 'text-theme-secondary bg-theme-surface';
    }
  };

  const { refreshAction } = useRefreshAction({
    onRefresh: loadData,
    loading,
  });

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'AI', href: '/app/ai' },
    { label: 'Teams' }
  ];

  const tabs = [
    { id: 'teams' as TabType, label: 'Teams', icon: Users },
    { id: 'roles' as TabType, label: 'Roles', icon: UserCog },
    { id: 'channels' as TabType, label: 'Channels', icon: Hash },
    { id: 'executions' as TabType, label: 'Executions', icon: Play },
    { id: 'tasks' as TabType, label: 'Tasks', icon: ListTodo },
    { id: 'messages' as TabType, label: 'Messages', icon: MessageSquare },
    { id: 'templates' as TabType, label: 'Templates', icon: Copy },
    { id: 'analytics' as TabType, label: 'Analytics', icon: BarChart3 }
  ];

  return (
    <PageContainer
      title="Team Orchestration"
      description="Multi-agent team management with roles, channels, executions, tasks, and messaging"
      breadcrumbs={breadcrumbs}
      actions={[
        refreshAction,
        {
          id: 'start-execution',
          label: 'Start Execution',
          onClick: () => setShowExecutionModal(true),
          icon: Play,
          variant: 'secondary' as const,
          disabled: !selectedTeam
        },
        {
          id: 'create-team',
          label: 'Create Team',
          onClick: () => setShowCreateModal(true),
          icon: Plus,
          variant: 'primary' as const
        }
      ]}
    >
      {/* Team Selector */}
      {teams.length > 0 && (
        <div className="flex items-center gap-4 mb-6 p-4 bg-theme-surface border border-theme rounded-lg">
          <label className="text-sm font-medium text-theme-primary">Active Team:</label>
          <select
            value={selectedTeam?.id || ''}
            onChange={(e) => {
              const team = teams.find(t => t.id === e.target.value);
              setSelectedTeam(team || null);
            }}
            className="flex-1 max-w-md px-3 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent"
          >
            {teams.map(team => (
              <option key={team.id} value={team.id}>
                {team.name} ({team.team_topology}) - {team.status}
              </option>
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
          {/* Teams Tab */}
          {activeTab === 'teams' && (
            <div className="space-y-4">
              {teams.length === 0 ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <Users size={48} className="mx-auto text-theme-secondary mb-4" />
                  <h3 className="text-lg font-semibold text-theme-primary mb-2">No teams</h3>
                  <p className="text-theme-secondary mb-6">Create a team to start orchestrating multi-agent operations</p>
                  <button onClick={() => setShowCreateModal(true)} className="btn-theme btn-theme-primary">
                    Create Team
                  </button>
                </div>
              ) : (
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                  {teams.map(team => (
                    <div
                      key={team.id}
                      onClick={() => setSelectedTeam(team)}
                      className={`bg-theme-surface border rounded-lg p-4 cursor-pointer transition-colors ${
                        selectedTeam?.id === team.id ? 'border-theme-accent' : 'border-theme hover:border-theme-accent/50'
                      }`}
                    >
                      <div className="flex items-center justify-between mb-2">
                        <h3 className="font-medium text-theme-primary">{team.name}</h3>
                        <div className="flex items-center gap-2">
                          <span className={`px-2 py-1 text-xs rounded ${getStatusColor(team.status)}`}>{team.status}</span>
                          <button
                            onClick={(e) => { e.stopPropagation(); handleDeleteTeam(team.id); }}
                            className="text-theme-secondary hover:text-theme-danger transition-colors"
                          >
                            <Trash2 size={14} />
                          </button>
                        </div>
                      </div>
                      <p className="text-sm text-theme-secondary mb-3">{team.description || 'No description'}</p>
                      <div className="flex flex-wrap gap-2 text-xs text-theme-secondary">
                        <span className="px-2 py-1 bg-theme-accent/10 text-theme-accent rounded">{team.team_topology}</span>
                        <span>{team.coordination_strategy}</span>
                        <span>{team.roles_count || 0} roles</span>
                        <span>Max {team.max_parallel_tasks} parallel</span>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}

          {/* Roles Tab */}
          {activeTab === 'roles' && (
            <div className="space-y-4">
              {!selectedTeam ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <p className="text-theme-secondary">Select a team to view roles</p>
                </div>
              ) : roles.length === 0 ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <UserCog size={48} className="mx-auto text-theme-secondary mb-4" />
                  <h3 className="text-lg font-semibold text-theme-primary mb-2">No roles defined</h3>
                  <p className="text-theme-secondary mb-6">Define roles for team members</p>
                </div>
              ) : (
                roles.map(role => (
                  <div key={role.id} className="bg-theme-surface border border-theme rounded-lg p-4">
                    <div className="flex items-center justify-between mb-2">
                      <div className="flex items-center gap-3">
                        <h3 className="font-medium text-theme-primary">{role.role_name}</h3>
                        <span className="px-2 py-1 text-xs bg-theme-accent/10 text-theme-accent rounded">{role.role_type}</span>
                        <span className="text-xs text-theme-secondary">Priority: {role.priority_order}</span>
                      </div>
                      <div className="flex gap-2 text-xs">
                        {role.can_delegate && <span className="px-2 py-1 bg-theme-info/10 text-theme-info rounded">Can Delegate</span>}
                        {role.can_escalate && <span className="px-2 py-1 bg-theme-warning/10 text-theme-warning rounded">Can Escalate</span>}
                      </div>
                    </div>
                    {role.role_description && <p className="text-sm text-theme-secondary mb-2">{role.role_description}</p>}
                    <div className="flex gap-4 text-xs text-theme-secondary">
                      <span>Agent: {role.agent_name || 'Unassigned'}</span>
                      <span>Max tasks: {role.max_concurrent_tasks}</span>
                      {role.capabilities.length > 0 && <span>{role.capabilities.length} capabilities</span>}
                      {role.tools_allowed.length > 0 && <span>{role.tools_allowed.length} tools</span>}
                    </div>
                  </div>
                ))
              )}
            </div>
          )}

          {/* Channels Tab */}
          {activeTab === 'channels' && (
            <div className="space-y-4">
              {!selectedTeam ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <p className="text-theme-secondary">Select a team to view channels</p>
                </div>
              ) : channels.length === 0 ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <Hash size={48} className="mx-auto text-theme-secondary mb-4" />
                  <h3 className="text-lg font-semibold text-theme-primary mb-2">No channels</h3>
                  <p className="text-theme-secondary mb-6">Create communication channels for team coordination</p>
                </div>
              ) : (
                channels.map(channel => (
                  <div key={channel.id} className="bg-theme-surface border border-theme rounded-lg p-4">
                    <div className="flex items-center justify-between mb-2">
                      <div className="flex items-center gap-3">
                        <Hash size={16} className="text-theme-accent" />
                        <h3 className="font-medium text-theme-primary">{channel.name}</h3>
                        <span className="px-2 py-1 text-xs bg-theme-accent/10 text-theme-accent rounded">{channel.channel_type}</span>
                        {channel.is_persistent && <span className="px-2 py-1 text-xs bg-theme-info/10 text-theme-info rounded">Persistent</span>}
                      </div>
                      <span className="text-sm text-theme-secondary">{channel.message_count} messages</span>
                    </div>
                    {channel.description && <p className="text-sm text-theme-secondary mb-2">{channel.description}</p>}
                    <div className="flex gap-2 text-xs text-theme-secondary">
                      <span>{channel.participant_roles.length} participants</span>
                      {channel.message_retention_hours && <span>Retention: {channel.message_retention_hours}h</span>}
                    </div>
                  </div>
                ))
              )}
            </div>
          )}

          {/* Executions Tab */}
          {activeTab === 'executions' && (
            <div className="space-y-4">
              {!selectedTeam ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <p className="text-theme-secondary">Select a team to view executions</p>
                </div>
              ) : executions.length === 0 ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <Play size={48} className="mx-auto text-theme-secondary mb-4" />
                  <h3 className="text-lg font-semibold text-theme-primary mb-2">No executions</h3>
                  <p className="text-theme-secondary mb-6">Start a team execution to see results here</p>
                  <button onClick={() => setShowExecutionModal(true)} className="btn-theme btn-theme-primary">
                    Start Execution
                  </button>
                </div>
              ) : (
                executions.map(execution => (
                  <div
                    key={execution.id}
                    className="bg-theme-surface border border-theme rounded-lg p-4 cursor-pointer hover:border-theme-accent/50 transition-colors"
                    onClick={() => handleLoadExecutionTasks(execution)}
                  >
                    <div className="flex items-center justify-between mb-2">
                      <div className="flex items-center gap-3">
                        <span className="font-mono text-sm text-theme-secondary">{execution.execution_id.slice(0, 8)}</span>
                        <span className={`px-2 py-1 text-xs rounded ${getStatusColor(execution.status)}`}>{execution.status}</span>
                      </div>
                      <div className="flex gap-2" onClick={(e) => e.stopPropagation()}>
                        {execution.status === 'running' && (
                          <>
                            <button onClick={() => handleExecutionAction(execution.id, 'pause')} className="btn-theme btn-theme-warning btn-theme-sm">
                              <Pause size={14} />
                            </button>
                            <button onClick={() => handleExecutionAction(execution.id, 'cancel')} className="btn-theme btn-theme-danger btn-theme-sm">
                              <Square size={14} />
                            </button>
                          </>
                        )}
                        {execution.status === 'paused' && (
                          <button onClick={() => handleExecutionAction(execution.id, 'resume')} className="btn-theme btn-theme-success btn-theme-sm">
                            <Play size={14} />
                          </button>
                        )}
                      </div>
                    </div>
                    <p className="text-sm text-theme-primary mb-2">{execution.objective || 'No objective'}</p>
                    {/* Progress Bar */}
                    <div className="w-full bg-theme-bg rounded-full h-2 mb-2">
                      <div
                        className="bg-theme-accent h-2 rounded-full transition-all"
                        style={{ width: `${execution.progress_percentage}%` }}
                      ></div>
                    </div>
                    <div className="flex gap-4 text-xs text-theme-secondary">
                      <span>{execution.tasks_completed}/{execution.tasks_total} tasks</span>
                      {execution.tasks_failed > 0 && <span className="text-theme-danger">{execution.tasks_failed} failed</span>}
                      <span>{execution.messages_exchanged} messages</span>
                      <span>{execution.total_tokens_used.toLocaleString()} tokens</span>
                      {execution.total_cost_usd > 0 && <span>${execution.total_cost_usd.toFixed(4)}</span>}
                      {execution.duration_ms && <span>{(execution.duration_ms / 1000).toFixed(1)}s</span>}
                    </div>
                  </div>
                ))
              )}
            </div>
          )}

          {/* Tasks Tab */}
          {activeTab === 'tasks' && (
            <div className="space-y-4">
              {!selectedExecution ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <ListTodo size={48} className="mx-auto text-theme-secondary mb-4" />
                  <h3 className="text-lg font-semibold text-theme-primary mb-2">Select an execution</h3>
                  <p className="text-theme-secondary">Go to the Executions tab and click on an execution to view its tasks</p>
                </div>
              ) : tasks.length === 0 ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <ListTodo size={48} className="mx-auto text-theme-secondary mb-4" />
                  <h3 className="text-lg font-semibold text-theme-primary mb-2">No tasks</h3>
                  <p className="text-theme-secondary">Tasks will appear as the execution progresses</p>
                </div>
              ) : (
                tasks.map(task => (
                  <div key={task.id} className="bg-theme-surface border border-theme rounded-lg p-4">
                    <div className="flex items-center justify-between mb-2">
                      <div className="flex items-center gap-3">
                        <h3 className="font-medium text-theme-primary">{task.description || task.task_type || 'Task'}</h3>
                        <span className={`px-2 py-1 text-xs rounded ${getStatusColor(task.status)}`}>{task.status}</span>
                      </div>
                    </div>
                    <div className="flex gap-4 text-xs text-theme-secondary">
                      {task.assigned_role_name && <span>Role: {task.assigned_role_name}</span>}
                      {task.assigned_agent_id && <span>Agent: {task.assigned_agent_id.slice(0, 8)}</span>}
                      {task.priority && <span>Priority: {task.priority}</span>}
                      {task.tokens_used > 0 && <span>{task.tokens_used.toLocaleString()} tokens</span>}
                      {task.duration_ms && <span>{(task.duration_ms / 1000).toFixed(1)}s</span>}
                    </div>
                  </div>
                ))
              )}
            </div>
          )}

          {/* Messages Tab */}
          {activeTab === 'messages' && (
            <div className="space-y-4">
              {!selectedExecution ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <MessageSquare size={48} className="mx-auto text-theme-secondary mb-4" />
                  <h3 className="text-lg font-semibold text-theme-primary mb-2">Select an execution</h3>
                  <p className="text-theme-secondary">Go to the Executions tab and click on an execution to view messages</p>
                </div>
              ) : messages.length === 0 ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <MessageSquare size={48} className="mx-auto text-theme-secondary mb-4" />
                  <h3 className="text-lg font-semibold text-theme-primary mb-2">No messages</h3>
                  <p className="text-theme-secondary">Messages will appear as agents communicate</p>
                </div>
              ) : (
                <div className="space-y-3">
                  {messages.map(msg => (
                    <div key={msg.id} className="bg-theme-surface border border-theme rounded-lg p-4">
                      <div className="flex items-center gap-2 mb-2">
                        <span className="text-sm font-medium text-theme-accent">{msg.from_role_name || 'System'}</span>
                        {msg.to_role_name && (
                          <>
                            <ArrowRightLeft size={12} className="text-theme-secondary" />
                            <span className="text-sm font-medium text-theme-info">{msg.to_role_name}</span>
                          </>
                        )}
                        <span className="text-xs text-theme-secondary ml-auto">{new Date(msg.created_at).toLocaleTimeString()}</span>
                      </div>
                      <p className="text-sm text-theme-primary">{msg.content}</p>
                      {msg.message_type && (
                        <span className="inline-block mt-1 px-2 py-0.5 text-xs bg-theme-accent/10 text-theme-accent rounded">{msg.message_type}</span>
                      )}
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}

          {/* Templates Tab */}
          {activeTab === 'templates' && (
            <div className="space-y-4">
              {templates.length === 0 ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <Copy size={48} className="mx-auto text-theme-secondary mb-4" />
                  <h3 className="text-lg font-semibold text-theme-primary mb-2">No templates</h3>
                  <p className="text-theme-secondary mb-6">Create team templates for reuse</p>
                </div>
              ) : (
                templates.map(template => (
                  <div key={template.id} className="bg-theme-surface border border-theme rounded-lg p-4">
                    <div className="flex items-center justify-between mb-2">
                      <div className="flex items-center gap-3">
                        <h3 className="font-medium text-theme-primary">{template.name}</h3>
                        {template.is_public && <span className="px-2 py-1 text-xs rounded text-theme-success bg-theme-success/10">Published</span>}
                        {template.is_system && <span className="px-2 py-1 text-xs rounded text-theme-info bg-theme-info/10">System</span>}
                      </div>
                      {!template.published_at && (
                        <button
                          onClick={() => handlePublishTemplate(template.id)}
                          className="btn-theme btn-theme-success btn-theme-sm"
                        >
                          Publish
                        </button>
                      )}
                    </div>
                    <p className="text-sm text-theme-secondary">{template.description || 'No description'}</p>
                    <div className="flex gap-3 text-xs text-theme-secondary mt-2">
                      <span>{template.team_topology}</span>
                      <span>{template.usage_count} uses</span>
                      {template.tags.length > 0 && <span>{template.tags.join(', ')}</span>}
                    </div>
                  </div>
                ))
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
                <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                  {Object.entries(teamAnalytics).filter(([, value]) => typeof value === 'number' || typeof value === 'string').slice(0, 9).map(([key, value]) => (
                    <div key={key} className="bg-theme-surface border border-theme rounded-lg p-4">
                      <p className="text-sm text-theme-secondary">{key.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase())}</p>
                      <p className="text-2xl font-bold text-theme-primary">
                        {typeof value === 'number'
                          ? (key.includes('usd') || key.includes('cost') ? `$${value.toFixed(2)}` : value.toLocaleString())
                          : String(value)}
                      </p>
                    </div>
                  ))}
                </div>
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
            <input
              type="text"
              value={newTeamName}
              onChange={(e) => setNewTeamName(e.target.value)}
              placeholder="Team name"
              className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Topology</label>
            <select
              value={newTeamTopology}
              onChange={(e) => setNewTeamTopology(e.target.value)}
              className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent"
            >
              <option value="hierarchical">Hierarchical</option>
              <option value="flat">Flat</option>
              <option value="mesh">Mesh</option>
              <option value="pipeline">Pipeline</option>
              <option value="hybrid">Hybrid</option>
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Description</label>
            <textarea
              value={newTeamDescription}
              onChange={(e) => setNewTeamDescription(e.target.value)}
              placeholder="Optional description"
              rows={3}
              className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent"
            />
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
            <textarea
              value={executionObjective}
              onChange={(e) => setExecutionObjective(e.target.value)}
              placeholder="Describe the objective for this execution..."
              rows={4}
              className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent"
            />
          </div>
        </div>
      </Modal>
    </PageContainer>
  );
};

export default TeamsPage;
