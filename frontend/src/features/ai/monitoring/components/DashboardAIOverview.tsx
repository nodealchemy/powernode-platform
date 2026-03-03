import React from 'react';
import { Activity, CheckCircle, AlertTriangle, XCircle, Zap, Clock, BarChart3, Bell } from 'lucide-react';
import type { DashboardStats } from '@/shared/hooks/useDashboardStats';

interface DashboardAIOverviewProps {
  stats: DashboardStats;
  loading: boolean;
}

const healthConfig = {
  healthy: { icon: CheckCircle, color: 'text-theme-success', bg: 'bg-theme-success', label: 'Healthy' },
  degraded: { icon: AlertTriangle, color: 'text-theme-warning', bg: 'bg-theme-warning', label: 'Degraded' },
  down: { icon: XCircle, color: 'text-theme-error', bg: 'bg-theme-error', label: 'Down' },
} as const;

export const DashboardAIOverview: React.FC<DashboardAIOverviewProps> = ({ stats, loading }) => {
  const health = healthConfig[stats.systemHealth.status] || healthConfig.healthy;
  const HealthIcon = health.icon;

  const quickStats = [
    {
      label: 'Executions Today',
      value: loading ? '...' : stats.overview.totalExecutionsToday.toLocaleString(),
      icon: Zap,
    },
    {
      label: 'Success Rate',
      value: loading ? '...' : `${stats.overview.successRate.toFixed(1)}%`,
      icon: BarChart3,
    },
    {
      label: 'Avg Response Time',
      value: loading ? '...' : `${stats.overview.avgResponseTime.toFixed(0)}ms`,
      icon: Clock,
    },
    {
      label: 'Active Alerts',
      value: loading ? '...' : stats.alerts.length.toString(),
      icon: Bell,
    },
  ];

  const recentAlerts = stats.alerts.slice(0, 3);

  const severityClasses: Record<string, string> = {
    critical: 'bg-theme-error text-white',
    warning: 'bg-theme-warning text-white',
    info: 'bg-theme-info text-white',
  };

  return (
    <div className="card-theme-elevated p-6">
      <div className="flex items-center justify-between mb-5">
        <div className="flex items-center gap-3">
          <div className={`p-2 rounded-lg ${health.bg} bg-opacity-10`}>
            <Activity className={`h-5 w-5 ${health.color}`} />
          </div>
          <div>
            <h3 className="text-lg font-semibold text-theme-primary">AI Platform Status</h3>
            <div className="flex items-center gap-2 mt-0.5">
              <HealthIcon className={`h-4 w-4 ${health.color}`} />
              <span className={`text-sm font-medium ${health.color}`}>{health.label}</span>
              {!loading && (
                <span className="text-xs text-theme-tertiary ml-1">
                  ({stats.systemHealth.score}% health score)
                </span>
              )}
            </div>
          </div>
        </div>
      </div>

      {/* Quick Stats Grid */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-5">
        {quickStats.map((stat) => {
          const StatIcon = stat.icon;
          return (
            <div key={stat.label} className="bg-theme-surface rounded-lg p-3">
              <div className="flex items-center gap-2 mb-1">
                <StatIcon className="h-4 w-4 text-theme-tertiary" />
                <span className="text-xs text-theme-tertiary">{stat.label}</span>
              </div>
              <span className="text-lg font-semibold text-theme-primary">{stat.value}</span>
            </div>
          );
        })}
      </div>

      {/* Recent Alerts */}
      {recentAlerts.length > 0 && (
        <div>
          <h4 className="text-sm font-medium text-theme-secondary mb-2">Recent Alerts</h4>
          <div className="space-y-2">
            {recentAlerts.map((alert) => (
              <div
                key={alert.id}
                className="flex items-center gap-3 bg-theme-surface rounded-lg px-3 py-2"
              >
                <span
                  className={`text-[10px] font-bold uppercase px-1.5 py-0.5 rounded ${
                    severityClasses[alert.severity] || severityClasses.info
                  }`}
                >
                  {alert.severity}
                </span>
                <span className="text-sm text-theme-primary flex-1 truncate">{alert.message}</span>
                <span className="text-xs text-theme-tertiary whitespace-nowrap">
                  {new Date(alert.timestamp).toLocaleTimeString()}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}

      {!loading && recentAlerts.length === 0 && (
        <p className="text-sm text-theme-tertiary">No active alerts — all systems nominal.</p>
      )}
    </div>
  );
};
