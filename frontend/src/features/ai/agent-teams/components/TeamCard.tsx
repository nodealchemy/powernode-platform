// Team Card Component - Displays a single team in list view

import { Users, Crown, Play, Edit2, Trash2 } from 'lucide-react';
import { AgentTeam } from '../services/agentTeamsApi';

interface TeamCardProps {
  team: AgentTeam;
  onEdit: (team: AgentTeam) => void;
  onDelete: (team: AgentTeam) => void;
  onExecute: (team: AgentTeam) => void;
}

export const TeamCard: React.FC<TeamCardProps> = ({ team, onEdit, onDelete, onExecute }) => {
  const getTeamTypeColor = (type: string) => {
    switch (type) {
      case 'hierarchical':
        return 'bg-theme-info/10 text-theme-info';
      case 'mesh':
        return 'bg-theme-interactive-primary/10 text-theme-interactive-primary';
      case 'sequential':
        return 'bg-theme-success/10 text-theme-success';
      case 'parallel':
        return 'bg-theme-warning/10 text-theme-warning';
      default:
        return 'bg-theme-accent text-theme-secondary';
    }
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'active':
        return 'bg-theme-success/10 text-theme-success';
      case 'inactive':
        return 'bg-theme-accent text-theme-secondary';
      case 'archived':
        return 'bg-theme-error/10 text-theme-error';
      default:
        return 'bg-theme-accent text-theme-secondary';
    }
  };

  return (
    <div data-testid="team-card" className="bg-theme-surface border border-theme rounded-lg p-6 hover:shadow-md transition-shadow">
      {/* Header */}
      <div className="flex items-start justify-between mb-4">
        <div className="flex-1">
          <h3 data-testid="team-name" className="text-lg font-semibold text-theme-primary mb-1">{team.name}</h3>
          <p className="text-sm text-theme-secondary line-clamp-2">{team.description}</p>
        </div>

        {/* Status Badge */}
        <span data-testid="team-status-badge" className={`px-2 py-1 text-xs font-medium rounded-full ${getStatusColor(team.status)}`}>
          {team.status}
        </span>
      </div>

      {/* Team Info */}
      <div className="flex flex-wrap gap-2 mb-4">
        <span data-testid="team-type-badge" className={`px-2 py-1 text-xs font-medium rounded-full ${getTeamTypeColor(team.team_type)}`}>
          {team.team_type}
        </span>

        <span className="flex items-center gap-1 px-2 py-1 text-xs font-medium rounded-full bg-theme-accent text-theme-primary">
          <Users size={12} />
          {team.member_count} {team.member_count === 1 ? 'member' : 'members'}
        </span>

        {team.has_lead && (
          <span className="flex items-center gap-1 px-2 py-1 text-xs font-medium rounded-full bg-theme-warning/10 text-theme-warning">
            <Crown size={12} />
            Has Lead
          </span>
        )}
      </div>

      {/* Coordination Strategy */}
      <div className="text-xs text-theme-secondary mb-4">
        <span className="font-medium">Strategy:</span> {team.coordination_strategy.replace('_', ' ')}
      </div>

      {/* Actions */}
      <div className="flex gap-2 pt-4 border-t border-theme">
        <button
          onClick={() => onExecute(team)}
          disabled={team.status !== 'active' || team.member_count === 0}
          className="btn-theme btn-theme-primary btn-theme-sm flex items-center gap-1"
        >
          <Play size={16} />
          Execute
        </button>

        <button
          onClick={() => onEdit(team)}
          className="btn-theme btn-theme-secondary btn-theme-sm flex items-center gap-1"
        >
          <Edit2 size={16} />
          Edit
        </button>

        <button
          onClick={() => onDelete(team)}
          className="flex items-center gap-1 px-3 py-2 text-sm font-medium text-theme-danger bg-theme-error/10 rounded-md hover:bg-theme-error/20 transition-colors"
        >
          <Trash2 size={16} />
          Delete
        </button>
      </div>
    </div>
  );
};
