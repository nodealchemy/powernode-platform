import React from 'react';
import { Users, Trash2, UserCog, Settings, Clock, Wrench } from 'lucide-react';
import { useSkillCoverage } from '@/features/ai/knowledge-graph/api/skillGraphApi';
import type { Team, TeamRole } from '@/shared/services/ai/TeamsApiService';

interface TeamOverviewTabProps {
  team: Team;
  roles: TeamRole[];
  onDeleteTeam: (teamId: string) => void;
}

function getStatusColor(status: string): string {
  switch (status) {
    case 'active': case 'completed': return 'text-theme-success bg-theme-success/10';
    case 'running': case 'pending': return 'text-theme-warning bg-theme-warning/10';
    case 'paused': return 'text-theme-info bg-theme-info/10';
    case 'failed': case 'cancelled': return 'text-theme-danger bg-theme-danger/10';
    default: return 'text-theme-secondary bg-theme-surface';
  }
}

export const TeamOverviewTab: React.FC<TeamOverviewTabProps> = ({ team, roles, onDeleteTeam }) => {
  const { data: coverage } = useSkillCoverage(team.id);
  const coveragePct = coverage ? Math.round(coverage.coverage_ratio * 100) : null;

  const coverageColorClass = coverage
    ? coverage.coverage_ratio >= 0.7
      ? 'text-theme-success'
      : coverage.coverage_ratio >= 0.4
        ? 'text-theme-warning'
        : 'text-theme-error'
    : 'text-theme-secondary';

  return (
    <div className="space-y-6">
      {/* Team Info Card */}
      <div className="bg-theme-surface border border-theme rounded-lg p-5">
        <div className="flex items-start justify-between mb-4">
          <div>
            <div className="flex items-center gap-3 mb-1">
              <h2 className="text-lg font-semibold text-theme-primary">{team.name}</h2>
              <span className={`px-2 py-0.5 text-xs rounded font-medium ${getStatusColor(team.status)}`}>
                {team.status}
              </span>
            </div>
            <p className="text-sm text-theme-secondary">{team.description || 'No description'}</p>
          </div>
          <button
            onClick={() => onDeleteTeam(team.id)}
            className="p-2 text-theme-secondary hover:text-theme-danger transition-colors rounded hover:bg-theme-danger/10"
            title="Delete team"
          >
            <Trash2 size={16} />
          </button>
        </div>

        <div className="grid grid-cols-2 sm:grid-cols-5 gap-3">
          <div className="bg-theme-surface rounded-lg p-3 border border-theme-light">
            <div className="flex items-center gap-2 mb-1">
              <Settings size={14} className="text-theme-interactive-primary" />
              <span className="text-xs text-theme-secondary">Topology</span>
            </div>
            <span className="text-sm font-medium text-theme-primary capitalize">{team.team_topology}</span>
          </div>
          <div className="bg-theme-surface rounded-lg p-3 border border-theme-light">
            <div className="flex items-center gap-2 mb-1">
              <Users size={14} className="text-theme-interactive-primary" />
              <span className="text-xs text-theme-secondary">Roles</span>
            </div>
            <span className="text-sm font-medium text-theme-primary">{team.roles_count || 0}</span>
          </div>
          <div className="bg-theme-surface rounded-lg p-3 border border-theme-light">
            <div className="flex items-center gap-2 mb-1">
              <UserCog size={14} className="text-theme-interactive-primary" />
              <span className="text-xs text-theme-secondary">Coordination</span>
            </div>
            <span className="text-sm font-medium text-theme-primary capitalize">{team.coordination_strategy}</span>
          </div>
          <div className="bg-theme-surface rounded-lg p-3 border border-theme-light">
            <div className="flex items-center gap-2 mb-1">
              <Clock size={14} className="text-theme-interactive-primary" />
              <span className="text-xs text-theme-secondary">Created</span>
            </div>
            <span className="text-sm font-medium text-theme-primary">{new Date(team.created_at).toLocaleDateString()}</span>
          </div>
          <div className="bg-theme-surface rounded-lg p-3 border border-theme-light">
            <div className="flex items-center gap-2 mb-1">
              <Wrench size={14} className="text-theme-interactive-primary" />
              <span className="text-xs text-theme-secondary">Skill Coverage</span>
            </div>
            <span className={`text-sm font-medium ${coverageColorClass}`}>
              {coveragePct != null ? `${coveragePct}%` : '—'}
            </span>
          </div>
        </div>

        {team.goal_description && (
          <div className="mt-4 p-3 bg-theme-surface rounded-lg border border-theme-light">
            <span className="text-xs text-theme-secondary block mb-1">Goal</span>
            <p className="text-sm text-theme-primary">{team.goal_description}</p>
          </div>
        )}
      </div>

      {/* Member / Role Grid */}
      <div>
        <h3 className="text-sm font-semibold text-theme-primary mb-3 flex items-center gap-2">
          <UserCog size={16} />
          Team Roles ({roles.length})
        </h3>
        {roles.length === 0 ? (
          <div className="text-center py-8 bg-theme-surface border border-theme rounded-lg">
            <UserCog size={32} className="mx-auto text-theme-secondary mb-2" />
            <p className="text-sm text-theme-secondary">No roles defined for this team</p>
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
            {roles.map(role => (
              <div key={role.id} className="bg-theme-surface border border-theme rounded-lg p-3">
                <div className="flex items-center justify-between mb-1.5">
                  <span className="text-sm font-medium text-theme-primary truncate">{role.role_name}</span>
                  <span className="px-1.5 py-0.5 text-[10px] bg-theme-interactive-primary/10 text-theme-interactive-primary rounded shrink-0">
                    {role.role_type}
                  </span>
                </div>
                {role.role_description && (
                  <p className="text-xs text-theme-secondary mb-2 line-clamp-2">{role.role_description}</p>
                )}
                <div className="flex items-center justify-between text-[11px] text-theme-secondary">
                  <span>{role.agent_name || 'Unassigned'}</span>
                  <div className="flex gap-1.5">
                    {role.can_delegate && <span className="text-theme-info">Delegate</span>}
                    {role.can_escalate && <span className="text-theme-warning">Escalate</span>}
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
};
