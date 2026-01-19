import React from 'react';
import { Bell, Settings, Users, Zap, BarChart3 } from 'lucide-react';
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

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-5 gap-4">
      <Card>
        <CardContent className="p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-theme-muted">Active Providers</p>
              <p className="text-2xl font-bold text-theme-primary">
                {dashboardData.overview.total_providers}
              </p>
            </div>
            <Settings className="h-8 w-8 text-theme-info" />
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardContent className="p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-theme-muted">AI Agents</p>
              <p className="text-2xl font-bold text-theme-primary">
                {dashboardData.overview.total_agents}
              </p>
            </div>
            <Users className="h-8 w-8 text-theme-success" />
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardContent className="p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-theme-muted">Active Workflows</p>
              <p className="text-2xl font-bold text-theme-primary">
                {dashboardData.overview.total_workflows}
              </p>
            </div>
            <Zap className="h-8 w-8 text-theme-primary" />
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardContent className="p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-theme-muted">Conversations</p>
              <p className="text-2xl font-bold text-theme-primary">
                {dashboardData.overview.active_conversations}
              </p>
            </div>
            <BarChart3 className="h-8 w-8 text-theme-warning" />
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardContent className="p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-theme-muted">Active Alerts</p>
              <p className="text-2xl font-bold text-theme-primary">
                {alerts.filter(a => !a.resolved).length}
              </p>
            </div>
            <Bell className="h-8 w-8 text-theme-error" />
          </div>
        </CardContent>
      </Card>
    </div>
  );
};
