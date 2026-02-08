import React from 'react';
import { Filter, Users, Crown, Plus, Play, Trash2, Search } from 'lucide-react';
import { Input } from '@/shared/components/ui/Input';
import { ViewToggle } from '@/shared/components/ui/ViewToggle';
import { TeamCard } from '@/features/ai/agent-teams/components/TeamCard';
import { cn } from '@/shared/utils/cn';
import type { AgentTeam, ExecuteTeamParams } from '@/features/ai/agent-teams/services/agentTeamsApi';

interface TeamsTabProps {
  filteredTeams: AgentTeam[];
  teamsLoading: boolean;
  statusFilter: string;
  onStatusFilterChange: (value: string) => void;
  typeFilter: string;
  onTypeFilterChange: (value: string) => void;
  teamSearchQuery: string;
  onSearchChange: (query: string) => void;
  teamViewMode: 'grid' | 'list';
  onViewModeChange: (mode: 'grid' | 'list') => void;
  expandedTeamId: string | null;
  executingTeamIds: string[];
  onOpenBuilder: () => void;
  onToggleExpand: (teamId: string) => void;
  onDeleteTeam: (team: AgentTeam) => void;
  onRequestExecute: (team: AgentTeam) => void;
  onExecuteTeam: (team: AgentTeam, params?: ExecuteTeamParams) => void;
  onExecutionComplete: (teamId: string) => void;
  onDismissMonitor: (teamId: string) => void;
  onTeamUpdated: () => void;
}

