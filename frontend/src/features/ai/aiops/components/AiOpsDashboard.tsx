import React, { useState, useEffect, useCallback } from 'react';
import {
  Activity,
  AlertTriangle,
  BarChart3,
  CheckCircle2,
  Clock,
  DollarSign,
  RefreshCw,
  Server,
  TrendingDown,
  TrendingUp,
  Zap,
  XCircle
} from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Select } from '@/shared/components/ui/Select';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { aiOpsApi, AiOpsDashboard as DashboardData, SystemHealth, RealTimeMetrics } from '@/shared/services/ai';

type TimeRange = '5m' | '15m' | '30m' | '1h' | '6h' | '24h' | '7d';

/** Embeddable AIOps content for use inside tabs (no PageContainer wrapper) */
export const AiOpsContent: React.FC = () => {
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [timeRange, setTimeRange] = useState<TimeRange>('1h');
  const [dashboardData, setDashboardData] = useState<DashboardData | null>(null);
  const [healthData, setHealthData] = useState<SystemHealth | null>(null);
  const [realTimeData, setRealTimeData] = useState<RealTimeMetrics | null>(null);
  const [autoRefresh, setAutoRefresh] = useState(true);

  const { addNotification } = useNotifications();

  const loadData = useCallback(async (showSpinner = true) => {
    try {
      if (showSpinner) setLoading(true);
      else setRefreshing(true);

      const [dashboard, health, realTime] = await Promise.all([
        aiOpsApi.getDashboard(timeRange),
        aiOpsApi.getHealth(),
        aiOpsApi.getRealTimeMetrics()
      ]);

      setDashboardData(dashboard);
      setHealthData(health);
      setRealTimeData(realTime);
    } catch (_error) {
      addNotification({
        type: 'error',
        title: 'AIOps Error',
        message: 'Failed to load operations data. Please try again.'
      });
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [timeRange, addNotification]);

  useEffect(() => { loadData(); }, []);  // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => { if (dashboardData) loadData(false); }, [timeRange]);  // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => {
    if (!autoRefresh) return;
    const interval = setInterval(() => loadData(false), 30000);
    return () => clearInterval(interval);
  }, [autoRefresh, loadData]);

  if (loading) return <LoadingSpinner className="py-12" message="Loading operations data..." />;
  if (!dashboardData) {
    return (
      <div className="text-center py-12">
        <AlertTriangle className="h-12 w-12 text-theme-warning mx-auto mb-4" />
        <h3 className="text-lg font-semibold mb-2">No Data Available</h3>
        <p className="text-theme-tertiary">Unable to load operations data.</p>
      </div>
    );
  }

  return (
    <AiOpsInnerContent
      dashboardData={dashboardData}
      healthData={healthData}
      realTimeData={realTimeData}
      timeRange={timeRange}
      setTimeRange={setTimeRange}
      autoRefresh={autoRefresh}
      setAutoRefresh={setAutoRefresh}
      refreshing={refreshing}
      onRefresh={() => loadData(false)}
    />
  );
};

// ---- Shared inner content used by both standalone page and embeddable component ----

interface AiOpsInnerContentProps {
  dashboardData: DashboardData;
  healthData: SystemHealth | null;
  realTimeData: RealTimeMetrics | null;
  timeRange: TimeRange;
  setTimeRange: (tr: TimeRange) => void;
  autoRefresh: boolean;
  setAutoRefresh: (v: boolean) => void;
  refreshing: boolean;
  onRefresh: () => void;
}

const getHealthBadge = (status: string) => {
  switch (status) {
    case 'healthy': return <Badge variant="success" size="sm">Healthy</Badge>;
    case 'degraded': return <Badge variant="warning" size="sm">Degraded</Badge>;
    case 'critical': return <Badge variant="danger" size="sm">Critical</Badge>;
    default: return <Badge variant="outline" size="sm">Unknown</Badge>;
  }
};

