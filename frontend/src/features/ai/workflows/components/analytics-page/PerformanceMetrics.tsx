import React from 'react';
import { BarChart3, Activity, AlertTriangle } from 'lucide-react';
import { Card, CardTitle, CardContent } from '@/shared/components/ui/Card';
import { WorkflowStatistics } from '@/shared/services/ai';
import { WorkflowExecutionStats } from '@/shared/types/workflow';

interface PerformanceMetricsProps {
  statistics: WorkflowStatistics;
  metrics: WorkflowExecutionStats;
  formatDuration: (ms: number) => string;
  formatPercentage: (value: number) => string;
}

export const PerformanceMetrics: React.FC<PerformanceMetricsProps> = ({
  statistics,
  metrics,
  formatDuration,
  formatPercentage,
}) => {
  return (
    <>
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Daily Executions */}
        <Card>
          <CardTitle className="flex items-center gap-2">
            <BarChart3 className="h-5 w-5" />
            Daily Executions
          </CardTitle>
          <CardContent>
            <div className="space-y-4">
              {Object.entries(metrics?.dailyExecutions || {}).map(([date, count]) => (
                <div key={date} className="flex items-center justify-between">
                  <span className="text-sm text-theme-muted">{new Date(date).toLocaleDateString()}</span>
                  <span className="font-medium">{count}</span>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>

        {/* Most Active Users */}
        <Card>
          <CardTitle className="flex items-center gap-2">
            <Activity className="h-5 w-5" />
            Most Active Users
          </CardTitle>
          <CardContent>
            <div className="space-y-4">
              {Object.entries(metrics?.mostActiveUsers || {}).map(([user, count]) => (
                <div key={user} className="flex items-center justify-between">
                  <span className="text-sm text-theme-primary">{user}</span>
                  <span className="font-medium">{count} executions</span>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Recommendations */}
      <Card>
        <CardTitle className="flex items-center gap-2">
          <AlertTriangle className="h-5 w-5" />
          Optimization Recommendations
        </CardTitle>
        <CardContent>
          <div className="space-y-4">
            {(metrics?.successRate || 0) < 90 && (
              <div className="p-4 bg-theme-warning/10 border border-theme-warning/20 rounded-lg">
                <h4 className="font-medium text-theme-warning mb-2">Low Success Rate</h4>
                <p className="text-sm text-theme-warning">
                  Your workflows have a {formatPercentage(metrics?.successRate || 0)} success rate.
                  Consider reviewing failed executions and improving error handling.
                </p>
              </div>
            )}
            {(metrics?.avgExecutionTime || 0) > 300000 && (
              <div className="p-4 bg-theme-info/10 border border-theme-info/20 rounded-lg">
                <h4 className="font-medium text-theme-info mb-2">High Execution Time</h4>
                <p className="text-sm text-theme-info">
                  Average execution time is {formatDuration(metrics?.avgExecutionTime || 0)}.
                  Consider optimizing workflow logic or using parallel execution mode.
                </p>
              </div>
            )}
            {(statistics?.draftWorkflows || 0) > (statistics?.activeWorkflows || 0) && (
              <div className="p-4 bg-theme-accent/10 border border-theme-accent/20 rounded-lg">
                <h4 className="font-medium text-theme-accent mb-2">Many Draft Workflows</h4>
                <p className="text-sm text-theme-accent">
                  You have {statistics?.draftWorkflows || 0} draft workflows.
                  Consider reviewing and publishing useful workflows.
                </p>
              </div>
            )}
            {(metrics?.totalExecutions || 0) === 0 && (
              <div className="p-4 bg-theme-surface border border-theme rounded-lg">
                <h4 className="font-medium text-theme-primary mb-2">No Recent Executions</h4>
                <p className="text-sm text-theme-tertiary">
                  No workflow executions found in the selected period.
                  Try expanding the date range or execute some workflows to see analytics.
                </p>
              </div>
            )}
          </div>
        </CardContent>
      </Card>
    </>
  );
};
