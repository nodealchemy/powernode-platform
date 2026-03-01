import React from 'react';
import { Activity, Clock } from 'lucide-react';
import { Card, CardTitle, CardContent } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Progress } from '@/shared/components/ui/Progress';
import type { WorkflowHealthData } from '@/shared/types/workflow';

interface HealthIndicatorsProps {
  health: WorkflowHealthData['health'] | null;
}

const getStatusColor = (status: string) => {
  switch (status) {
    case 'healthy': return 'text-theme-success';
    case 'warning': return 'text-theme-warning';
    case 'error': return 'text-theme-danger';
    default: return 'text-theme-muted';
  }
};

export const HealthIndicators: React.FC<HealthIndicatorsProps> = ({ health }) => (
  <Card>
    <CardTitle className="flex items-center gap-2 p-4 pb-0">
      <Activity className="h-5 w-5" />
      System Health
    </CardTitle>
    <CardContent className="space-y-4 pt-4">
      {health ? (
        <>
          <div className="flex items-center justify-between">
            <span className="text-sm font-medium">Workflow Engine</span>
            <Badge className={getStatusColor(health.workflowEngineStatus)}>
              {health.workflowEngineStatus}
            </Badge>
          </div>

          <div className="space-y-2">
            <div className="flex items-center justify-between text-sm">
              <span>CPU Usage</span>
              <span>{health.resourceUsage?.cpuUsage || 0}%</span>
            </div>
            <Progress value={health.resourceUsage?.cpuUsage || 0} className="h-2" />
          </div>

          <div className="space-y-2">
            <div className="flex items-center justify-between text-sm">
              <span>Memory Usage</span>
              <span>{health.resourceUsage?.memoryUsage || 0}%</span>
            </div>
            <Progress value={health.resourceUsage?.memoryUsage || 0} className="h-2" />
          </div>

          <div className="space-y-2">
            <div className="flex items-center justify-between text-sm">
              <span>Disk Usage</span>
              <span>{health.resourceUsage?.diskUsage || 0}%</span>
            </div>
            <Progress value={health.resourceUsage?.diskUsage || 0} className="h-2" />
          </div>

          <div className="grid grid-cols-2 gap-4 text-sm">
            <div>
              <span className="text-theme-muted">Queue Length</span>
              <p className="font-medium">{health.workerQueueLength || 0}</p>
            </div>
            <div>
              <span className="text-theme-muted">Error Rate (24h)</span>
              <p className="font-medium">{health.errorRate24h || 0}%</p>
            </div>
          </div>
        </>
      ) : (
        <div className="text-center py-4 text-theme-muted">
          <Clock className="h-8 w-8 mx-auto mb-2 opacity-50" />
          <p>Loading health data...</p>
        </div>
      )}
    </CardContent>
  </Card>
);