const getStatusIcon = (status: string) => {
  switch (status) {
    case 'healthy': return <CheckCircle2 className="h-4 w-4 text-theme-success" />;
    case 'degraded': return <AlertTriangle className="h-4 w-4 text-theme-warning" />;
    case 'critical': return <XCircle className="h-4 w-4 text-theme-error" />;
    default: return <Clock className="h-4 w-4 text-theme-muted" />;
  }
};

const formatNumber = (num: number) => {
  if (num >= 1000000) return `${(num / 1000000).toFixed(1)}M`;
  if (num >= 1000) return `${(num / 1000).toFixed(1)}K`;
  return num.toString();
};

const AiOpsInnerContent: React.FC<AiOpsInnerContentProps> = ({
  dashboardData, healthData, realTimeData, timeRange, setTimeRange,
  autoRefresh, setAutoRefresh, refreshing, onRefresh
}) => (
  <div className="space-y-6">
    {/* Controls */}
    <div className="flex items-center justify-between">
      <div className="flex items-center gap-4">
        <Select
          value={timeRange}
          onValueChange={(val) => setTimeRange(val as TimeRange)}
          options={[
            { value: '5m', label: 'Last 5 minutes' },
            { value: '15m', label: 'Last 15 minutes' },
            { value: '30m', label: 'Last 30 minutes' },
            { value: '1h', label: 'Last 1 hour' },
            { value: '6h', label: 'Last 6 hours' },
            { value: '24h', label: 'Last 24 hours' },
            { value: '7d', label: 'Last 7 days' }
          ]}
        />
        <button
          onClick={() => setAutoRefresh(!autoRefresh)}
          className="text-xs text-theme-secondary hover:text-theme-primary"
        >
          Auto-refresh: {autoRefresh ? 'On' : 'Off'}
        </button>
      </div>
      <div className="flex items-center gap-2">
        {healthData && getHealthBadge(healthData.status)}
        <button onClick={onRefresh} disabled={refreshing} className="text-theme-secondary hover:text-theme-primary">
          <RefreshCw className={`h-4 w-4 ${refreshing ? 'animate-spin' : ''}`} />
        </button>
      </div>
    </div>

    {/* Real-time Metrics Bar */}
    {realTimeData && (
      <div className="grid grid-cols-2 md:grid-cols-5 gap-4 p-4 bg-theme-surface rounded-lg border border-theme">
        <div className="text-center">
          <p className="text-xs text-theme-tertiary uppercase">Requests/sec</p>
          <p className="text-xl font-bold text-theme-primary">{realTimeData.current_requests_per_second.toFixed(1)}</p>
        </div>
        <div className="text-center">
          <p className="text-xs text-theme-tertiary uppercase">Avg Latency</p>
          <p className="text-xl font-bold text-theme-primary">{realTimeData.current_avg_latency_ms.toFixed(0)}ms</p>
        </div>
        <div className="text-center">
          <p className="text-xs text-theme-tertiary uppercase">Error Rate</p>
          <p className={`text-xl font-bold ${realTimeData.current_error_rate > 0.05 ? 'text-theme-error' : 'text-theme-success'}`}>
            {(realTimeData.current_error_rate * 100).toFixed(1)}%
          </p>
        </div>
        <div className="text-center">
          <p className="text-xs text-theme-tertiary uppercase">Queue Depth</p>
          <p className="text-xl font-bold text-theme-primary">{realTimeData.queue_depth}</p>
        </div>
        <div className="text-center">
          <p className="text-xs text-theme-tertiary uppercase">Connections</p>
          <p className="text-xl font-bold text-theme-primary">{realTimeData.active_connections}</p>
        </div>
      </div>
    )}

    {/* Summary Cards */}
    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
      <Card className="p-4">
        <div className="flex items-center justify-between">
          <div>
            <p className="text-sm text-theme-tertiary">Total Requests</p>
            <p className="text-2xl font-semibold text-theme-primary">{formatNumber(dashboardData.summary.total_requests)}</p>
            <p className="text-xs text-theme-tertiary mt-1">{dashboardData.summary.success_rate.toFixed(1)}% success</p>
          </div>
          <BarChart3 className="h-8 w-8 text-theme-info" />
        </div>
      </Card>
      <Card className="p-4">
        <div className="flex items-center justify-between">
          <div>
            <p className="text-sm text-theme-tertiary">Avg Latency</p>
            <p className="text-2xl font-semibold text-theme-primary">{dashboardData.summary.avg_latency_ms.toFixed(0)}ms</p>
            <p className="text-xs text-theme-tertiary mt-1">p95: {dashboardData.summary.p95_latency_ms.toFixed(0)}ms</p>
          </div>
          <Clock className="h-8 w-8 text-theme-warning" />
        </div>
      </Card>
      <Card className="p-4">
        <div className="flex items-center justify-between">
          <div>
            <p className="text-sm text-theme-tertiary">Total Cost</p>
            <p className="text-2xl font-semibold text-theme-primary">${dashboardData.summary.total_cost_usd.toFixed(2)}</p>
            <p className="text-xs text-theme-tertiary mt-1">This period</p>
          </div>
          <DollarSign className="h-8 w-8 text-theme-success" />
        </div>
      </Card>
      <Card className="p-4">
        <div className="flex items-center justify-between">
          <div>
            <p className="text-sm text-theme-tertiary">Failed Requests</p>
            <p className="text-2xl font-semibold text-theme-error">{formatNumber(dashboardData.summary.failed_requests)}</p>
            <p className="text-xs text-theme-tertiary mt-1">
              {dashboardData.summary.total_requests > 0
                ? ((dashboardData.summary.failed_requests / dashboardData.summary.total_requests) * 100).toFixed(1)
                : '0.0'}% error rate
            </p>
          </div>
          <AlertTriangle className="h-8 w-8 text-theme-error" />
        </div>
      </Card>
    </div>

    {/* Health & Providers Section */}
    <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
      {healthData && (
        <Card className="p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
            <Activity className="h-5 w-5" />
            System Health
          </h3>
          <div className="text-center mb-4">
            <div className={`text-4xl font-bold ${
              healthData.overall_score >= 90 ? 'text-theme-success' :
              healthData.overall_score >= 70 ? 'text-theme-warning' : 'text-theme-error'
            }`}>
              {healthData.overall_score.toFixed(0)}%
            </div>
            {getHealthBadge(healthData.status)}
          </div>
          <div className="space-y-3">
            {Object.entries(healthData.components).map(([name, component]) => (
              <div key={name} className="flex items-center justify-between p-3 bg-theme-surface rounded-lg">
                <div className="flex items-center gap-3">
                  {getStatusIcon(component.status)}
                  <div>
                    <p className="font-medium text-theme-primary capitalize">{name}</p>
                    <p className="text-xs text-theme-tertiary">{component.active_count} active</p>
                  </div>
                </div>
                <div className="text-right">
                  <p className={`font-medium ${
                    component.score >= 90 ? 'text-theme-success' :
                    component.score >= 70 ? 'text-theme-warning' : 'text-theme-error'
                  }`}>
                    {component.score.toFixed(0)}%
                  </p>
                  {component.error_count > 0 && (
                    <p className="text-xs text-theme-error">{component.error_count} errors</p>
                  )}
                </div>
              </div>
            ))}
          </div>
          <div className="mt-4 pt-4 border-t border-theme">
            <div className="flex items-center justify-between">
              <span className="text-sm text-theme-tertiary">Active Alerts</span>
              <div className="flex gap-2">
                {healthData.alerts_summary.critical > 0 && <Badge variant="danger" size="sm">{healthData.alerts_summary.critical} critical</Badge>}
                {healthData.alerts_summary.warning > 0 && <Badge variant="warning" size="sm">{healthData.alerts_summary.warning} warning</Badge>}
                {healthData.alerts_summary.info > 0 && <Badge variant="info" size="sm">{healthData.alerts_summary.info} info</Badge>}
              </div>
            </div>
          </div>
        </Card>
      )}

      <Card className="p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
          <Server className="h-5 w-5" />
          Top Providers
        </h3>
        <div className="space-y-3">
          {dashboardData.top_providers.length === 0 ? (
            <p className="text-sm text-theme-tertiary text-center py-4">No provider data available</p>
          ) : dashboardData.top_providers.map((provider) => (
            <div key={provider.id} className="flex items-center justify-between p-3 bg-theme-surface rounded-lg">
              <div className="flex items-center gap-3">
                <div className={`w-2 h-2 rounded-full ${
                  provider.success_rate >= 99 ? 'bg-theme-success' :
                  provider.success_rate >= 95 ? 'bg-theme-warning' : 'bg-theme-error'
                }`} />
                <div>
                  <p className="font-medium text-theme-primary">{provider.name}</p>
                  <p className="text-xs text-theme-tertiary">{formatNumber(provider.requests)} requests</p>
                </div>
              </div>
              <div className="text-right">
                <p className="font-medium text-theme-primary">{provider.success_rate.toFixed(1)}%</p>
                <p className="text-xs text-theme-tertiary">{provider.avg_latency_ms.toFixed(0)}ms avg</p>
              </div>
            </div>
          ))}
        </div>
      </Card>
    </div>

    {/* Workflows & Recent Errors */}
    <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
      <Card className="p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
          <Zap className="h-5 w-5" />
          Top Workflows
        </h3>
        <div className="space-y-3">
          {dashboardData.top_workflows.length === 0 ? (
            <p className="text-sm text-theme-tertiary text-center py-4">No workflow data available</p>
          ) : dashboardData.top_workflows.map((workflow, index) => (
            <div key={workflow.id} className="flex items-center justify-between p-3 bg-theme-surface rounded-lg">
              <div className="flex items-center gap-3">
                <div className="w-6 h-6 bg-theme-info rounded flex items-center justify-center text-white text-xs font-bold">{index + 1}</div>
                <div>
                  <p className="font-medium text-theme-primary">{workflow.name}</p>
                  <p className="text-xs text-theme-tertiary">{workflow.executions} executions</p>
                </div>
              </div>
              <div className="text-right">
                <div className="flex items-center gap-1">
                  {workflow.success_rate >= 95 ? <TrendingUp className="h-3 w-3 text-theme-success" /> : <TrendingDown className="h-3 w-3 text-theme-error" />}
                  <span className={`font-medium ${workflow.success_rate >= 95 ? 'text-theme-success' : 'text-theme-error'}`}>
                    {workflow.success_rate.toFixed(1)}%
                  </span>
                </div>
                <p className="text-xs text-theme-tertiary">{(workflow.avg_duration_ms / 1000).toFixed(1)}s avg</p>
              </div>
            </div>
          ))}
        </div>
      </Card>

      <Card className="p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
          <AlertTriangle className="h-5 w-5 text-theme-error" />
          Recent Errors
        </h3>
        {dashboardData.recent_errors.length === 0 ? (
          <div className="text-center py-8">
            <CheckCircle2 className="h-12 w-12 text-theme-success mx-auto mb-2" />
            <p className="text-theme-tertiary">No recent errors</p>
          </div>
        ) : (
          <div className="space-y-3">
            {dashboardData.recent_errors.slice(0, 5).map((error, index) => (
              <div key={index} className="p-3 bg-theme-error-background rounded-lg border border-theme-error">
                <div className="flex items-start justify-between">
                  <div>
                    <p className="font-medium text-theme-error">{error.error_type}</p>
                    <p className="text-sm text-theme-secondary mt-1">{error.message}</p>
                    <p className="text-xs text-theme-tertiary mt-1">{error.source_type}: {error.source_name}</p>
                  </div>
                  <span className="text-xs text-theme-tertiary whitespace-nowrap">
                    {new Date(error.timestamp).toLocaleTimeString()}
                  </span>
                </div>
              </div>
            ))}
          </div>
        )}
      </Card>
    </div>
  </div>
);

// ---- Standalone Page Component ----

export const AiOpsDashboard: React.FC = () => {
  return (
    <PageContainer
      title="AI Operations"
      description="Real-time monitoring and observability for AI workloads"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'AI', href: '/app/ai' },
        { label: 'AIOps' }
      ]}
    >
      <AiOpsContent />
    </PageContainer>
  );
};

export default AiOpsDashboard;
