import React from 'react';
import { Activity, Zap, Clock, BarChart3, Bell } from 'lucide-react';
import type { DashboardStats } from '@/shared/hooks/useDashboardStats';
import { VerdictBadge } from '@/shared/components/ui/VerdictBadge';

interface DashboardAIOverviewProps {
  stats: DashboardStats;
  loading: boolean;
  /**
   * Set when the monitoring READ failed (M1 review F4). Distinct from a
   * `not_measured` verdict, which means the server answered and had no
   * measurement: a failed read renders "Could not load" with the reason, and
   * the figures are blanked rather than shown as zeros nobody measured.
   */
  monitoringError?: string | null;
}

const PLACEHOLDER = '—';

export const DashboardAIOverview: React.FC<DashboardAIOverviewProps> = ({ stats, loading, monitoringError = null }) => {
  const unavailable = !loading && monitoringError !== null;
  const figure = (value: string): string => (loading ? '...' : unavailable ? PLACEHOLDER : value);

  const quickStats = [
    {
      label: 'Executions Today',
      value: figure(stats.overview.totalExecutionsToday.toLocaleString()),
      icon: Zap,
    },
    {
      label: 'Success Rate',
      value: figure(`${stats.overview.successRate.toFixed(1)}%`),
      icon: BarChart3,
    },
    {
      label: 'Avg Response Time',
      value: figure(`${stats.overview.avgResponseTime.toFixed(0)}ms`),
      icon: Clock,
    },
    {
      label: 'Active Alerts',
      value: figure(stats.alerts.length.toString()),
      icon: Bell,
    },
  ];

  const recentAlerts = stats.alerts.slice(0, 3);

  const severityClasses: Record<string, string> = {
    critical: 'bg-theme-error-bg text-white',
    warning: 'bg-theme-warning-bg text-white',
    info: 'bg-theme-info-bg text-white',
  };

  return (
    <div className="card-theme-elevated p-6">
      <div className="flex items-center justify-between mb-5">
        <div className="flex items-center gap-3">
          <div className="p-2 rounded-lg">
            <Activity className="h-5 w-5 text-theme-tertiary" />
          </div>
          <div>
            <h3 className="text-lg font-semibold text-theme-primary">AI Platform Status</h3>
            <div className="flex items-center gap-2 mt-0.5">
              {/* The shared verdict rendering (E7 review M1). This used a
                  three-entry table and fell back to its HEALTHY entry for
                  any status it did not know, so a not-measured platform read
                  as healthy. VerdictBadge has no default branch. */}
              {loading ? (
                <span className="text-sm text-theme-tertiary">...</span>
              ) : unavailable ? (
                <span role="alert" className="text-sm text-theme-danger-fg">
                  Could not load: {monitoringError}
                </span>
              ) : (
                <VerdictBadge verdict={stats.systemHealth.status} size="sm" labelPrefix="AI platform" />
              )}
              {!loading && !unavailable && stats.systemHealth.score !== null && (
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

      {/* "All systems nominal" only on an OK verdict: a not-measured platform
          with no alerts has no alerts because nothing is looking. */}
      {!loading && !unavailable && recentAlerts.length === 0 && (
        <p className="text-sm text-theme-tertiary">
          {stats.systemHealth.status === 'ok' ? 'No active alerts — all systems nominal.' : 'No active alerts.'}
        </p>
      )}
    </div>
  );
};
