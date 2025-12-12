// Agent Teams Page - Main page for managing CrewAI-style agent teams
import React, { useState, useEffect } from 'react';
import { Plus, Users, Filter } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { TeamCard } from '@/features/ai-agent-teams/components/TeamCard';
import { TeamBuilderModal } from '@/features/ai-agent-teams/components/TeamBuilderModal';
import { TeamExecutionMonitor } from '@/features/ai-agent-teams/components/TeamExecutionMonitor';
import {
  agentTeamsApi,
  AgentTeam,
  CreateTeamParams,
  UpdateTeamParams
} from '@/features/ai-agent-teams/services/agentTeamsApi';
import { useDispatch } from 'react-redux';
import { addNotification } from '@/shared/services/slices/uiSlice';
import { AppDispatch } from '@/shared/services';

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

const AgentTeamsPage: React.FC = () => {
  const dispatch = useDispatch<AppDispatch>();
  const [teams, setTeams] = useState<AgentTeam[]>([]);
  const [loading, setLoading] = useState(true);
  const [isBuilderOpen, setIsBuilderOpen] = useState(false);
  const [editingTeam, setEditingTeam] = useState<AgentTeam | null>(null);
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [typeFilter, setTypeFilter] = useState<string>('all');
  const [executingTeamId, setExecutingTeamId] = useState<string | null>(null);

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
    } catch (error: unknown) {
      dispatch(addNotification({
        type: 'error',
        // title: 'Error',
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
        // title: 'Success',
        message: 'Team created successfully'
      }));
      await loadTeams();
    } catch (error: unknown) {
      dispatch(addNotification({
        type: 'error',
        // title: 'Error',
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
        // title: 'Success',
        message: 'Team updated successfully'
      }));
      await loadTeams();
      setEditingTeam(null);
    } catch (error: unknown) {
      dispatch(addNotification({
        type: 'error',
        // title: 'Error',
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
        // title: 'Success',
        message: 'Team deleted successfully'
      }));
      await loadTeams();
    } catch (error: unknown) {
      dispatch(addNotification({
        type: 'error',
        // title: 'Error',
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
        // title: 'Team Execution Started',
        message: `Team "${team.name}" is now executing. Job ID: ${result.job_id}`
      }));
    } catch (error: unknown) {
      dispatch(addNotification({
        type: 'error',
        // title: 'Error',
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

  return (
    <PageContainer
      title="Agent Teams"
      description="Manage CrewAI-style multi-agent teams for collaborative AI orchestration"
      actions={[
        {
          label: 'Create Team',
          onClick: () => setIsBuilderOpen(true),
          icon: Plus,
          variant: 'primary' as const
        }
      ]}
    >
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
            className="px-3 py-1 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-blue-500"
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
            className="px-3 py-1 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-blue-500"
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
            className="inline-flex items-center gap-2 px-4 py-2 text-sm font-medium text-white bg-theme-primary rounded-md hover:opacity-90 transition-opacity"
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
