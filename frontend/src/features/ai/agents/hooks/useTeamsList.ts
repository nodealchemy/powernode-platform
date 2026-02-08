import { useState, useCallback, useMemo } from 'react';
import { useDispatch } from 'react-redux';
import {
  agentTeamsApi,
  AgentTeam,
  CreateTeamParams,
  ExecuteTeamParams,
} from '@/features/ai/agent-teams/services/agentTeamsApi';
import { addNotification } from '@/shared/services/slices/uiSlice';
import { getErrorMessage } from '@/shared/utils/apiErrors';
import type { AppDispatch } from '@/shared/services';

interface TeamFilters {
  status?: string;
  team_type?: string;
}

export function useTeamsList() {
  const dispatch = useDispatch<AppDispatch>();

  const [teams, setTeams] = useState<AgentTeam[]>([]);
  const [teamsLoading, setTeamsLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [typeFilter, setTypeFilter] = useState<string>('all');
  const [executingTeamIds, setExecutingTeamIds] = useState<string[]>([]);
  const [expandedTeamId, setExpandedTeamId] = useState<string | null>(null);
  const [teamViewMode, setTeamViewMode] = useState<'grid' | 'list'>('grid');
  const [teamSearchQuery, setTeamSearchQuery] = useState('');
  const [isBuilderOpen, setIsBuilderOpen] = useState(false);
  const [executeModalTeam, setExecuteModalTeam] = useState<AgentTeam | null>(null);

  const loadTeams = useCallback(async () => {
    try {
      setTeamsLoading(true);
      const filters: TeamFilters = {};
      if (statusFilter !== 'all') filters.status = statusFilter;
      if (typeFilter !== 'all') filters.team_type = typeFilter;

      const data = await agentTeamsApi.getTeams(filters);
      setTeams(data);
    } catch (error) {
      dispatch(addNotification({
        type: 'error',
        message: getErrorMessage(error, 'Failed to load teams'),
      }));
    } finally {
      setTeamsLoading(false);
    }
  }, [statusFilter, typeFilter, dispatch]);

  const handleToggleExpand = useCallback((teamId: string) => {
    setExpandedTeamId(prev => prev === teamId ? null : teamId);
  }, []);

  const handleCreateTeam = useCallback(async (params: CreateTeamParams) => {
    try {
      await agentTeamsApi.createTeam(params);
      dispatch(addNotification({ type: 'success', message: 'Team created successfully' }));
      await loadTeams();
    } catch (error) {
      dispatch(addNotification({ type: 'error', message: getErrorMessage(error, 'Failed to create team') }));
      throw error;
    }
  }, [dispatch, loadTeams]);

  const handleDeleteTeam = useCallback(async (team: AgentTeam) => {
    if (!confirm(`Are you sure you want to delete "${team.name}"?`)) return;
    setExpandedTeamId(null);
    try {
      await agentTeamsApi.deleteTeam(team.id);
      dispatch(addNotification({ type: 'success', message: 'Team deleted successfully' }));
      await loadTeams();
    } catch (error) {
      dispatch(addNotification({ type: 'error', message: getErrorMessage(error, 'Failed to delete team') }));
    }
  }, [dispatch, loadTeams]);

  const handleRequestExecute = useCallback((team: AgentTeam) => {
    setExecuteModalTeam(team);
  }, []);

  const handleExecuteTeam = useCallback(async (team: AgentTeam, params?: ExecuteTeamParams) => {
    try {
      const result = await agentTeamsApi.executeTeam(team.id, params);
      setExecutingTeamIds(prev => prev.includes(team.id) ? prev : [...prev, team.id]);
      dispatch(addNotification({ type: 'success', message: `Team "${team.name}" is now executing. Job ID: ${result.job_id}` }));
    } catch (error) {
      dispatch(addNotification({ type: 'error', message: getErrorMessage(error, 'Failed to execute team') }));
    }
  }, [dispatch]);

  const handleExecutionComplete = useCallback((_teamId: string) => {
    loadTeams();
  }, [loadTeams]);

  const handleDismissMonitor = useCallback((teamId: string) => {
    setExecutingTeamIds(prev => prev.filter(id => id !== teamId));
  }, []);

  const handleCloseBuilder = useCallback(() => {
    setIsBuilderOpen(false);
  }, []);

  const handleSaveTeam = useCallback(async (params: CreateTeamParams | Partial<CreateTeamParams>) => {
    await handleCreateTeam(params as CreateTeamParams);
  }, [handleCreateTeam]);

  const filteredTeams = useMemo(() => {
    if (!teamSearchQuery) return teams;
    const q = teamSearchQuery.toLowerCase();
    return teams.filter(t =>
      t.name.toLowerCase().includes(q) ||
      t.description?.toLowerCase().includes(q) ||
      t.team_type?.toLowerCase().includes(q)
    );
  }, [teams, teamSearchQuery]);

  const teamStats = useMemo(() => {
    const active = teams.filter(t => t.status === 'active').length;
    const totalMembers = teams.reduce((sum, t) => sum + t.member_count, 0);
    const withLead = teams.filter(t => t.has_lead).length;
    const byType = teams.reduce<Record<string, number>>((acc, t) => {
      acc[t.team_type] = (acc[t.team_type] || 0) + 1;
      return acc;
    }, {});
    return { total: teams.length, active, totalMembers, withLead, byType };
  }, [teams]);

  return {
    teams,
    teamsLoading,
    statusFilter,
    setStatusFilter,
    typeFilter,
    setTypeFilter,
    executingTeamIds,
    expandedTeamId,
    teamViewMode,
    setTeamViewMode,
    teamSearchQuery,
    setTeamSearchQuery,
    isBuilderOpen,
    setIsBuilderOpen,
    executeModalTeam,
    setExecuteModalTeam,
    loadTeams,
    filteredTeams,
    teamStats,
    handleToggleExpand,
    handleCreateTeam,
    handleDeleteTeam,
    handleRequestExecute,
    handleExecuteTeam,
    handleExecutionComplete,
    handleDismissMonitor,
    handleCloseBuilder,
    handleSaveTeam,
  };
}
