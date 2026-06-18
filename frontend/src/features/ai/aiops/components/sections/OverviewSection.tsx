import React from 'react';
import { Activity, BarChart3, CheckCircle2, Clock, DollarSign, Gauge, ShieldAlert, XCircle, Zap } from 'lucide-react';
import { MetricCard } from '@/shared/components/ui/Card';
import { EntityLink } from '@/shared/components/entity';
import type { AiOpsDashboard } from '@/shared/services/ai/AiOpsApiService';
import {
  formatNumber, formatCurrency, formatDuration, formatPercent,
  scoreColorClass, getHealthBadge, getStatusIcon, getSeverityBadge, formatTimestamp,
} from '../aiopsHelpers';
import { DashboardSection, AiOpsTimeRange } from './sectionShared';

/** Compact provider-health alerts callout (sourced from dashboard.alerts). */
const ActiveProviderAlerts: React.FC<{ alerts: AiOpsDashboard['alerts'] }> = ({ alerts }) => {
  const rows = alerts ?? [];
  return (
    <div className="bg-theme-surface border border-theme rounded-lg p-4">
      <h4 className="text-sm font-medium text-theme-primary mb-3 flex items-center gap-2">
        <ShieldAlert className="h-4 w-4" />
        Active Provider Alerts
      </h4>
      {rows.length === 0 ? (
        <div className="flex items-center gap-2 text-sm text-theme-secondary">
          <CheckCircle2 className="h-4 w-4 text-theme-success-fg" />
          No active provider alerts.
        </div>
      ) : (
        <div className="space-y-2">
          {rows.map((alert, idx) => (
            <div key={`${alert.provider_id}-${idx}`} className="flex items-start justify-between gap-3 py-1.5 border-b border-theme last:border-0">
              <div className="flex items-start gap-2">
                {getSeverityBadge(alert.severity)}
                <div>
                  <p className="text-sm text-theme-primary">{alert.message}</p>
                  {alert.provider_name && (
                    <p className="text-xs text-theme-tertiary">
                      <EntityLink type="ai_provider" id={alert.provider_id} label={alert.provider_name} />
                    </p>
                  )}
                </div>
              </div>
              <span className="text-xs text-theme-tertiary whitespace-nowrap">{formatTimestamp(alert.detected_at)}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
};

const OverviewBody: React.FC<{ dashboard: AiOpsDashboard }> = ({ dashboard }) => {
  const overview = dashboard.overview;
  const health = dashboard.health;
  const executions = overview?.executions;
  const performance = overview?.performance;
  const costs = overview?.costs;
  const latency = overview?.latency_aggregate;
  const components = health?.components;

  return (
    <div className="space-y-6">
      {/* Execution + performance + cost KPIs */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <MetricCard
          title="Total Executions"
          value={formatNumber(executions?.total ?? 0)}
          icon={<BarChart3 className="h-5 w-5 text-theme-info-fg" />}
          description={`${formatPercent(executions?.success_rate)} success`}
        />
        <MetricCard
          title="Successful"
          value={formatNumber(executions?.successful ?? 0)}
          icon={<CheckCircle2 className="h-5 w-5 text-theme-success-fg" />}
        />
        <MetricCard
          title="Failed"
          value={formatNumber(executions?.failed ?? 0)}
          icon={<XCircle className="h-5 w-5 text-theme-error-fg" />}
        />
        <MetricCard
          title="Success Rate"
          value={formatPercent(executions?.success_rate)}
          icon={<Gauge className="h-5 w-5 text-theme-success-fg" />}
        />
        <MetricCard
          title="Avg Duration"
          value={formatDuration(performance?.avg_execution_duration_ms)}
          icon={<Clock className="h-5 w-5 text-theme-warning-fg" />}
        />
        <MetricCard
          title="Throughput"
          value={`${formatNumber(performance?.throughput_per_minute ?? 0)}/min`}
          icon={<Zap className="h-5 w-5 text-theme-info-fg" />}
        />
        <MetricCard
          title="Total Cost"
          value={formatCurrency(costs?.total_execution_cost ?? 0)}
          icon={<DollarSign className="h-5 w-5 text-theme-success-fg" />}
        />
        <MetricCard
          title="Total Tokens"
          value={formatNumber(costs?.total_tokens ?? 0)}
          icon={<Activity className="h-5 w-5 text-theme-interactive-primary" />}
        />
      </div>

      {/* Optional aggregate latency percentiles */}
      {latency && (
        <div className="bg-theme-surface border border-theme rounded-lg p-4">
          <h4 className="text-sm font-medium text-theme-primary mb-3">Latency Percentiles</h4>
          <div className="grid grid-cols-2 md:grid-cols-5 gap-4">
            {([
              ['Average', latency.avg_ms],
              ['p95', latency.p95_ms],
              ['p99', latency.p99_ms],
              ['Max', latency.max_ms],
            ] as const).map(([label, value]) => (
              <div key={label} className="text-center">
                <p className="text-xs text-theme-tertiary uppercase">{label}</p>
                <p className="text-lg font-bold text-theme-primary">{formatDuration(value)}</p>
              </div>
            ))}
            <div className="text-center">
              <p className="text-xs text-theme-tertiary uppercase">Providers</p>
              <p className="text-lg font-bold text-theme-primary">{formatNumber(latency.sample_provider_count ?? 0)}</p>
            </div>
          </div>
        </div>
      )}

      {/* Active provider alerts (compact) */}
      <ActiveProviderAlerts alerts={dashboard.alerts ?? []} />

      {/* System health */}
      <div className="bg-theme-surface border border-theme rounded-lg p-6">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-semibold text-theme-primary flex items-center gap-2">
            <Activity className="h-5 w-5" />
            System Health
          </h3>
          {getHealthBadge(health?.status)}
        </div>

        <div className="flex flex-wrap items-baseline gap-x-6 gap-y-1 mb-4">
          <div>
            <span className={`text-4xl font-bold ${scoreColorClass(health?.overall_score)}`}>
              {Math.round(health?.overall_score ?? 0)}%
            </span>
            <span className="text-sm text-theme-tertiary ml-2">overall score</span>
          </div>
          <div className="text-sm text-theme-tertiary">
            Uptime <span className="font-medium text-theme-primary">{formatPercent(health?.uptime_percentage)}</span>
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
          {Object.entries(components ?? {}).map(([name, component]) => (
            <div key={name} className="p-3 bg-theme-background rounded-lg">
              <div className="flex items-center justify-between mb-1">
                <div className="flex items-center gap-2">
                  {getStatusIcon(component?.status)}
                  <span className="font-medium text-theme-primary capitalize">{name}</span>
                </div>
                <span className={`font-medium ${scoreColorClass(component?.score)}`}>
                  {Math.round(component?.score ?? 0)}%
                </span>
              </div>
              {(component?.issues ?? []).length > 0 ? (
                <ul className="mt-1 space-y-0.5">
                  {(component?.issues ?? []).map((issue, idx) => (
                    <li key={idx} className="text-xs text-theme-warning-fg truncate" title={issue}>• {issue}</li>
                  ))}
                </ul>
              ) : (
                <p className="text-xs text-theme-tertiary">No issues detected</p>
              )}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};

/** Standalone, self-fetching overview: KPIs + latency + provider-alert callout + system health. */
export const OverviewSection: React.FC<{ timeRange?: AiOpsTimeRange }> = ({ timeRange }) => (
  <DashboardSection timeRange={timeRange}>
    {(dashboard) => <OverviewBody dashboard={dashboard} />}
  </DashboardSection>
);

export default OverviewSection;
