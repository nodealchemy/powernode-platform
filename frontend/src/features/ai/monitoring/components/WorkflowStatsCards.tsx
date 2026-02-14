import React from 'react';
import { Zap, Play, CheckCircle, XCircle, DollarSign } from 'lucide-react';
import { Card, CardContent } from '@/shared/components/ui/Card';
import type { WorkflowMonitoringData } from '@/shared/types/workflow';

interface WorkflowStatsCardsProps {
  stats: WorkflowMonitoringData['stats'] | null;
  formatCurrency: (amount: number) => string;
}

export const WorkflowStatsCards: React.FC<WorkflowStatsCardsProps> = ({ stats, formatCurrency }) => (
  <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-5 gap-4">
    <Card>
      <CardContent className="p-4">
        <div className="flex items-center justify-between">
          <div>
            <p className="text-sm text-theme-muted">Active Workflows</p>
            <p className="text-2xl font-bold text-theme-primary">
              {stats?.activeWorkflows || 0}
            </p>
          </div>
          <Zap className="h-8 w-8 text-theme-info" />
        </div>
      </CardContent>
    </Card>

    <Card>
      <CardContent className="p-4">
        <div className="flex items-center justify-between">
          <div>
            <p className="text-sm text-theme-muted">Running Executions</p>
            <p className="text-2xl font-bold text-theme-primary">
              {stats?.runningExecutions || 0}
            </p>
          </div>
          <Play className="h-8 w-8 text-theme-success" />
        </div>
      </CardContent>
    </Card>

    <Card>
      <CardContent className="p-4">
        <div className="flex items-center justify-between">
          <div>
            <p className="text-sm text-theme-muted">Completed Today</p>
            <p className="text-2xl font-bold text-theme-primary">
              {stats?.completedToday || 0}
            </p>
          </div>
          <CheckCircle className="h-8 w-8 text-theme-success" />
        </div>
      </CardContent>
    </Card>

    <Card>
      <CardContent className="p-4">
        <div className="flex items-center justify-between">
          <div>
            <p className="text-sm text-theme-muted">Failed Today</p>
            <p className="text-2xl font-bold text-theme-primary">
              {stats?.failedToday || 0}
            </p>
          </div>
          <XCircle className="h-8 w-8 text-theme-danger" />
        </div>
      </CardContent>
    </Card>

    <Card>
      <CardContent className="p-4">
        <div className="flex items-center justify-between">
          <div>
            <p className="text-sm text-theme-muted">Cost Today</p>
            <p className="text-2xl font-bold text-theme-primary">
              {formatCurrency(stats?.totalCostToday || 0)}
            </p>
          </div>
          <DollarSign className="h-8 w-8 text-theme-warning" />
        </div>
      </CardContent>
    </Card>
  </div>
);
