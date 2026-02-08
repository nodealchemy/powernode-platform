// Agent Teams Page - Main page for managing multi-agent teams
import React, { useState, useEffect, useMemo } from 'react';
import { useLocation } from 'react-router-dom';
import { Plus, Users, Filter, Server, LayoutDashboard, Crown, Activity } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { TeamCard } from '@/features/ai/agent-teams/components/TeamCard';
import { TeamBuilderModal } from '@/features/ai/agent-teams/components/TeamBuilderModal';
import { TeamExecutionMonitor } from '@/features/ai/agent-teams/components/TeamExecutionMonitor';
import { DevOpsTeamTemplates } from '@/features/ai/agent-teams/components/DevOpsTeamTemplates';
import {
  agentTeamsApi,
  AgentTeam,
  CreateTeamParams,
  UpdateTeamParams
} from '@/features/ai/agent-teams/services/agentTeamsApi';
import { useDispatch } from 'react-redux';
import { addNotification } from '@/shared/services/slices/uiSlice';
import { AppDispatch } from '@/shared/services';
import { useAiOrchestrationWebSocket } from '@/shared/hooks/useAiOrchestrationWebSocket';
import { useRefreshAction } from '@/shared/hooks/useRefreshAction';

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

// Filter interface for type safety
interface TeamFilters {
  status?: string;
  team_type?: string;
}

const tabs = [
  { id: 'overview', label: 'Overview', icon: <LayoutDashboard size={16} />, path: '/' },
  { id: 'teams', label: 'Teams', icon: <Users size={16} />, path: '/teams' },
  { id: 'devops', label: 'DevOps Templates', icon: <Server size={16} />, path: '/devops-templates' },
];

