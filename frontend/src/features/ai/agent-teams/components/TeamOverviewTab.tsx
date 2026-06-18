import React from 'react';
import { Users, Trash2, UserCog, Settings, Clock, Wrench, Bot, Crown, Monitor, Zap, Cpu, Activity, History } from 'lucide-react';
import { EntityLink } from '@/shared/components/entity';
import { useSkillCoverage } from '@/features/ai/knowledge-graph/api/skillGraphApi';
import type { Team, TeamRole, TeamActivationRules, TeamEventHistoryEntry } from '@/shared/services/ai/TeamsApiService';

interface TeamOverviewTabProps {
  team: Team;
  roles: TeamRole[];
  onDeleteTeam: (teamId: string) => void;
}

function getStatusColor(status: string): string {
  switch (status) {
    case 'active': case 'completed': return 'text-theme-success-fg bg-theme-success-fg/10';
    case 'running': case 'pending': return 'text-theme-warning-fg bg-theme-warning-fg/10';
    case 'paused': return 'text-theme-info-fg bg-theme-info-fg/10';
    case 'failed': case 'cancelled': return 'text-theme-danger-fg bg-theme-danger-fg/10';
    default: return 'text-theme-secondary bg-theme-surface';
  }
}

function formatRelativeTime(iso: string | null | undefined): string {
  if (!iso) return '—';
  const date = new Date(iso);
  const diffMs = Date.now() - date.getTime();
  const minutes = Math.round(diffMs / 60000);
  if (minutes < 1) return 'just now';
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.round(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.round(hours / 24);
  if (days < 7) return `${days}d ago`;
  return date.toLocaleDateString();
}

function successRateColorClass(rate: number | null): string {
  if (rate === null) return 'text-theme-secondary';
  if (rate >= 0.8) return 'text-theme-success-fg';
  if (rate >= 0.5) return 'text-theme-warning-fg';
  return 'text-theme-danger-fg';
}

export const TeamOverviewTab: React.FC<TeamOverviewTabProps> = ({ team, roles, onDeleteTeam }) => {
  const { data: coverage } = useSkillCoverage(team.id);
  const coveragePct = coverage ? Math.round(coverage.coverage_ratio * 100) : null;

  const teamConfig = (team.team_config ?? {}) as { activation_rules?: TeamActivationRules; event_history?: TeamEventHistoryEntry[] };
  const activationRules: TeamActivationRules = teamConfig.activation_rules ?? {};
  const eventHistory: TeamEventHistoryEntry[] = Array.isArray(teamConfig.event_history) ? teamConfig.event_history : [];
  const subscribedEvents = activationRules.on_event ?? [];
  const triggersEnabled = activationRules.enabled === true && subscribedEvents.length > 0;

  const coverageColorClass = coverage
    ? coverage.coverage_ratio >= 0.7
      ? 'text-theme-success-fg'
      : coverage.coverage_ratio >= 0.4
        ? 'text-theme-warning-fg'
        : 'text-theme-error-fg'
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
            className="p-2 text-theme-secondary hover:text-theme-danger-fg transition-colors rounded hover:bg-theme-danger-fg/10"
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

      {/* Event Triggers (T4) — visible only when team subscribes to signals */}
      {subscribedEvents.length > 0 && (
        <div className="bg-theme-surface border border-theme rounded-lg p-5">
          <div className="flex items-center justify-between mb-3">
            <h3 className="text-sm font-semibold text-theme-primary flex items-center gap-2">
              <Zap size={16} className={triggersEnabled ? 'text-theme-warning-fg' : 'text-theme-secondary'} />
              Event Triggers
            </h3>
            <span
              className={`px-2 py-0.5 text-[10px] rounded font-medium ${
                triggersEnabled
                  ? 'text-theme-success-fg bg-theme-success-fg/10'
                  : 'text-theme-secondary bg-theme-surface border border-theme-light'
              }`}
              title={triggersEnabled ? 'Team will activate on matching signals' : 'Subscriptions defined but dispatch is gated off'}
            >
              {triggersEnabled ? 'Enabled' : 'Disabled'}
            </span>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 mb-3">
            <div className="bg-theme-surface rounded-lg p-3 border border-theme-light">
              <span className="text-xs text-theme-secondary block mb-1">Subscribed events</span>
              <div className="flex flex-wrap gap-1">
                {subscribedEvents.map(key => (
                  <span key={key} className="px-1.5 py-0.5 text-[10px] font-mono bg-theme-interactive-primary/10 text-theme-interactive-primary rounded">
                    {key}
                  </span>
                ))}
              </div>
            </div>
            <div className="bg-theme-surface rounded-lg p-3 border border-theme-light">
              <span className="text-xs text-theme-secondary block mb-1">Min signal strength</span>
              <span className="text-sm font-medium text-theme-primary">
                {activationRules.min_strength != null && activationRules.min_strength > 0
                  ? activationRules.min_strength.toFixed(2)
                  : 'any'}
              </span>
            </div>
            <div className="bg-theme-surface rounded-lg p-3 border border-theme-light">
              <span className="text-xs text-theme-secondary block mb-1">Cooldown</span>
              <span className="text-sm font-medium text-theme-primary">
                {activationRules.cooldown_seconds != null && activationRules.cooldown_seconds > 0
                  ? `${activationRules.cooldown_seconds}s`
                  : 'none'}
              </span>
            </div>
          </div>

          {eventHistory.length > 0 && (
            <div>
              <h4 className="text-xs font-semibold text-theme-primary flex items-center gap-1.5 mb-2">
                <History size={12} />
                Recent dispatches ({eventHistory.length})
              </h4>
              <div className="space-y-1.5 max-h-48 overflow-y-auto">
                {eventHistory.slice(0, 10).map((entry, idx) => (
                  <div
                    key={`${entry.dispatched_at}-${idx}`}
                    className="flex items-center justify-between text-xs bg-theme-surface border border-theme-light rounded px-2.5 py-1.5"
                  >
                    <div className="flex items-center gap-2 min-w-0">
                      <Zap size={11} className="text-theme-warning-fg shrink-0" />
                      <span className="font-mono text-theme-primary truncate">{entry.signal_key}</span>
                      {entry.execution_id && (
                        <span className="font-mono text-[10px] text-theme-secondary truncate">
                          → {entry.execution_id}
                        </span>
                      )}
                    </div>
                    <span className="text-theme-secondary shrink-0 ml-2">{formatRelativeTime(entry.dispatched_at)}</span>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      )}

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
            {roles.map(role => {
              const perf = role.model_performance;
              const sel = role.model_selection;
              const successRate = perf?.success_rate ?? null;
              const successRateLabel = successRate !== null
                ? `${Math.round(successRate * 100)}%`
                : perf
                  ? `${perf.successful_runs}/${perf.total_runs}`
                  : '—';
              return (
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
                        <EntityLink
                          type="agent"
                          id={role.agent_id}
                          label={role.agent_name || role.role_name}
                          className="text-sm font-medium truncate"
                        />
                        {role.is_lead && <Crown size={12} className="text-theme-warning-fg shrink-0" />}
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
                          <span className="text-[10px] text-theme-warning-fg">Unassigned</span>
                        )}
                      </div>
                    </div>
                  </div>

                  {(role.agent_model || role.agent_provider) && (
                    <div className="flex items-center gap-1.5 mb-2 text-[11px]" title={sel?.reason || 'Provider/model assigned to this agent'}>
                      <Cpu size={11} className="text-theme-secondary shrink-0" />
                      {role.agent_provider && (
                        <span className="px-1.5 py-0.5 text-[10px] bg-theme-surface border border-theme-light rounded text-theme-secondary">
                          {role.agent_provider}
                        </span>
                      )}
                      {role.agent_model && (
                        <span className="font-mono text-[10px] text-theme-primary truncate">{role.agent_model}</span>
                      )}
                      {sel && (
                        <span className="text-[10px] text-theme-info-fg" title="Model picked by AgentModelSelector">AI</span>
                      )}
                    </div>
                  )}

                  {perf && (
                    <div
                      className="flex items-center gap-3 mb-2 text-[11px] bg-theme-surface border border-theme-light rounded px-2 py-1"
                      title={`${perf.successful_runs}/${perf.total_runs} successful, last run ${formatRelativeTime(perf.last_run_at)}`}
                    >
                      <span className="flex items-center gap-1">
                        <Activity size={10} className={successRateColorClass(successRate)} />
                        <span className={`font-medium ${successRateColorClass(successRate)}`}>{successRateLabel}</span>
                      </span>
                      <span className="text-theme-secondary">n={perf.total_runs}</span>
                      {perf.avg_cost_usd > 0 && (
                        <span className="text-theme-secondary">${perf.avg_cost_usd.toFixed(4)}/run</span>
                      )}
                    </div>
                  )}

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
                      {role.can_delegate && <span className="text-[10px] text-theme-info-fg">Delegate</span>}
                      {role.can_escalate && <span className="text-[10px] text-theme-warning-fg">Escalate</span>}
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
};
