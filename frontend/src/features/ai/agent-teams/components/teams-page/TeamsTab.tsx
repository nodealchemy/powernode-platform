import React from 'react';
import { Users, Trash2 } from 'lucide-react';
import { Team } from '@/shared/services/ai/TeamsApiService';

interface TeamsTabProps {
  teams: Team[];
  selectedTeam: Team | null;
  onSelectTeam: (team: Team) => void;
  onDeleteTeam: (teamId: string) => void;
  onCreateClick: () => void;
  getStatusColor: (status: string) => string;
}

export const TeamsTab: React.FC<TeamsTabProps> = ({
  teams,
  selectedTeam,
  onSelectTeam,
  onDeleteTeam,
  onCreateClick,
  getStatusColor,
}) => {
  if (teams.length === 0) {
    return (
      <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
        <Users size={48} className="mx-auto text-theme-secondary mb-4" />
        <h3 className="text-lg font-semibold text-theme-primary mb-2">No teams</h3>
        <p className="text-theme-secondary mb-6">Create a team to start orchestrating multi-agent operations</p>
        <button onClick={onCreateClick} className="btn-theme btn-theme-primary">
          Create Team
        </button>
      </div>
    );
  }

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
      {teams.map(team => (
        <div
          key={team.id}
          onClick={() => onSelectTeam(team)}
          className={`bg-theme-surface border rounded-lg p-4 cursor-pointer transition-colors ${
            selectedTeam?.id === team.id ? 'border-theme-accent' : 'border-theme hover:border-theme-accent/50'
          }`}
        >
          <div className="flex items-center justify-between mb-2">
            <h3 className="font-medium text-theme-primary">{team.name}</h3>
            <div className="flex items-center gap-2">
              <span className={`px-2 py-1 text-xs rounded ${getStatusColor(team.status)}`}>{team.status}</span>
              <button
                onClick={(e) => { e.stopPropagation(); onDeleteTeam(team.id); }}
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
  );
};
