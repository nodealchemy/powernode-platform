import React from 'react';
import { DollarSign, Zap, Clock } from 'lucide-react';
import type { MemberCost } from '../services/agentTeamsApi';

interface CostProfilerProps {
  totalTokens?: number;
  totalCost?: number;
  memberCosts?: MemberCost[];
  className?: string;
}

const getCostTier = (cost: number): { color: string; label: string } => {
  if (cost <= 0) return { color: 'text-theme-secondary', label: 'Free' };
  if (cost < 0.01) return { color: 'text-theme-success', label: 'Low' };
  if (cost < 0.10) return { color: 'text-theme-warning', label: 'Medium' };
  return { color: 'text-theme-danger', label: 'High' };
};

const formatCost = (cost: number): string => {
  if (cost <= 0) return '$0.00';
  if (cost < 0.01) return `$${cost.toFixed(4)}`;
  return `$${cost.toFixed(2)}`;
};

const formatTokens = (tokens: number): string => {
  if (tokens >= 1000000) return `${(tokens / 1000000).toFixed(1)}M`;
  if (tokens >= 1000) return `${(tokens / 1000).toFixed(1)}K`;
  return tokens.toString();
};

const formatDuration = (ms: number): string => {
  if (ms < 1000) return `${ms}ms`;
  if (ms < 60000) return `${(ms / 1000).toFixed(1)}s`;
  const minutes = Math.floor(ms / 60000);
  const seconds = Math.round((ms % 60000) / 1000);
  return `${minutes}m ${seconds}s`;
};

export const CostProfiler: React.FC<CostProfilerProps> = ({
  totalTokens = 0,
  totalCost = 0,
  memberCosts = [],
  className = '',
}) => {
  const costTier = getCostTier(totalCost);

  return (
    <div className={`bg-theme-surface border border-theme rounded-lg ${className}`}>
      {/* Summary row */}
      <div className="p-4 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className="h-8 w-8 rounded-lg bg-theme-info/10 flex items-center justify-center">
            <DollarSign className="h-4 w-4 text-theme-info" />
          </div>
          <div>
            <p className="text-xs text-theme-secondary">Execution Cost</p>
            <p className={`text-lg font-bold ${costTier.color}`}>{formatCost(totalCost)}</p>
          </div>
        </div>
        <div className="flex items-center gap-6">
          <div className="text-right">
            <p className="text-xs text-theme-secondary">Tokens</p>
            <p className="text-sm font-semibold text-theme-primary flex items-center gap-1">
              <Zap className="h-3 w-3" />
              {formatTokens(totalTokens)}
            </p>
          </div>
          <div className={`px-2 py-0.5 text-xs font-medium rounded-full ${
            costTier.label === 'Low' ? 'bg-theme-success/10 text-theme-success' :
            costTier.label === 'Medium' ? 'bg-theme-warning/10 text-theme-warning' :
            costTier.label === 'High' ? 'bg-theme-error/10 text-theme-danger' :
            'bg-theme-accent text-theme-secondary'
          }`}>
            {costTier.label}
          </div>
        </div>
      </div>

      {/* Per-member breakdown */}
      {memberCosts.length > 0 && (
        <div className="border-t border-theme">
          <div className="px-4 py-2">
            <h4 className="text-xs font-semibold text-theme-secondary uppercase tracking-wide">Per-Agent Breakdown</h4>
          </div>
          <div className="divide-y divide-theme">
            {memberCosts.map((member) => {
              const memberTier = getCostTier(member.cost_usd);
              const costPct = totalCost > 0 ? (member.cost_usd / totalCost) * 100 : 0;

              return (
                <div key={member.agent_id} className="px-4 py-2 flex items-center justify-between">
                  <div className="flex items-center gap-2 min-w-0">
                    <div className={`w-1.5 h-1.5 rounded-full flex-shrink-0 ${
                      member.status === 'completed' ? 'bg-theme-success-solid' :
                      member.status === 'failed' ? 'bg-theme-danger-solid' :
                      'bg-theme-muted'
                    }`} />
                    <span className="text-sm text-theme-primary truncate">{member.agent_name}</span>
                  </div>
                  <div className="flex items-center gap-4 flex-shrink-0">
                    <span className="text-xs text-theme-secondary flex items-center gap-1">
                      <Zap className="h-3 w-3" />
                      {formatTokens(member.tokens_used)}
                    </span>
                    <span className="text-xs text-theme-secondary flex items-center gap-1">
                      <Clock className="h-3 w-3" />
                      {formatDuration(member.duration_ms)}
                    </span>
                    <div className="w-16 text-right">
                      <span className={`text-xs font-medium ${memberTier.color}`}>
                        {formatCost(member.cost_usd)}
                      </span>
                    </div>
                    {totalCost > 0 && (
                      <div className="w-12">
                        <div className="w-full bg-theme-accent rounded-full h-1">
                          <div
                            className="h-1 rounded-full bg-theme-interactive-primary transition-all"
                            style={{ width: `${Math.min(costPct, 100)}%` }}
                          />
                        </div>
                      </div>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
};
