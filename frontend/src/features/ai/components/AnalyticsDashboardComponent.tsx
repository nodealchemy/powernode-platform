import React, { useState, useEffect, useCallback } from 'react';
import {
  BarChart3,
  DollarSign,
  AlertTriangle,
  CheckCircle2,
  RefreshCw,
  Download,
  Activity,
  Lightbulb,
  TrendingUp,
  TrendingDown,
  Zap
} from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Select } from '@/shared/components/ui/Select';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { analyticsApi, CostAnalytics, Insight, Recommendation } from '@/shared/services/ai';

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

      // Fetch real analytics data from API
      const filters = {
        time_range: timeRange as '24h' | '7d' | '30d' | '90d'
      };

      // Fetch data in parallel for better performance
      const [dashboard, overview, performance, costs, usage, insightsData, recommendationsData] = await Promise.all([
        analyticsApi.getDashboard(filters),
        analyticsApi.getOverview(filters),
        analyticsApi.getPerformance(filters),
        analyticsApi.getCosts(filters),
        analyticsApi.getUsage(filters),
        analyticsApi.getInsights(filters),
        analyticsApi.getRecommendations(filters)
      ]);

      // Store cost analytics, insights, and recommendations
      setCostAnalytics(costs);
      setInsights(insightsData);
      setRecommendations(recommendationsData);

      // Transform API data to component format
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

    } catch {
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

      // Use real API to export data
      const result = await analyticsApi.exportData({
        format: 'csv',
        data_type: 'dashboard',
        filters: {
          time_range: timeRange as '24h' | '7d' | '30d' | '90d'
        }
      });

      // Open download URL in new tab
      if (result.download_url) {
        window.open(result.download_url, '_blank');
        addNotification({
          type: 'success',
          title: 'Export Complete',
          message: 'Analytics report is ready for download'
        });
      }

    } catch {
      addNotification({
        type: 'error',
        title: 'Export Failed',
        message: 'Failed to export analytics data'
      });
    } finally {
      setExporting(false);
    }
  }, [addNotification, timeRange]);

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

  // Initial load
  useEffect(() => {
    loadAnalyticsData();
  }, []);  
  
  // Reload when filters change
  useEffect(() => {
    if (analyticsData) { // Only reload if already loaded initially
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
      {/* Controls */}
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-4">
          <Select
            value={timeRange}
            onValueChange={setTimeRange}
            options={[
              { value: '1d', label: 'Last 24 hours' },
              { value: '7d', label: 'Last 7 days' },
              { value: '30d', label: 'Last 30 days' },
              { value: '90d', label: 'Last 90 days' }
            ]}
          />
          
          <Select
            value={selectedProvider}
            onValueChange={setSelectedProvider}
            options={[
              { value: 'all', label: 'All Providers' },
              ...(analyticsData.providerMetrics.map(p => ({
                value: p.id,
                label: p.name
              })))
            ]}
          />
        </div>
        
        <div className="flex items-center gap-2">
          {getHealthBadge(analyticsData.systemHealth.overall_health)}
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
                {analyticsData.systemHealth.active_executions}
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
                {analyticsData.accountMetrics.executions_today}
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
                  (analyticsData.accountMetrics.successful_executions / 
                   analyticsData.accountMetrics.executions_today) * 100
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
                ${analyticsData.accountMetrics.estimated_cost.toFixed(2)}
              </p>
            </div>
            <DollarSign className="h-5 w-5 text-theme-success" />
          </div>
        </Card>
      </div>

      {/* Provider Performance & Top Agents */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Provider Performance */}
        <Card className="p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-4">
            Provider Performance
          </h3>
          <div className="space-y-4">
            {analyticsData.providerMetrics.map((provider) => (
              <div key={provider.id} className="flex items-center justify-between p-3 bg-theme-surface rounded-lg">
                <div className="flex items-center gap-3">
                  <div className={`w-3 h-3 rounded-full ${
                    provider.health_status === 'healthy' ? 'bg-theme-success' : 'bg-theme-error'
                  }`} />
                  <div>
                    <p className="font-medium text-theme-primary">{provider.name}</p>
                    <p className="text-sm text-theme-tertiary">
                      {provider.total_requests} requests • {provider.avg_response_time}ms avg
                    </p>
                  </div>
                </div>
                
                <div className="text-right">
                  <p className="font-semibold text-theme-primary">
                    {provider.success_rate.toFixed(1)}%
                  </p>
                  <p className="text-sm text-theme-tertiary">
                    ${provider.cost_today.toFixed(2)}
                  </p>
                </div>
              </div>
            ))}
          </div>
        </Card>

        {/* Top Performing Agents */}
        <Card className="p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-4">
            Top Performing Agents
          </h3>
          <div className="space-y-4">
            {analyticsData.topAgents.map((agent, index) => (
              <div key={agent.id} className="flex items-center justify-between p-3 bg-theme-surface rounded-lg">
                <div className="flex items-center gap-3">
                  <div className="w-8 h-8 bg-theme-info rounded-full flex items-center justify-center text-white text-sm font-semibold">
                    {index + 1}
                  </div>
                  <div>
                    <p className="font-medium text-theme-primary">{agent.name}</p>
                    <p className="text-sm text-theme-tertiary">
                      {agent.executions} executions
                    </p>
                  </div>
                </div>

                <div className="text-right">
                  <p className="font-semibold text-theme-primary">
                    {agent.success_rate.toFixed(1)}%
                  </p>
                  <p className="text-sm text-theme-tertiary">
                    ${agent.total_cost.toFixed(2)}
                  </p>
                </div>
              </div>
            ))}
          </div>
        </Card>
      </div>

      {/* Cost Analytics Section */}
      {costAnalytics && (
        <div className="mt-6">
          <Card className="p-6">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-semibold text-theme-primary">
                Cost Analytics
              </h3>
              {costAnalytics.optimization_potential_usd > 0 && (
                <Badge variant="success" size="sm">
                  <Zap className="h-3 w-3 mr-1" />
                  ${costAnalytics.optimization_potential_usd.toFixed(2)} savings potential
                </Badge>
              )}
            </div>

            <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
              <div className="p-4 bg-theme-surface rounded-lg">
                <p className="text-sm text-theme-tertiary">Total Cost</p>
                <p className="text-2xl font-semibold text-theme-primary">
                  ${costAnalytics.total_cost_usd.toFixed(2)}
                </p>
              </div>

              <div className="p-4 bg-theme-surface rounded-lg">
                <p className="text-sm text-theme-tertiary">Cost by Provider</p>
                <div className="mt-2 space-y-1">
                  {Object.entries(costAnalytics.cost_by_provider).slice(0, 3).map(([provider, cost]) => (
                    <div key={provider} className="flex justify-between text-sm">
                      <span className="text-theme-secondary">{provider}</span>
                      <span className="font-medium text-theme-primary">${(cost as number).toFixed(2)}</span>
                    </div>
                  ))}
                </div>
              </div>

              <div className="p-4 bg-theme-surface rounded-lg">
                <p className="text-sm text-theme-tertiary">Top Expensive Workflows</p>
                <div className="mt-2 space-y-1">
                  {costAnalytics.top_expensive_workflows.slice(0, 3).map((workflow) => (
                    <div key={workflow.id} className="flex justify-between text-sm">
                      <span className="text-theme-secondary truncate max-w-[120px]">{workflow.name}</span>
                      <span className="font-medium text-theme-primary">${workflow.total_cost_usd.toFixed(2)}</span>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          </Card>
        </div>
      )}

      {/* Insights & Recommendations Section */}
      {(insights.length > 0 || recommendations.length > 0) && (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mt-6">
          {/* Insights */}
          {insights.length > 0 && (
            <Card className="p-6">
              <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
                <Lightbulb className="h-5 w-5 text-theme-warning" />
                Insights
              </h3>
              <div className="space-y-3">
                {insights.slice(0, 5).map((insight, index) => (
                  <div
                    key={index}
                    className={`p-3 rounded-lg border ${
                      insight.severity === 'critical'
                        ? 'bg-theme-error-background border-theme-error'
                        : insight.severity === 'warning'
                        ? 'bg-theme-warning-background border-theme-warning'
                        : 'bg-theme-surface border-theme'
                    }`}
                  >
                    <div className="flex items-start gap-2">
                      {insight.severity === 'critical' && <AlertTriangle className="h-4 w-4 text-theme-error mt-0.5" />}
                      {insight.severity === 'warning' && <AlertTriangle className="h-4 w-4 text-theme-warning mt-0.5" />}
                      <div>
                        <p className="font-medium text-theme-primary">{insight.title}</p>
                        <p className="text-sm text-theme-tertiary mt-1">{insight.description}</p>
                        {insight.impact && (
                          <p className="text-xs text-theme-tertiary mt-1">Impact: {insight.impact}</p>
                        )}
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </Card>
          )}

          {/* Recommendations */}
          {recommendations.length > 0 && (
            <Card className="p-6">
              <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
                <Zap className="h-5 w-5 text-theme-success" />
                Recommendations
              </h3>
              <div className="space-y-3">
                {recommendations.slice(0, 5).map((rec) => (
                  <div key={rec.id} className="p-3 bg-theme-surface rounded-lg">
                    <div className="flex items-start justify-between">
                      <div className="flex-1">
                        <div className="flex items-center gap-2">
                          <p className="font-medium text-theme-primary">{rec.title}</p>
                          <Badge
                            variant={rec.priority === 'high' ? 'danger' : rec.priority === 'medium' ? 'warning' : 'outline'}
                            size="sm"
                          >
                            {rec.priority}
                          </Badge>
                        </div>
                        <p className="text-sm text-theme-tertiary mt-1">{rec.description}</p>
                        {(rec.potential_savings_usd || rec.potential_improvement_percentage) && (
                          <div className="flex items-center gap-3 mt-2">
                            {rec.potential_savings_usd && (
                              <span className="text-xs text-theme-success flex items-center gap-1">
                                <TrendingDown className="h-3 w-3" />
                                Save ${rec.potential_savings_usd.toFixed(2)}
                              </span>
                            )}
                            {rec.potential_improvement_percentage && (
                              <span className="text-xs text-theme-success flex items-center gap-1">
                                <TrendingUp className="h-3 w-3" />
                                +{rec.potential_improvement_percentage}% improvement
                              </span>
                            )}
                          </div>
                        )}
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </Card>
          )}
        </div>
      )}

    </PageContainer>
  );
};