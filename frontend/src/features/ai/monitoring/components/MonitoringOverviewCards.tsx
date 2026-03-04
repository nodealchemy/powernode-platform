import React from 'react';
import { Bell, Settings, Users, Zap, Clock, CheckCircle, DollarSign, Activity } from 'lucide-react';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { MonitoringDashboardData, Alert } from '@/shared/types/monitoring';

interface MonitoringOverviewCardsProps {
  dashboardData: MonitoringDashboardData | null;
  alerts: Alert[];
}

export const MonitoringOverviewCards: React.FC<MonitoringOverviewCardsProps> = ({
  dashboardData,
  alerts
}) => {
  if (!dashboardData) return null;

  const { overview } = dashboardData;

  return (
    <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-8 gap-3">
      <Card>
        <CardContent className="p-3">
          <div className="flex items-center gap-2">
            <Settings className="h-5 w-5 text-theme-info shrink-0" />
            <div className="min-w-0">
              <p className="text-xs text-theme-muted truncate">Providers</p>
              <p className="text-lg font-bold text-theme-primary">{overview.total_providers}</p>
            </div>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardContent className="p-3">
          <div className="flex items-center gap-2">
            <Users className="h-5 w-5 text-theme-success shrink-0" />
            <div className="min-w-0">
              <p className="text-xs text-theme-muted truncate">Agents</p>
              <p className="text-lg font-bold text-theme-primary">{overview.total_agents}</p>
            </div>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardContent className="p-3">
          <div className="flex items-center gap-2">
            <Zap className="h-5 w-5 text-theme-primary shrink-0" />
            <div className="min-w-0">
              <p className="text-xs text-theme-muted truncate">Workflows</p>
              <p className="text-lg font-bold text-theme-primary">{overview.total_workflows}</p>
            </div>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardContent className="p-3">
          <div className="flex items-center gap-2">
            <Activity className="h-5 w-5 text-theme-warning shrink-0" />
            <div className="min-w-0">
              <p className="text-xs text-theme-muted truncate">Executions Today</p>
              <p className="text-lg font-bold text-theme-primary">{overview.total_executions_today ?? 0}</p>
            </div>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardContent className="p-3">
          <div className="flex items-center gap-2">
            <CheckCircle className="h-5 w-5 text-theme-success shrink-0" />
            <div className="min-w-0">
              <p className="text-xs text-theme-muted truncate">Success Rate</p>
              <p className="text-lg font-bold text-theme-primary">{Number(overview.success_rate ?? 0).toFixed(1)}%</p>
            </div>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardContent className="p-3">
          <div className="flex items-center gap-2">
            <Clock className="h-5 w-5 text-theme-info shrink-0" />
            <div className="min-w-0">
              <p className="text-xs text-theme-muted truncate">Avg Response</p>
              <p className="text-lg font-bold text-theme-primary">{Number(overview.avg_response_time ?? 0).toFixed(0)}ms</p>
            </div>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardContent className="p-3">
          <div className="flex items-center gap-2">
            <DollarSign className="h-5 w-5 text-theme-success shrink-0" />
            <div className="min-w-0">
              <p className="text-xs text-theme-muted truncate">Cost Today</p>
              <p className="text-lg font-bold text-theme-primary">${Number(overview.total_cost_today ?? 0).toFixed(2)}</p>
            </div>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardContent className="p-3">
          <div className="flex items-center gap-2">
            <Bell className="h-5 w-5 text-theme-error shrink-0" />
            <div className="min-w-0">
              <p className="text-xs text-theme-muted truncate">Alerts</p>
              <p className="text-lg font-bold text-theme-primary">{alerts.filter(a => !a.resolved).length}</p>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  );
};
