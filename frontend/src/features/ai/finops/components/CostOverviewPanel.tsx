import React from 'react';
import { DollarSign, Zap, Activity, Bot, Cpu, TrendingUp, TrendingDown } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useFinOpsOverview, useOptimizationScore, useTokenAnalytics } from '../api/finopsApi';

const formatCost = (cost: number | undefined | null): string => {
  const value = cost ?? 0;
  if (value <= 0) return '$0.00';
  if (value < 0.01) return `$${value.toFixed(4)}`;
  if (value >= 1000) return `$${(value / 1000).toFixed(1)}K`;
  return `$${value.toFixed(2)}`;
};

const formatTokens = (tokens: number | undefined | null): string => {
  const value = tokens ?? 0;
  if (value >= 1000000) return `${(value / 1000000).toFixed(1)}M`;
  if (value >= 1000) return `${(value / 1000).toFixed(1)}K`;
  return value.toString();
};

const formatChangePercent = (pct: number): string => {
  const sign = pct > 0 ? '+' : '';
  return `${sign}${pct.toFixed(1)}%`;
};

export const CostOverviewPanel: React.FC = () => {
  const { data: overview, isLoading: overviewLoading } = useFinOpsOverview();
  const { data: optimization, isLoading: optLoading } = useOptimizationScore();
  const { data: tokenAnalytics, isLoading: tokenLoading } = useTokenAnalytics();

  const isLoading = overviewLoading || optLoading || tokenLoading;

  if (isLoading) {
    return <LoadingSpinner size="sm" className="py-8" />;
  }

  const statCards = [
    {
      label: 'Total Cost',
      value: formatCost(overview?.total_cost ?? 0),
      change: overview?.cost_change_pct,
      icon: DollarSign,
      colorClass: 'text-theme-info-fg',
      bgClass: 'bg-theme-info-bg',
    },
    {
      label: 'Total Tokens',
      value: formatTokens(overview?.total_tokens ?? 0),
      change: overview?.token_change_pct,
      icon: Zap,
      colorClass: 'text-theme-warning-fg',
      bgClass: 'bg-theme-warning-bg',
    },
    {
      label: 'Total Requests',
      value: (overview?.total_requests ?? 0).toLocaleString(),
      icon: Activity,
      colorClass: 'text-theme-success-fg',
      bgClass: 'bg-theme-success-bg',
    },
    {
      label: 'Active Agents',
      value: overview?.active_agents ?? 0,
      icon: Bot,
      colorClass: 'text-theme-interactive-primary',
      bgClass: 'bg-theme-interactive-primary',
    },
    {
      label: 'Active Models',
      value: overview?.active_models ?? 0,
      icon: Cpu,
      colorClass: 'text-theme-info-fg',
      bgClass: 'bg-theme-info-bg',
    },
    {
      label: 'Optimization Score',
      value: optimization ? `${optimization.score}/${optimization.max_score}` : '--',
      icon: TrendingUp,
      colorClass: 'text-theme-success-fg',
      bgClass: 'bg-theme-success-bg',
    },
  ];

  return (
    <div className="space-y-6">
      {/* Summary Cards */}
      <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-4">
        {statCards.map((stat) => {
          const Icon = stat.icon;
          return (
            <Card key={stat.label} className="p-4">
              <div className="flex items-center justify-between">
                <div className="min-w-0">
                  <p className="text-xs text-theme-tertiary truncate">{stat.label}</p>
                  <p className="text-xl font-semibold text-theme-primary mt-1">
                    {typeof stat.value === 'number' ? stat.value.toLocaleString() : stat.value}
                  </p>
                  {stat.change !== undefined && stat.change !== null && (
                    <div className={`flex items-center gap-1 mt-1 text-xs ${
                      stat.change > 0 ? 'text-theme-error-fg' : stat.change < 0 ? 'text-theme-success-fg' : 'text-theme-secondary'
                    }`}>
                      {stat.change > 0 ? (
                        <TrendingUp className="h-3 w-3" />
                      ) : stat.change < 0 ? (
                        <TrendingDown className="h-3 w-3" />
                      ) : null}
                      <span>{formatChangePercent(stat.change)}</span>
                    </div>
                  )}
                </div>
                <div className={`h-10 w-10 ${stat.bgClass} rounded-lg flex items-center justify-center flex-shrink-0`}>
                  <Icon className={`h-5 w-5 ${stat.colorClass}`} />
                </div>
              </div>
            </Card>
          );
        })}
      </div>

      {/* Token Breakdown */}
      {tokenAnalytics && (
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <Card className="p-4">
            <p className="text-xs text-theme-tertiary">Input Tokens</p>
            <p className="text-lg font-semibold text-theme-primary mt-1">
              {formatTokens(tokenAnalytics.total_input_tokens)}
            </p>
          </Card>
          <Card className="p-4">
            <p className="text-xs text-theme-tertiary">Output Tokens</p>
            <p className="text-lg font-semibold text-theme-primary mt-1">
              {formatTokens(tokenAnalytics.total_output_tokens)}
            </p>
          </Card>
          <Card className="p-4">
            <p className="text-xs text-theme-tertiary">Avg Tokens / Request</p>
            <p className="text-lg font-semibold text-theme-primary mt-1">
              {formatTokens(tokenAnalytics.avg_tokens_per_request)}
            </p>
          </Card>
        </div>
      )}

      {/* Potential Savings */}
      {optimization && optimization.potential_savings > 0 && (
        <Card className="p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm font-medium text-theme-primary">Potential Savings</p>
              <p className="text-xs text-theme-tertiary mt-0.5">
                Based on {optimization.recommendations?.length ?? 0} optimization recommendation{(optimization.recommendations?.length ?? 0) !== 1 ? 's' : ''}
              </p>
            </div>
            <div className="text-right">
              <p className="text-lg font-bold text-theme-success-fg">
                {formatCost(optimization.potential_savings)}
              </p>
              <p className="text-xs text-theme-success-fg">
                {(optimization.potential_savings_pct ?? 0).toFixed(1)}% reduction
              </p>
            </div>
          </div>
        </Card>
      )}
    </div>
  );
};