const AgentTeamsPage: React.FC = () => {
  const dispatch = useDispatch<AppDispatch>();
  const location = useLocation();
  const [teams, setTeams] = useState<AgentTeam[]>([]);
  const [loading, setLoading] = useState(true);
  const [isBuilderOpen, setIsBuilderOpen] = useState(false);
  const [editingTeam, setEditingTeam] = useState<AgentTeam | null>(null);
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [typeFilter, setTypeFilter] = useState<string>('all');
  const [executingTeamId, setExecutingTeamId] = useState<string | null>(null);

  const getActiveTab = () => {
    const path = location.pathname;
    if (path.includes('/teams')) return 'teams';
    if (path.includes('/devops-templates')) return 'devops';
    return 'overview';
  };

  const [activeTab, setActiveTab] = useState(getActiveTab());

  useEffect(() => {
    const newTab = getActiveTab();
    if (newTab !== activeTab) setActiveTab(newTab);
  }, [location.pathname]);

  // WebSocket for real-time agent team updates
  useAiOrchestrationWebSocket({
    onAgentTeamEvent: (event) => {
      // Refresh team list when teams are created, updated, deleted, or execution completes
      if (['team_created', 'team_updated', 'team_deleted', 'team_execution_completed'].includes(event.type)) {
        loadTeams();
      }
    },
  });

  useEffect(() => {
    loadTeams();
  }, [statusFilter, typeFilter]);

  const loadTeams = async () => {
    try {
      setLoading(true);
      const filters: TeamFilters = {};
      if (statusFilter !== 'all') filters.status = statusFilter;
      if (typeFilter !== 'all') filters.team_type = typeFilter;

      const data = await agentTeamsApi.getTeams(filters);
      setTeams(data);
    } catch (error) {
      dispatch(addNotification({
        type: 'error',
        message: getErrorMessage(error, 'Failed to load teams')
      }));
    } finally {
      setLoading(false);
    }
  };

  const handleCreateTeam = async (params: CreateTeamParams) => {
    try {
      await agentTeamsApi.createTeam(params);
      dispatch(addNotification({
        type: 'success',
        message: 'Team created successfully'
      }));
      await loadTeams();
    } catch (error) {
      dispatch(addNotification({
        type: 'error',
        message: getErrorMessage(error, 'Failed to create team')
      }));
      throw error;
    }
  };

  const handleUpdateTeam = async (params: UpdateTeamParams) => {
    if (!editingTeam) return;

    try {
      await agentTeamsApi.updateTeam(editingTeam.id, params);
      dispatch(addNotification({
        type: 'success',
        message: 'Team updated successfully'
      }));
      await loadTeams();
      setEditingTeam(null);
    } catch (error) {
      dispatch(addNotification({
        type: 'error',
        message: getErrorMessage(error, 'Failed to update team')
      }));
      throw error;
    }
  };

  const handleDeleteTeam = async (team: AgentTeam) => {
    if (!confirm(`Are you sure you want to delete "${team.name}"?`)) return;

    try {
      await agentTeamsApi.deleteTeam(team.id);
      dispatch(addNotification({
        type: 'success',
        message: 'Team deleted successfully'
      }));
      await loadTeams();
    } catch (error) {
      dispatch(addNotification({
        type: 'error',
        message: getErrorMessage(error, 'Failed to delete team')
      }));
    }
  };

  const handleExecuteTeam = async (team: AgentTeam) => {
    try {
      const result = await agentTeamsApi.executeTeam(team.id);
      setExecutingTeamId(team.id);
      dispatch(addNotification({
        type: 'success',
        message: `Team "${team.name}" is now executing. Job ID: ${result.job_id}`
      }));
    } catch (error) {
      dispatch(addNotification({
        type: 'error',
        message: getErrorMessage(error, 'Failed to execute team')
      }));
    }
  };

  const handleExecutionComplete = () => {
    // Reload teams to get updated status
    loadTeams();
  };

  const handleEditTeam = (team: AgentTeam) => {
    setEditingTeam(team);
    setIsBuilderOpen(true);
  };

  const handleCloseBuilder = () => {
    setIsBuilderOpen(false);
    setEditingTeam(null);
  };

  const handleSaveTeam = async (params: CreateTeamParams | UpdateTeamParams) => {
    if (editingTeam) {
      await handleUpdateTeam(params as UpdateTeamParams);
    } else {
      await handleCreateTeam(params as CreateTeamParams);
    }
  };

  const { refreshAction } = useRefreshAction({
    onRefresh: loadTeams,
    loading,
  });

  const overviewStats = useMemo(() => {
    const active = teams.filter(t => t.status === 'active').length;
    const totalMembers = teams.reduce((sum, t) => sum + t.member_count, 0);
    const withLead = teams.filter(t => t.has_lead).length;
    const byType = teams.reduce<Record<string, number>>((acc, t) => {
      acc[t.team_type] = (acc[t.team_type] || 0) + 1;
      return acc;
    }, {});
    return { total: teams.length, active, totalMembers, withLead, byType };
  }, [teams]);

  const getBreadcrumbs = () => {
    const base: Array<{ label: string; href?: string }> = [
      { label: 'Dashboard', href: '/app' },
      { label: 'AI', href: '/app/ai' },
      { label: 'Agent Teams' }
    ];
    const activeTabInfo = tabs.find(t => t.id === activeTab);
    if (activeTabInfo && activeTab !== 'overview') {
      base.push({ label: activeTabInfo.label });
    }
    return base;
  };

  return (
    <PageContainer
      title="Agent Teams"
      description="Manage multi-agent teams for collaborative AI orchestration"
      breadcrumbs={getBreadcrumbs()}
      actions={[
        refreshAction,
        {
          id: 'create-team',
          label: 'Create Team',
          onClick: () => setIsBuilderOpen(true),
          icon: Plus,
          variant: 'primary' as const
        }
      ]}
    >
      <TabContainer
        tabs={tabs}
        activeTab={activeTab}
        onTabChange={setActiveTab}
        basePath="/app/ai/agent-teams"
        variant="underline"
        className="mb-6"
      >
        <TabPanel tabId="overview" activeTab={activeTab}>
          <div className="space-y-6">
            {/* Stats Cards */}
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              <div className="bg-theme-surface border border-theme rounded-lg p-4">
                <div className="flex items-center gap-2 mb-2">
                  <Users className="h-4 w-4 text-theme-info" />
                  <span className="text-xs font-medium text-theme-secondary">Total Teams</span>
                </div>
                <div className="text-2xl font-bold text-theme-primary">{overviewStats.total}</div>
              </div>
              <div className="bg-theme-surface border border-theme rounded-lg p-4">
                <div className="flex items-center gap-2 mb-2">
                  <Activity className="h-4 w-4 text-theme-success" />
                  <span className="text-xs font-medium text-theme-secondary">Active</span>
                </div>
                <div className="text-2xl font-bold text-theme-success">{overviewStats.active}</div>
              </div>
              <div className="bg-theme-surface border border-theme rounded-lg p-4">
                <div className="flex items-center gap-2 mb-2">
                  <Users className="h-4 w-4 text-theme-interactive-primary" />
                  <span className="text-xs font-medium text-theme-secondary">Total Agents</span>
                </div>
                <div className="text-2xl font-bold text-theme-primary">{overviewStats.totalMembers}</div>
              </div>
              <div className="bg-theme-surface border border-theme rounded-lg p-4">
                <div className="flex items-center gap-2 mb-2">
                  <Crown className="h-4 w-4 text-theme-warning" />
                  <span className="text-xs font-medium text-theme-secondary">With Lead</span>
                </div>
                <div className="text-2xl font-bold text-theme-primary">{overviewStats.withLead}</div>
              </div>
            </div>

            {/* Team Type Breakdown */}
            {Object.keys(overviewStats.byType).length > 0 && (
              <div className="bg-theme-surface border border-theme rounded-lg p-4">
                <h4 className="text-sm font-semibold text-theme-primary mb-3">Teams by Type</h4>
                <div className="space-y-2">
                  {Object.entries(overviewStats.byType).map(([type, count]) => (
                    <div key={type} className="flex items-center justify-between">
                      <span className="text-sm text-theme-primary capitalize">{type}</span>
                      <div className="flex items-center gap-2">
                        <div className="w-32 bg-theme-accent rounded-full h-2">
                          <div
                            className="h-2 rounded-full bg-theme-interactive-primary transition-all"
                            style={{ width: `${(count / overviewStats.total) * 100}%` }}
                          />
                        </div>
                        <span className="text-sm font-medium text-theme-primary w-6 text-right">{count}</span>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* Recent Teams */}
            <div>
              <h4 className="text-sm font-semibold text-theme-primary mb-3">All Teams</h4>
              {loading ? (
                <div className="text-center py-8">
                  <div className="inline-block animate-spin rounded-full h-6 w-6 border-4 border-theme-accent border-t-theme-primary" />
                </div>
              ) : teams.length === 0 ? (
                <div className="text-center py-8 text-theme-secondary text-sm">No teams created yet</div>
              ) : (
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                  {teams.map((team) => (
                    <TeamCard
                      key={team.id}
                      team={team}
                      onEdit={handleEditTeam}
                      onDelete={handleDeleteTeam}
                      onExecute={handleExecuteTeam}
                    />
                  ))}
                </div>
              )}
            </div>
          </div>
        </TabPanel>

        <TabPanel tabId="devops" activeTab={activeTab}>
          <DevOpsTeamTemplates />
        </TabPanel>

        <TabPanel tabId="teams" activeTab={activeTab}>
          {/* Filters */}
          <div className="flex flex-wrap gap-4 mb-6">
            <div className="flex items-center gap-2">
              <Filter size={16} className="text-theme-secondary" />
              <label htmlFor="status-filter" className="text-sm font-medium text-theme-primary">
                Status:
              </label>
              <select
                id="status-filter"
                value={statusFilter}
                onChange={(e) => setStatusFilter(e.target.value)}
                className="px-3 py-1 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent"
              >
                <option value="all">All</option>
                <option value="active">Active</option>
                <option value="inactive">Inactive</option>
                <option value="archived">Archived</option>
              </select>
            </div>

            <div className="flex items-center gap-2">
              <label htmlFor="type-filter" className="text-sm font-medium text-theme-primary">
                Type:
              </label>
              <select
                id="type-filter"
                value={typeFilter}
                onChange={(e) => setTypeFilter(e.target.value)}
                className="px-3 py-1 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent"
              >
                <option value="all">All</option>
                <option value="hierarchical">Hierarchical</option>
                <option value="mesh">Mesh</option>
                <option value="sequential">Sequential</option>
                <option value="parallel">Parallel</option>
              </select>
            </div>
          </div>

          {/* Execution Monitor */}
          {executingTeamId && (
            <TeamExecutionMonitor
              teamId={executingTeamId}
              onExecutionComplete={handleExecutionComplete}
            />
          )}

          {/* Teams Grid */}
          {loading ? (
            <div className="text-center py-12">
              <div className="inline-block animate-spin rounded-full h-8 w-8 border-4 border-theme-accent border-t-theme-primary"></div>
              <p className="mt-4 text-theme-secondary">Loading teams...</p>
            </div>
          ) : teams.length === 0 ? (
            <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
              <Users size={48} className="mx-auto text-theme-secondary mb-4" />
              <h3 className="text-lg font-semibold text-theme-primary mb-2">No teams yet</h3>
              <p className="text-theme-secondary mb-6">
                Create your first agent team to start collaborative AI orchestration
              </p>
              <button
                onClick={() => setIsBuilderOpen(true)}
                className="btn-theme btn-theme-primary btn-theme-md inline-flex items-center gap-2 cursor-pointer"
              >
                <Plus size={16} />
                Create Team
              </button>
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
              {teams.map((team) => (
                <TeamCard
                  key={team.id}
                  team={team}
                  onEdit={handleEditTeam}
                  onDelete={handleDeleteTeam}
                  onExecute={handleExecuteTeam}
                />
              ))}
            </div>
          )}
        </TabPanel>
      </TabContainer>

      {/* Team Builder Modal */}
      <TeamBuilderModal
        isOpen={isBuilderOpen}
        onClose={handleCloseBuilder}
        onSave={handleSaveTeam}
        team={editingTeam}
      />
    </PageContainer>
  );
};

export default AgentTeamsPage;
