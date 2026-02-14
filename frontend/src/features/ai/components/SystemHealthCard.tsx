import React from 'react';
import { Activity, BarChart3, CheckCircle2, DollarSign } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Select } from '@/shared/components/ui/Select';

interface SystemHealthData {
  overall_health: string;
  active_executions: number;
}

interface AccountMetricsData {
  executions_today: number;
  successful_executions: number;
  estimated_cost: number;
}

interface ProviderMetric {
  id: string;
  name: string;
}

interface SystemHealthCardProps {
  systemHealth: SystemHealthData;
  accountMetrics: AccountMetricsData;
  providerMetrics: ProviderMetric[];
  timeRange: string;
  selectedProvider: string;
  onTimeRangeChange: (value: string) => void;
  onProviderChange: (value: string) => void;
}

const getHealthBadge = (health: string) => {
  switch (health) {
    case 'healthy':
      return <Badge variant="success" size="sm">Healthy</Badge>;
    case 'degraded':
      return <Badge variant="warning" size="sm">Degraded</Badge>;
    case 'unhealthy':
      return <Badge variant="danger" size="sm">Unhealthy</Badge>;
    default:
      return <Badge variant="outline" size="sm">Unknown</Badge>;
  }
};

export const SystemHealthCard: React.FC<SystemHealthCardProps> = ({
  systemHealth,
  accountMetrics,
  providerMetrics,
  timeRange,
  selectedProvider,
  onTimeRangeChange,
  onProviderChange,
}) => {
  return (
    <>
      {/* Controls */}
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-4">
          <Select
            value={timeRange}
            onValueChange={onTimeRangeChange}
            options={[
              { value: '1d', label: 'Last 24 hours' },
              { value: '7d', label: 'Last 7 days' },
              { value: '30d', label: 'Last 30 days' },
              { value: '90d', label: 'Last 90 days' }
            ]}
          />

          <Select
            value={selectedProvider}
            onValueChange={onProviderChange}
            options={[
              { value: 'all', label: 'All Providers' },
              ...(providerMetrics.map(p => ({
                value: p.id,
                label: p.name
              })))
            ]}
          />
        </div>

        <div className="flex items-center gap-2">
          {getHealthBadge(systemHealth.overall_health)}
          <span className="text-sm text-theme-tertiary">
            System Health
          </span>
        </div>
      </div>

      {/* System Overview */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <Card className="p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-theme-tertiary">Active Executions</p>
              <p className="text-2xl font-semibold text-theme-primary">
                {systemHealth.active_executions}
              </p>
            </div>
            <Activity className="h-5 w-5 text-theme-info" />
          </div>
        </Card>

        <Card className="p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-theme-tertiary">Today's Executions</p>
              <p className="text-2xl font-semibold text-theme-primary">
                {accountMetrics.executions_today}
              </p>
            </div>
            <BarChart3 className="h-5 w-5 text-theme-info" />
          </div>
        </Card>

        <Card className="p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-theme-tertiary">Success Rate</p>
              <p className="text-2xl font-semibold text-theme-primary">
                {Math.round(
                  (accountMetrics.successful_executions /
                   accountMetrics.executions_today) * 100
                )}%
              </p>
            </div>
            <CheckCircle2 className="h-5 w-5 text-theme-success" />
          </div>
        </Card>

        <Card className="p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-theme-tertiary">Today's Cost</p>
              <p className="text-2xl font-semibold text-theme-primary">
                ${accountMetrics.estimated_cost.toFixed(2)}
              </p>
            </div>
            <DollarSign className="h-5 w-5 text-theme-success" />
          </div>
        </Card>
      </div>
    </>
  );
};
