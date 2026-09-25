import React from 'react';
import type { AgentStats, AgentAnalytics } from '@/shared/services/ai/types/agent-api-types';
import { cn } from '@/shared/utils/cn';

interface AgentPerformanceSummaryProps {
  stats: AgentStats | null;
  analytics: AgentAnalytics | null;
  fallbackSuccessRate?: number;
}

/** Success-rate bar and 30-day execution sparkline for one agent. */
export const AgentPerformanceSummary: React.FC<AgentPerformanceSummaryProps> = ({
  stats,
  analytics,
  fallbackSuccessRate = 0,
}) => {
  const successRate = stats?.success_rate ?? fallbackSuccessRate;
  const trends = analytics?.execution_trends ?? [];

  const hasRate = !!stats && stats.total_executions > 0;
  const hasTrend = trends.length > 1;
  if (!hasRate && !hasTrend) return null;

  const svgWidth = 200;
  const svgHeight = 32;
  const maxCount = Math.max(...trends.map(t => t.count), 1);
  const points = trends.map((t, i) => {
    const x = (i / (trends.length - 1)) * svgWidth;
    const y = svgHeight - (t.count / maxCount) * (svgHeight - 4) - 2;
    return `${x},${y}`;
  }).join(' ');

  return (
    <div className="space-y-4">
      {hasRate && (
        <div>
          <div className="flex items-center justify-between mb-1.5">
            <span className="text-xs text-theme-secondary">Success Rate</span>
            <span className={cn(
              'text-xs font-medium',
              successRate >= 80 ? 'text-theme-success-fg' :
              successRate >= 50 ? 'text-theme-warning-fg' :
              'text-theme-error-fg'
            )}>
              {successRate}%
            </span>
          </div>
          <div className="h-2 bg-theme-background-secondary rounded-full overflow-hidden">
            <div
              className={cn(
                'h-full rounded-full transition-all duration-500',
                successRate >= 80 ? 'bg-theme-status-success' :
                successRate >= 50 ? 'bg-theme-status-warning' :
                'bg-theme-status-error'
              )}
              style={{ width: `${successRate}%` }}
            />
          </div>
        </div>
      )}

      {hasTrend && (
        <div>
          <div className="flex items-center justify-between mb-1">
            <span className="text-xs text-theme-secondary">Executions (30d)</span>
            <span className="text-xs text-theme-tertiary">{trends.length} days</span>
          </div>
          <svg
            viewBox={`0 0 ${svgWidth} ${svgHeight}`}
            preserveAspectRatio="none"
            className="w-full"
            style={{ height: `${svgHeight}px` }}
          >
            <polyline
              fill="none"
              stroke="currentColor"
              strokeWidth="1.5"
              className="text-theme-interactive-primary"
              points={points}
            />
          </svg>
        </div>
      )}
    </div>
  );
};
