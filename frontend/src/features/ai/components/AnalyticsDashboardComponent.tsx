import React, { useState, useEffect, useCallback } from 'react';
import {
  AlertTriangle,
  RefreshCw,
  Download,
  Activity,
} from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { analyticsApi, CostAnalytics, Insight, Recommendation } from '@/shared/services/ai';
import { SystemHealthCard } from './SystemHealthCard';
import { CostMetricsPanel } from './CostMetricsPanel';
import { ProviderMetricsList } from './ProviderMetricsList';
import { InsightsPanel } from './InsightsPanel';

interface AnalyticsData {
  systemHealth: {
    overall_health: string;
    active_executions: number;
    total_providers: number;
    healthy_providers: number;
    recent_errors: number;
    system_load: number;
  };
  accountMetrics: {
    executions_today: number;
    successful_executions: number;
    failed_executions: number;
    active_conversations: number;
    total_tokens_used: number;
    estimated_cost: number;
  };
  providerMetrics: Array<{
    id: string;
    name: string;
    health_status: string;
    success_rate: number;
    avg_response_time: number;
    total_requests: number;
    cost_today: number;
  }>;
  topAgents: Array<{
    id: string;
    name: string;
    executions: number;
    success_rate: number;
    total_cost: number;
  }>;
}

