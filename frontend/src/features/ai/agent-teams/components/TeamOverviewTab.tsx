import React from 'react';
import { Users, Trash2, UserCog, Settings, Clock, Wrench, Bot, Crown, Monitor } from 'lucide-react';
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

      {/* Team Composition — unified role-backed view */}
      <div>
        <h3 className="text-sm font-semibold text-theme-primary mb-3 flex items-center gap-2">
          <Users size={16} />
          Team Composition ({roles.length})
        </h3>
        {roles.length === 0 ? (
          <div className="text-center py-8 bg-theme-surface border border-theme rounded-lg">
            <Users size={32} className="mx-auto text-theme-secondary mb-2" />
            <p className="text-sm text-theme-secondary">No roles defined for this team</p>
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
            {roles.map(role => (
              <div key={role.id} className="bg-theme-surface border border-theme rounded-lg p-3">
                <div className="flex items-center gap-2.5 mb-2">
                  <div className="w-8 h-8 rounded-full bg-theme-interactive-primary/10 flex items-center justify-center shrink-0">
                    {role.agent_type === 'mcp_client' ? (
                      <Monitor size={14} className="text-theme-interactive-primary" />
                    ) : role.agent_id ? (
                      <Bot size={14} className="text-theme-interactive-primary" />
                    ) : (
                      <UserCog size={14} className="text-theme-secondary" />
                    )}
                  </div>
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-1.5">
                      <span className="text-sm font-medium text-theme-primary truncate">
                        {role.agent_name || role.role_name}
                      </span>
                      {role.is_lead && <Crown size={12} className="text-theme-warning shrink-0" />}
                    </div>
                    <div className="flex items-center gap-1.5">
                      <span className="px-1.5 py-0.5 text-[10px] bg-theme-interactive-primary/10 text-theme-interactive-primary rounded">
                        {role.role_type}
                      </span>
                      {role.agent_type && (
                        <span className="text-[10px] text-theme-secondary">
                          {role.agent_type === 'mcp_client' ? 'MCP Client' : role.agent_type}
                        </span>
                      )}
                      {!role.agent_id && (
                        <span className="text-[10px] text-theme-warning">Unassigned</span>
                      )}
                    </div>
                  </div>
                </div>
                {role.role_description && (
                  <p className="text-xs text-theme-secondary mb-2 line-clamp-2">{role.role_description}</p>
                )}
                {(role.capabilities.length > 0 || role.can_delegate || role.can_escalate) && (
                  <div className="flex items-center gap-1.5 flex-wrap">
                    {role.capabilities.slice(0, 2).map(cap => (
                      <span key={cap} className="px-1.5 py-0.5 text-[10px] bg-theme-surface border border-theme-light rounded text-theme-secondary truncate max-w-[120px]">
                        {cap}
                      </span>
                    ))}
                    {role.can_delegate && <span className="text-[10px] text-theme-info">Delegate</span>}
                    {role.can_escalate && <span className="text-[10px] text-theme-warning">Escalate</span>}
                  </div>
                )}
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
};
