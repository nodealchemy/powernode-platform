import React from 'react';
import { Brain, Play, BarChart3, Activity, Users, Crown, DollarSign, Zap } from 'lucide-react';

interface AgentOverviewStats {
  total_agents: number;
  active_agents: number;
  total_executions: number;
  success_rate: number;
  total_tokens_used?: number;
  total_cost_usd?: number;
}

interface TeamOverviewStats {
  total: number;
  active: number;
  totalMembers: number;
  withLead: number;
  byType: Record<string, number>;
}

interface AgentsOverviewTabProps {
  agentStats: AgentOverviewStats;
  teamStats: TeamOverviewStats;
}

const formatTokens = (tokens: number): string => {
  if (tokens >= 1000000) return `${(tokens / 1000000).toFixed(1)}M`;
  if (tokens >= 1000) return `${(tokens / 1000).toFixed(1)}K`;
  return tokens.toString();
};

const formatCost = (cost: number): string => {
  if (cost <= 0) return '$0.00';
  if (cost < 0.01) return `$${cost.toFixed(4)}`;
  return `$${cost.toFixed(2)}`;
};

export const AgentsOverviewTab: React.FC<AgentsOverviewTabProps> = ({ agentStats, teamStats }) => (
  <div className="space-y-6">
    {/* Agent Stats */}
    <div>
      <h4 className="text-sm font-semibold text-theme-secondary uppercase tracking-wide mb-3">Agents</h4>
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <div className="bg-theme-surface border border-theme rounded-lg p-4">
          <div className="flex items-center gap-2 mb-2">
            <Brain className="h-4 w-4 text-theme-info" />
            <span className="text-xs font-medium text-theme-secondary">Total Agents</span>
          </div>
          <div className="text-2xl font-bold text-theme-primary">{agentStats.total_agents}</div>
        </div>
        <div className="bg-theme-surface border border-theme rounded-lg p-4">
          <div className="flex items-center gap-2 mb-2">
            <Play className="h-4 w-4 text-theme-success" />
            <span className="text-xs font-medium text-theme-secondary">Active</span>
          </div>
          <div className="text-2xl font-bold text-theme-success">{agentStats.active_agents}</div>
        </div>
        <div className="bg-theme-surface border border-theme rounded-lg p-4">
          <div className="flex items-center gap-2 mb-2">
            <BarChart3 className="h-4 w-4 text-theme-warning" />
            <span className="text-xs font-medium text-theme-secondary">Executions</span>
          </div>
          <div className="text-2xl font-bold text-theme-primary">{agentStats.total_executions}</div>
        </div>
        <div className="bg-theme-surface border border-theme rounded-lg p-4">
          <div className="flex items-center gap-2 mb-2">
            <Activity className="h-4 w-4 text-theme-success" />
            <span className="text-xs font-medium text-theme-secondary">Success Rate</span>
          </div>
          <div className="text-2xl font-bold text-theme-primary">{agentStats.success_rate}%</div>
        </div>
      </div>
    </div>

    {/* Cost Summary */}
    {((agentStats.total_tokens_used ?? 0) > 0 || (agentStats.total_cost_usd ?? 0) > 0) && (
      <div>
        <h4 className="text-sm font-semibold text-theme-secondary uppercase tracking-wide mb-3">Usage</h4>
        <div className="grid grid-cols-2 gap-4">
          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <div className="flex items-center gap-2 mb-2">
              <Zap className="h-4 w-4 text-theme-interactive-primary" />
              <span className="text-xs font-medium text-theme-secondary">Total Tokens</span>
            </div>
            <div className="text-2xl font-bold text-theme-primary">
              {formatTokens(agentStats.total_tokens_used ?? 0)}
            </div>
          </div>
          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <div className="flex items-center gap-2 mb-2">
              <DollarSign className="h-4 w-4 text-theme-warning" />
              <span className="text-xs font-medium text-theme-secondary">Total Cost</span>
            </div>
            <div className={`text-2xl font-bold ${
              (agentStats.total_cost_usd ?? 0) < 0.01 ? 'text-theme-success' :
              (agentStats.total_cost_usd ?? 0) < 1.00 ? 'text-theme-warning' :
              'text-theme-danger'
            }`}>
              {formatCost(agentStats.total_cost_usd ?? 0)}
            </div>
          </div>
        </div>
      </div>
    )}

    {/* Team Stats */}
    <div>
      <h4 className="text-sm font-semibold text-theme-secondary uppercase tracking-wide mb-3">Teams</h4>
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <div className="bg-theme-surface border border-theme rounded-lg p-4">
          <div className="flex items-center gap-2 mb-2">
            <Users className="h-4 w-4 text-theme-info" />
            <span className="text-xs font-medium text-theme-secondary">Total Teams</span>
          </div>
          <div className="text-2xl font-bold text-theme-primary">{teamStats.total}</div>
        </div>
        <div className="bg-theme-surface border border-theme rounded-lg p-4">
          <div className="flex items-center gap-2 mb-2">
            <Activity className="h-4 w-4 text-theme-success" />
            <span className="text-xs font-medium text-theme-secondary">Active Teams</span>
          </div>
          <div className="text-2xl font-bold text-theme-success">{teamStats.active}</div>
        </div>
        <div className="bg-theme-surface border border-theme rounded-lg p-4">
          <div className="flex items-center gap-2 mb-2">
            <Users className="h-4 w-4 text-theme-interactive-primary" />
            <span className="text-xs font-medium text-theme-secondary">Total Members</span>
          </div>
          <div className="text-2xl font-bold text-theme-primary">{teamStats.totalMembers}</div>
        </div>
        <div className="bg-theme-surface border border-theme rounded-lg p-4">
          <div className="flex items-center gap-2 mb-2">
            <Crown className="h-4 w-4 text-theme-warning" />
            <span className="text-xs font-medium text-theme-secondary">With Lead</span>
          </div>
          <div className="text-2xl font-bold text-theme-primary">{teamStats.withLead}</div>
        </div>
      </div>
    </div>

    {/* Team Type Breakdown */}
    {Object.keys(teamStats.byType).length > 0 && (
      <div className="bg-theme-surface border border-theme rounded-lg p-4">
        <h4 className="text-sm font-semibold text-theme-primary mb-3">Teams by Type</h4>
        <div className="space-y-2">
          {Object.entries(teamStats.byType).map(([type, count]) => (
            <div key={type} className="flex items-center justify-between">
              <span className="text-sm text-theme-primary capitalize">{type}</span>
              <div className="flex items-center gap-2">
                <div className="w-32 bg-theme-accent rounded-full h-2">
                  <div
                    className="h-2 rounded-full bg-theme-interactive-primary transition-all"
                    style={{ width: `${(count / teamStats.total) * 100}%` }}
                  />
                </div>
                <span className="text-sm font-medium text-theme-primary w-6 text-right">{count}</span>
              </div>
            </div>
          ))}
        </div>
      </div>
    )}
  </div>
);
