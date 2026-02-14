import React from 'react';
import {
  TrendingUp,
  TrendingDown,
  BarChart3,
  Activity,
  Clock,
  CheckCircle,
  XCircle
} from 'lucide-react';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { WorkflowStatistics } from '@/shared/services/ai';
import { WorkflowExecutionStats } from '@/shared/types/workflow';

interface AnalyticsSummaryCardsProps {
  statistics: WorkflowStatistics;
  metrics: WorkflowExecutionStats;
  formatDuration: (ms: number) => string;
  formatPercentage: (value: number) => string;
}

export const AnalyticsSummaryCards: React.FC<AnalyticsSummaryCardsProps> = ({
  statistics,
  metrics,
  formatDuration,
  formatPercentage,
}) => {
  return (
    <>
      {/* Overview Metrics */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-muted">Total Workflows</p>
                <p className="text-2xl font-bold text-theme-primary">{statistics?.totalWorkflows || 0}</p>
              </div>
              <BarChart3 className="h-8 w-8 text-theme-info" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-muted">Active Workflows</p>
                <p className="text-2xl font-bold text-theme-primary">{statistics?.activeWorkflows || 0}</p>
              </div>
              <Activity className="h-8 w-8 text-theme-success" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-muted">Total Executions</p>
                <p className="text-2xl font-bold text-theme-primary">{metrics?.totalExecutions || 0}</p>
              </div>
              <CheckCircle className="h-8 w-8 text-theme-success" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-muted">Success Rate</p>
                <p className="text-2xl font-bold text-theme-primary">{formatPercentage(metrics?.successRate || 0)}</p>
              </div>
              <TrendingUp className="h-8 w-8 text-theme-success" />
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Performance Metrics */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-muted">Avg Execution Time</p>
                <p className="text-2xl font-bold text-theme-primary">{formatDuration(metrics?.avgExecutionTime || 0)}</p>
              </div>
              <Clock className="h-8 w-8 text-theme-info" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-muted">Failed Executions</p>
                <p className="text-2xl font-bold text-theme-primary">{metrics?.failedExecutions || 0}</p>
              </div>
              <XCircle className="h-8 w-8 text-theme-danger" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-muted">Min Execution Time</p>
                <p className="text-2xl font-bold text-theme-primary">{formatDuration(metrics?.minExecutionTime || 0)}</p>
              </div>
              <TrendingDown className="h-8 w-8 text-theme-success" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-muted">Max Execution Time</p>
                <p className="text-2xl font-bold text-theme-primary">{formatDuration(metrics?.maxExecutionTime || 0)}</p>
              </div>
              <TrendingUp className="h-8 w-8 text-theme-warning" />
            </div>
          </CardContent>
        </Card>
      </div>
    </>
  );
};
