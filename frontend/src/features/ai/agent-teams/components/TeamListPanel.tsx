import React, { useState, useMemo } from 'react';
import { Plus, Users, Search } from 'lucide-react';
import { ResizableListPanel } from '@/shared/components/layout/ResizableListPanel';
import type { Team } from '@/shared/services/ai/TeamsApiService';

interface TeamListPanelProps {
  teams: Team[];
  selectedTeam: Team | null;
  onSelectTeam: (team: Team) => void;
  onCreateClick: () => void;
  loading?: boolean;
}

function getStatusColor(status: string): string {
  switch (status) {
    case 'active': return 'text-theme-success bg-theme-success/10';
    case 'paused': return 'text-theme-info bg-theme-info/10';
    case 'archived': case 'disbanded': return 'text-theme-secondary bg-theme-surface';
    default: return 'text-theme-secondary bg-theme-surface';
  }
}

export const TeamListPanel: React.FC<TeamListPanelProps> = ({
  teams,
  selectedTeam,
  onSelectTeam,
  onCreateClick,
  loading,
}) => {
  const [search, setSearch] = useState('');

  const filtered = useMemo(() => {
    if (!search.trim()) return teams;
    const q = search.toLowerCase();
    return teams.filter(t =>
      t.name.toLowerCase().includes(q) ||
      t.team_topology.toLowerCase().includes(q) ||
      (t.description && t.description.toLowerCase().includes(q))
    );
  }, [teams, search]);

  return (
    <ResizableListPanel
      storageKeyPrefix="ai-teams"
      title="Teams"
      headerAction={
        <button
          onClick={onCreateClick}
          className="p-1 rounded text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-hover transition-colors"
          title="Create team"
        >
          <Plus className="h-4 w-4" />
        </button>
      }
      search={
        <div className="px-3 py-2 border-b border-theme">
          <div className="relative">
            <Search size={14} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-theme-secondary" />
            <input
              type="text"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search teams..."
              className="w-full pl-8 pr-3 py-1.5 text-sm border border-theme rounded-md bg-theme-bg text-theme-primary placeholder:text-theme-secondary focus:outline-none focus:ring-1 focus:ring-theme-accent"
            />
          </div>
        </div>
      }
      collapsedContent={
        <div className="flex flex-col items-center gap-1 px-1">
          <Users className="h-4 w-4 text-theme-secondary" />
          <span className="text-[10px] text-theme-secondary">{teams.length}</span>
        </div>
      }
    >
      {loading ? (
        <div className="flex items-center justify-center py-8">
          <div className="animate-spin rounded-full h-5 w-5 border-2 border-theme-accent border-t-transparent" />
        </div>
      ) : filtered.length === 0 ? (
        <div className="px-3 py-8 text-center">
          <Users size={24} className="mx-auto text-theme-secondary mb-2" />
          <p className="text-xs text-theme-secondary">
            {search ? 'No teams match your search' : 'No teams yet'}
          </p>
        </div>
      ) : (
        <div className="py-1">
          {filtered.map(team => (
            <button
              key={team.id}
              onClick={() => onSelectTeam(team)}
              className={`w-full text-left px-3 py-2.5 border-b border-theme/50 transition-colors ${
                selectedTeam?.id === team.id
                  ? 'bg-theme-interactive-primary/10 border-l-2 border-l-theme-interactive-primary'
                  : 'hover:bg-theme-surface-hover border-l-2 border-l-transparent'
              }`}
            >
              <div className="flex items-center justify-between mb-1">
                <span className="text-sm font-medium text-theme-primary truncate">{team.name}</span>
                <span className={`px-1.5 py-0.5 text-[10px] rounded font-medium shrink-0 ${getStatusColor(team.status)}`}>
                  {team.status}
                </span>
              </div>
              <div className="flex items-center gap-2 text-[11px] text-theme-secondary">
                <span className="px-1.5 py-0.5 bg-theme-accent/10 text-theme-accent rounded">{team.team_topology}</span>
                <span>{team.roles_count || 0} roles</span>
                <span>{team.channels_count || 0} ch</span>
              </div>
            </button>
          ))}
        </div>
      )}
    </ResizableListPanel>
  );
};
