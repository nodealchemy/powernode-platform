import React, { useState, useCallback } from 'react';
import { Brain, Play, BarChart3, Activity, Users, Crown, DollarSign, Zap, ChevronDown } from 'lucide-react';
import { cn } from '@/shared/utils/cn';
import { formatTokens, formatCost, successRateColor } from '../constants/agentConstants';

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

interface ExpandableStatsHeaderProps {
  agentStats: AgentOverviewStats;
  teamStats: TeamOverviewStats;
  loading?: boolean;
}

function formatCompactExecutions(count: number): string {
  if (count >= 1000000) return `${(count / 1000000).toFixed(1)}M`;
  if (count >= 1000) return `${(count / 1000).toFixed(1)}K`;
  return count.toString();
}

interface StatCardProps {
  icon: React.ElementType;
  iconColor: string;
  label: string;
  value: string | number;
  valueColor: string;
}

const StatCard: React.FC<StatCardProps> = ({ icon: Icon, iconColor, label, value, valueColor }) => (
  <div className="bg-theme-surface border border-theme rounded-lg p-4">
    <div className="flex items-center gap-2 mb-2">
      <Icon className={cn('h-4 w-4', iconColor)} />
      <span className="text-xs font-medium text-theme-secondary">{label}</span>
    </div>
    <div className={cn('text-2xl font-bold', valueColor)}>{value}</div>
  </div>
);

export const ExpandableStatsHeader: React.FC<ExpandableStatsHeaderProps> = ({
  agentStats,
  teamStats,
  loading,
}) => {
  const [expanded, setExpanded] = useState(() => {
    return localStorage.getItem('agents-stats-expanded') === 'true';
  });

  const toggleExpanded = useCallback(() => {
    setExpanded(prev => {
      localStorage.setItem('agents-stats-expanded', String(!prev));
      return !prev;
    });
  }, []);

  if (loading) {
    return (
      <div className="mb-4">
        <div className="h-8 bg-theme-surface animate-pulse rounded-lg" />
      </div>
    );
  }

  const showUsageRow =
    (agentStats.total_tokens_used != null && agentStats.total_tokens_used > 0) ||
    (agentStats.total_cost_usd != null && agentStats.total_cost_usd > 0);

  return (
    <div className="mb-4">
      {/* Compact row — always visible */}
      <button
        type="button"
        onClick={toggleExpanded}
        className="w-full flex items-center justify-between px-3 py-2 rounded-lg bg-theme-surface border border-theme hover:bg-theme-surface-hover transition-colors cursor-pointer"
      >
        <div className="flex items-center gap-1.5 text-sm text-theme-secondary flex-wrap">
          <span>{agentStats.total_agents} total</span>
          <span className="text-theme-tertiary">·</span>
          <span className="text-theme-success">{agentStats.active_agents} active</span>
          <span className="text-theme-tertiary">·</span>
          <span className={successRateColor(agentStats.success_rate)}>
            {agentStats.success_rate}% success
          </span>
          <span className="text-theme-tertiary">·</span>
          <span>{formatCompactExecutions(agentStats.total_executions)} runs</span>
        </div>

        <ChevronDown
          className={cn(
            'h-4 w-4 text-theme-secondary transition-transform duration-300',
            expanded && 'rotate-180'
          )}
        />
      </button>

      {/* Expanded stat cards */}
      <div
        className={cn(
          'overflow-hidden transition-all duration-300 ease-in-out',
          expanded ? 'max-h-[600px] opacity-100 mt-4' : 'max-h-0 opacity-0'
        )}
      >
        {/* Agent Stats */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
          <StatCard
            icon={Brain}
            iconColor="text-theme-info"
            label="Total Agents"
            value={agentStats.total_agents}
            valueColor="text-theme-info"
          />
          <StatCard
            icon={Play}
            iconColor="text-theme-success"
            label="Active"
            value={agentStats.active_agents}
            valueColor="text-theme-success"
          />
          <StatCard
            icon={BarChart3}
            iconColor="text-theme-warning"
            label="Executions"
            value={agentStats.total_executions.toLocaleString()}
            valueColor="text-theme-warning"
          />
          <StatCard
            icon={Activity}
            iconColor="text-theme-success"
            label="Success Rate"
            value={`${agentStats.success_rate}%`}
            valueColor={successRateColor(agentStats.success_rate)}
          />
        </div>

        {/* Usage Stats (conditional) */}
        {showUsageRow && (
          <div className="grid grid-cols-2 gap-3 mt-3">
            <StatCard
              icon={Zap}
              iconColor="text-theme-warning"
              label="Total Tokens"
              value={formatTokens(agentStats.total_tokens_used ?? 0)}
              valueColor="text-theme-warning"
            />
            <StatCard
              icon={DollarSign}
              iconColor="text-theme-success"
              label="Total Cost"
              value={formatCost(agentStats.total_cost_usd ?? 0)}
              valueColor="text-theme-success"
            />
          </div>
        )}

        {/* Team Stats */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mt-3">
          <StatCard
            icon={Users}
            iconColor="text-theme-info"
            label="Total Teams"
            value={teamStats.total}
            valueColor="text-theme-info"
          />
          <StatCard
            icon={Activity}
            iconColor="text-theme-success"
            label="Active Teams"
            value={teamStats.active}
            valueColor="text-theme-success"
          />
          <StatCard
            icon={Users}
            iconColor="text-theme-interactive-primary"
            label="Total Members"
            value={teamStats.totalMembers}
            valueColor="text-theme-interactive-primary"
          />
          <StatCard
            icon={Crown}
            iconColor="text-theme-warning"
            label="With Lead"
            value={teamStats.withLead}
            valueColor="text-theme-warning"
          />
        </div>
      </div>
    </div>
  );
};
