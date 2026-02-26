import React from 'react';
import { Card, CardContent } from '@/shared/components/ui/Card';
import type { AgentStats } from '@/shared/services/ai/types/agent-api-types';

interface AgentDetailStatsCardsProps {
  stats: AgentStats;
}

function formatDuration(ms: number): string {
  if (!ms || isNaN(ms)) return '—';
  if (ms < 1000) return `${Math.round(ms)}ms`;
  return `${(ms / 1000).toFixed(1)}s`;
}

function successRateColor(rate: number): string {
  if (rate >= 80) return 'text-theme-success';
  if (rate >= 50) return 'text-theme-warning';
  return 'text-theme-error';
}

export const AgentDetailStatsCards: React.FC<AgentDetailStatsCardsProps> = ({ stats }) => {
  return (
    <div className="grid grid-cols-4 gap-4">
      <Card>
        <CardContent className="p-4">
          <div className="text-2xl font-bold text-theme-text-primary">
            {stats.total_executions}
          </div>
          <div className="text-sm text-theme-text-secondary">Total Executions</div>
        </CardContent>
      </Card>
      <Card>
        <CardContent className="p-4">
          <div className={`text-2xl font-bold ${successRateColor(stats.success_rate || 0)}`}>
            {isNaN(stats.success_rate) ? '—' : `${stats.success_rate}%`}
          </div>
          <div className="text-sm text-theme-text-secondary">Success Rate</div>
        </CardContent>
      </Card>
      <Card>
        <CardContent className="p-4">
          <div className="text-2xl font-bold text-theme-text-primary">
            {formatDuration(stats.avg_execution_time)}
          </div>
          <div className="text-sm text-theme-text-secondary">Avg Time</div>
        </CardContent>
      </Card>
      <Card>
        <CardContent className="p-4">
          <div className="text-2xl font-bold text-theme-warning">
            ${stats.estimated_total_cost || '0.00'}
          </div>
          <div className="text-sm text-theme-text-secondary">Est. Cost</div>
        </CardContent>
      </Card>
    </div>
  );
};
