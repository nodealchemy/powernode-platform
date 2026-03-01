import React from 'react';
import { Play, Zap } from 'lucide-react';
import { Card, CardTitle, CardContent } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import type { AiWorkflowRun } from '@/shared/types/workflow';
import type { MonitoringDashboard } from '@/shared/services/ai/MonitoringApiService';

interface ActiveExecutionsListProps {
  activeExecutions: AiWorkflowRun[];
  workflowsList: MonitoringDashboard['workflowsList'];
}

export const ActiveExecutionsList: React.FC<ActiveExecutionsListProps> = ({
  activeExecutions,
  workflowsList
}) => (
  <>
    <Card>
      <CardTitle className="flex items-center gap-2 p-4 pb-0">
        <Play className="h-5 w-5" />
        Active Executions
      </CardTitle>
      <CardContent className="pt-4">
        {activeExecutions.length > 0 ? (
          <div className="space-y-4">
            {activeExecutions.map(execution => (
              <div key={execution.run_id} className="border border-theme-border rounded-lg p-4">
                <div className="flex items-center justify-between">
                  <div>
                    <h4 className="font-medium text-theme-primary">
                      Run ID: {execution.run_id}
                    </h4>
                    <p className="text-sm text-theme-muted">
                      Started: {execution.started_at ? new Date(execution.started_at).toLocaleTimeString() : 'N/A'}
                    </p>
                  </div>
                  <div className="flex items-center gap-2">
                    <Badge variant="outline" className="bg-theme-info/10 text-theme-info">
                      {execution.status}
                    </Badge>
                    <Badge variant="outline">
                      {execution.trigger_type}
                    </Badge>
                  </div>
                </div>
              </div>
            ))}
          </div>
        ) : (
          <div className="text-center py-8 text-theme-muted">
            <Play className="h-12 w-12 mx-auto mb-4 opacity-50" />
            <p>No active executions</p>
          </div>
        )}
      </CardContent>
    </Card>

    <Card>
      <CardTitle className="flex items-center gap-2 p-4 pb-0">
        <Zap className="h-5 w-5" />
        All Workflows ({workflowsList?.length ?? 0})
      </CardTitle>
      <CardContent className="pt-4">
        {workflowsList && workflowsList.length > 0 ? (
          <div className="space-y-3">
            {workflowsList.map(workflow => (
              <div key={workflow.id} className="border border-theme-border rounded-lg p-4">
                <div className="flex items-center justify-between">
                  <div>
                    <h4 className="font-medium text-theme-primary">{workflow.name}</h4>
                    <div className="flex items-center gap-4 mt-1 text-sm text-theme-muted">
                      <span>Runs: {workflow.total_runs || 0}</span>
                      <span className="text-theme-success">{'\u2713'} {workflow.successful_runs || 0}</span>
                      <span className="text-theme-danger">{'\u2717'} {workflow.failed_runs || 0}</span>
                    </div>
                  </div>
                  <div className="flex items-center gap-2">
                    <Badge variant={workflow.status === 'active' ? 'success' : 'outline'}>
                      {workflow.status}
                    </Badge>
                    {(workflow.success_rate ?? 0) > 0 && (
                      <Badge variant="outline">
                        {workflow.success_rate?.toFixed(0)}% success
                      </Badge>
                    )}
                  </div>
                </div>
              </div>
            ))}
          </div>
        ) : (
          <div className="text-center py-8 text-theme-muted">
            <Zap className="h-12 w-12 mx-auto mb-4 opacity-50" />
            <p>No workflows configured</p>
          </div>
        )}
      </CardContent>
    </Card>
  </>
);