export const TeamsTab: React.FC<TeamsTabProps> = ({
  filteredTeams,
  teamsLoading,
  statusFilter,
  onStatusFilterChange,
  typeFilter,
  onTypeFilterChange,
  teamSearchQuery,
  onSearchChange,
  teamViewMode,
  onViewModeChange,
  expandedTeamId,
  executingTeamIds,
  onOpenBuilder,
  onToggleExpand,
  onDeleteTeam,
  onRequestExecute,
  onExecutionComplete,
  onDismissMonitor,
  onTeamUpdated,
}) => (
  <>
    {/* Search + Filters + View Toggle */}
    <div className="flex flex-wrap items-center gap-4 mb-6">
      <div className="flex-1 min-w-48 max-w-sm">
        <div className="relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-theme-muted" />
          <Input
            placeholder="Search teams..."
            value={teamSearchQuery}
            onChange={(e) => onSearchChange(e.target.value)}
            className="pl-10"
          />
        </div>
      </div>
      <div className="flex items-center gap-2">
        <Filter size={16} className="text-theme-secondary" />
        <label htmlFor="team-status-filter" className="text-sm font-medium text-theme-primary">Status:</label>
        <select
          id="team-status-filter"
          value={statusFilter}
          onChange={(e) => onStatusFilterChange(e.target.value)}
          className="px-3 py-1 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent"
        >
          <option value="all">All</option>
          <option value="active">Active</option>
          <option value="inactive">Inactive</option>
          <option value="archived">Archived</option>
        </select>
      </div>

      <div className="flex items-center gap-2">
        <label htmlFor="team-type-filter" className="text-sm font-medium text-theme-primary">Type:</label>
        <select
          id="team-type-filter"
          value={typeFilter}
          onChange={(e) => onTypeFilterChange(e.target.value)}
          className="px-3 py-1 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent"
        >
          <option value="all">All</option>
          <option value="hierarchical">Hierarchical</option>
          <option value="mesh">Mesh</option>
          <option value="sequential">Sequential</option>
          <option value="parallel">Parallel</option>
        </select>
      </div>

      <div className="ml-auto">
        <ViewToggle viewMode={teamViewMode} onViewModeChange={onViewModeChange} />
      </div>
    </div>

    {/* Teams */}
    {teamsLoading ? (
      <div className="text-center py-12">
        <div className="inline-block animate-spin rounded-full h-8 w-8 border-4 border-theme-accent border-t-theme-primary"></div>
        <p className="mt-4 text-theme-secondary">Loading teams...</p>
      </div>
    ) : filteredTeams.length === 0 ? (
      <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
        <Users size={48} className="mx-auto text-theme-secondary mb-4" />
        <h3 className="text-lg font-semibold text-theme-primary mb-2">No teams yet</h3>
        <p className="text-theme-secondary mb-6">
          Create your first agent team to start collaborative AI orchestration
        </p>
        <button
          onClick={onOpenBuilder}
          className="btn-theme btn-theme-primary btn-theme-md inline-flex items-center gap-2 cursor-pointer"
        >
          <Plus size={16} />
          Create Team
        </button>
      </div>
    ) : teamViewMode === 'grid' ? (
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        {filteredTeams.map((team) => (
          <TeamCard
            key={team.id}
            team={team}
            isExpanded={expandedTeamId === team.id}
            isExecuting={executingTeamIds.includes(team.id)}
            onToggleExpand={onToggleExpand}
            onDelete={onDeleteTeam}
            onExecute={onRequestExecute}
            onExecutionComplete={onExecutionComplete}
            onDismissMonitor={onDismissMonitor}
            onTeamUpdated={onTeamUpdated}
          />
        ))}
      </div>
    ) : (
      <div className="bg-theme-surface border border-theme rounded-lg overflow-hidden">
        <table className="w-full">
          <thead>
            <tr className="border-b border-theme bg-theme-background">
              <th className="text-left px-4 py-3 text-xs font-semibold text-theme-secondary uppercase tracking-wide">Name</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-theme-secondary uppercase tracking-wide">Type</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-theme-secondary uppercase tracking-wide">Strategy</th>
              <th className="text-center px-4 py-3 text-xs font-semibold text-theme-secondary uppercase tracking-wide">Members</th>
              <th className="text-center px-4 py-3 text-xs font-semibold text-theme-secondary uppercase tracking-wide">Lead</th>
              <th className="text-center px-4 py-3 text-xs font-semibold text-theme-secondary uppercase tracking-wide">Status</th>
              <th className="text-right px-4 py-3 text-xs font-semibold text-theme-secondary uppercase tracking-wide">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-theme">
            {filteredTeams.map((team) => (
              <tr key={team.id} className="hover:bg-theme-background/50 transition-colors">
                <td className="px-4 py-3">
                  <div>
                    <span className="text-sm font-medium text-theme-primary">{team.name}</span>
                    {team.description && (
                      <p className="text-xs text-theme-secondary line-clamp-1 mt-0.5">{team.description}</p>
                    )}
                  </div>
                </td>
                <td className="px-4 py-3">
                  <span className={cn(
                    'px-2 py-0.5 text-xs font-medium rounded-full capitalize',
                    team.team_type === 'hierarchical' && 'bg-theme-info/10 text-theme-info',
                    team.team_type === 'mesh' && 'bg-theme-interactive-primary/10 text-theme-interactive-primary',
                    team.team_type === 'sequential' && 'bg-theme-success/10 text-theme-success',
                    team.team_type === 'parallel' && 'bg-theme-warning/10 text-theme-warning',
                  )}>
                    {team.team_type}
                  </span>
                </td>
                <td className="px-4 py-3">
                  <span className="text-xs text-theme-primary capitalize">{team.coordination_strategy.replace('_', ' ')}</span>
                </td>
                <td className="px-4 py-3 text-center">
                  <span className="text-sm text-theme-primary">{team.member_count}</span>
                </td>
                <td className="px-4 py-3 text-center">
                  {team.has_lead ? (
                    <Crown size={14} className="inline text-theme-warning" />
                  ) : (
                    <span className="text-xs text-theme-secondary">&mdash;</span>
                  )}
                </td>
                <td className="px-4 py-3 text-center">
                  <span className={cn(
                    'px-2 py-0.5 text-xs font-medium rounded-full capitalize',
                    team.status === 'active' && 'bg-theme-success/10 text-theme-success',
                    team.status === 'inactive' && 'bg-theme-accent text-theme-secondary',
                    team.status === 'archived' && 'bg-theme-error/10 text-theme-error',
                  )}>
                    {team.status}
                  </span>
                </td>
                <td className="px-4 py-3">
                  <div className="flex items-center justify-end gap-1">
                    <button
                      onClick={() => onRequestExecute(team)}
                      disabled={team.status !== 'active' || team.member_count === 0}
                      className="p-1.5 rounded text-theme-primary hover:bg-theme-primary/10 transition-colors disabled:opacity-30"
                      title="Execute"
                    >
                      <Play size={14} />
                    </button>
                    <button
                      onClick={() => onDeleteTeam(team)}
                      className="p-1.5 rounded text-theme-secondary hover:bg-theme-error/10 hover:text-theme-danger transition-colors"
                      title="Delete"
                    >
                      <Trash2 size={14} />
                    </button>
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    )}
  </>
);