export const AnalyticsDashboardComponent: React.FC = () => {
  const [loading, setLoadingSpinner] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [timeRange, setTimeRange] = useState('7d');
  const [selectedProvider, setSelectedProvider] = useState<string>('all');
  const [analyticsData, setAnalyticsData] = useState<AnalyticsData | null>(null);
  const [costAnalytics, setCostAnalytics] = useState<CostAnalytics | null>(null);
  const [insights, setInsights] = useState<Insight[]>([]);
  const [recommendations, setRecommendations] = useState<Recommendation[]>([]);
  const [realtimeUpdates, setRealtimeUpdates] = useState(true);
  const [exporting, setExporting] = useState(false);

  const { addNotification } = useNotifications();

  const loadAnalyticsData = useCallback(async (showSpinner = true) => {
    try {
      if (showSpinner) setLoadingSpinner(true);
      else setRefreshing(true);

      const filters = {
        time_range: timeRange as '24h' | '7d' | '30d' | '90d'
      };

      const [dashboard, overview, performance, costs, usage, insightsData, recommendationsData] = await Promise.all([
        analyticsApi.getDashboard(filters),
        analyticsApi.getOverview(filters),
        analyticsApi.getPerformance(filters),
        analyticsApi.getCosts(filters),
        analyticsApi.getUsage(filters),
        analyticsApi.getInsights(filters),
        analyticsApi.getRecommendations(filters)
      ]);

      setCostAnalytics(costs);
      setInsights(insightsData);
      setRecommendations(recommendationsData);

      const transformedData: AnalyticsData = {
        systemHealth: {
          overall_health: performance.error_rate < 0.05 ? 'healthy' : performance.error_rate < 0.15 ? 'degraded' : 'unhealthy',
          active_executions: overview.active_executions || 0,
          total_providers: overview.total_providers || 0,
          healthy_providers: overview.healthy_providers || 0,
          recent_errors: Math.floor((dashboard.overview.failed_executions / dashboard.overview.total_executions) * 100) || 0,
          system_load: Math.min(100, Math.floor(performance.throughput_per_hour / 10))
        },
        accountMetrics: {
          executions_today: dashboard.overview.total_executions,
          successful_executions: dashboard.overview.successful_executions,
          failed_executions: dashboard.overview.failed_executions,
          active_conversations: overview.active_conversations || 0,
          total_tokens_used: usage.total_tokens_used,
          estimated_cost: dashboard.overview.total_cost_usd
        },
        providerMetrics: overview.provider_metrics || [],
        topAgents: dashboard.top_agents.map(agent => ({
          id: agent.id,
          name: agent.name,
          executions: agent.execution_count,
          success_rate: agent.success_rate,
          total_cost: overview.agent_costs?.[agent.id] || 0
        }))
      };

      setAnalyticsData(transformedData);

    } catch (_error) {
      addNotification({
        type: 'error',
        title: 'Analytics Error',
        message: 'Failed to load analytics data. Please try again.'
      });
    } finally {
      setLoadingSpinner(false);
      setRefreshing(false);
    }
  }, [timeRange, addNotification]);

  const handleRefresh = useCallback(() => {
    loadAnalyticsData(false);
  }, []);

  const handleExportData = useCallback(async () => {
    try {
      setExporting(true);
      addNotification({
        type: 'info',
        title: 'Exporting Data',
        message: 'Preparing analytics report for download...'
      });

      const result = await analyticsApi.exportData({
        format: 'csv',
        data_type: 'dashboard',
        filters: {
          time_range: timeRange as '24h' | '7d' | '30d' | '90d'
        }
      });

      if (result.download_url) {
        window.open(result.download_url, '_blank');
        addNotification({
          type: 'success',
          title: 'Export Complete',
          message: 'Analytics report is ready for download'
        });
      }

    } catch (_error) {
      addNotification({
        type: 'error',
        title: 'Export Failed',
        message: 'Failed to export analytics data'
      });
    } finally {
      setExporting(false);
    }
  }, [addNotification, timeRange]);

  useEffect(() => {
    loadAnalyticsData();
  }, []);

  useEffect(() => {
    if (analyticsData) {
      loadAnalyticsData(false);
    }
  }, [timeRange, selectedProvider]);

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'AI', href: '/app/ai' },
    { label: 'Analytics' }
  ];

  const pageActions = [
    {
      id: 'realtime-toggle',
      label: 'Real-time',
      onClick: () => setRealtimeUpdates(!realtimeUpdates),
      variant: 'outline' as const,
      icon: Activity
    },
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: handleRefresh,
      variant: 'outline' as const,
      icon: RefreshCw,
      disabled: refreshing
    },
    {
      id: 'export',
      label: 'Export',
      onClick: handleExportData,
      variant: 'outline' as const,
      icon: Download,
      disabled: exporting
    }
  ];

  if (loading) {
    return (
      <PageContainer
        title="AI Analytics"
        description="Monitor AI system performance and usage metrics"
        breadcrumbs={breadcrumbs}
      >
        <LoadingSpinner className="py-12" />
      </PageContainer>
    );
  }

  if (!analyticsData) {
    return (
      <PageContainer
        title="AI Analytics"
        description="Monitor AI system performance and usage metrics"
        breadcrumbs={breadcrumbs}
      >
        <div className="text-center py-12">
          <AlertTriangle className="h-12 w-12 text-theme-warning mx-auto mb-4" />
          <h3 className="text-lg font-semibold mb-2">No Data Available</h3>
          <p className="text-theme-tertiary">Unable to load analytics data.</p>
        </div>
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title="AI Analytics"
      description="Monitor AI system performance and usage metrics"
      breadcrumbs={breadcrumbs}
      actions={pageActions}
    >
      <SystemHealthCard
        systemHealth={analyticsData.systemHealth}
        accountMetrics={analyticsData.accountMetrics}
        providerMetrics={analyticsData.providerMetrics}
        timeRange={timeRange}
        selectedProvider={selectedProvider}
        onTimeRangeChange={setTimeRange}
        onProviderChange={setSelectedProvider}
      />

      <ProviderMetricsList
        providerMetrics={analyticsData.providerMetrics}
        topAgents={analyticsData.topAgents}
      />

      {costAnalytics && (
        <CostMetricsPanel costAnalytics={costAnalytics} />
      )}

      <InsightsPanel
        insights={insights}
        recommendations={recommendations}
      />
    </PageContainer>
  );
};
