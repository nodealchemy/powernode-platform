import React, { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import {
  TrendingUp,
  TrendingDown,
  BarChart3,
  Activity,
  Clock,
  CheckCircle,
  XCircle,
  AlertTriangle,
  Download
} from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Card, CardTitle, CardContent } from '@/shared/components/ui/Card';
import { Select } from '@/shared/components/ui/Select';
import { DateRangePicker } from '@/shared/components/ui/DateRangePicker';
import { workflowsApi, WorkflowStatistics } from '@/shared/services/ai';
import { useAuth } from '@/shared/hooks/useAuth';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import { WorkflowExecutionStats } from '@/shared/types/workflow';

interface AnalyticsData {
  statistics: WorkflowStatistics;
  executionMetrics: {
    metrics: WorkflowExecutionStats;
    period: {
      startDate: string;
      endDate: string;
      totalDays: number;
    };
  };
}

export const WorkflowAnalyticsPage: React.FC = () => {
  const { currentUser } = useAuth();
  const { addNotification } = useNotifications();

  // WebSocket for real-time updates
  usePageWebSocket({
    pageType: 'ai',
    onDataUpdate: () => {
      // Trigger data refresh if needed
    }
  });

  const [analyticsData, setAnalyticsData] = useState<AnalyticsData | null>(null);
  const [loading, setLoading] = useState(true);
  const [startDate, setStartDate] = useState(new Date(Date.now() - 30 * 24 * 60 * 60 * 1000));
  const [endDate, setEndDate] = useState(new Date());
  const [selectedPeriod, setSelectedPeriod] = useState('30');

  // Check permissions
  const canViewAnalytics = currentUser?.permissions?.includes('ai.analytics.read') || 
                          currentUser?.permissions?.includes('ai.workflows.read') ||
                          currentUser?.permissions?.includes('ai.workflows.manage') || false;

  // Memoize date strings to prevent unnecessary re-renders
  const dateStrings = useMemo(() => ({
    start: startDate.toISOString().split('T')[0],
    end: endDate.toISOString().split('T')[0]
  }), [startDate, endDate]);

  // Load analytics data - using useRef to avoid dependency issues
  const loadAnalyticsData = useRef<(() => Promise<void>) | undefined>(undefined);
  
  // Update the function reference when dates change
  loadAnalyticsData.current = async () => {
    try {
      setLoading(true);

      // Load statistics first
      let statisticsResponse;
      try {
        statisticsResponse = await workflowsApi.getWorkflowStatistics();
      } catch (_error) {
        console.error('Statistics API failed:', statsError);
        const errorMessage = statsError instanceof Error ? statsError.message : 'Unknown error';
        throw new Error(`Statistics API failed: ${errorMessage}`);
      }

      // Load metrics second
      let metricsResponse;
      try {
        metricsResponse = await workflowsApi.getExecutionMetrics(
          dateStrings.start,
          dateStrings.end
        );
      } catch (metricsError) {
        console.error('Metrics API failed:', metricsError);
        const errorMessage = metricsError instanceof Error ? metricsError.message : 'Unknown error';
        throw new Error(`Metrics API failed: ${errorMessage}`);
      }

      setAnalyticsData({
        statistics: statisticsResponse.statistics,
        executionMetrics: metricsResponse
      });
    } catch (error) {
      console.error('Failed to load analytics data:', error);
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      addNotification({
        type: 'error',
        title: 'Analytics Error',
        message: `Failed to load analytics data: ${errorMessage}`
      });
    } finally {
      setLoading(false);
    }
  };

  // Load data on mount and when date range changes
  useEffect(() => {
    if (canViewAnalytics && loadAnalyticsData.current) {
      loadAnalyticsData.current();
    }
  }, [canViewAnalytics, dateStrings.start, dateStrings.end]);

  // Handle period change
  const handlePeriodChange = useCallback((period: string) => {
    setSelectedPeriod(period);
    const days = parseInt(period);
    const newEndDate = new Date();
    const newStartDate = new Date(newEndDate.getTime() - days * 24 * 60 * 60 * 1000);
    
    setStartDate(newStartDate);
    setEndDate(newEndDate);
  }, []);

  // Format duration
  const formatDuration = (ms: number) => {
    if (ms < 1000) return `${ms}ms`;
    if (ms < 60000) return `${(ms / 1000).toFixed(1)}s`;
    return `${(ms / 60000).toFixed(1)}m`;
  };

  // Format percentage
  const formatPercentage = (value: number) => {
    return `${value.toFixed(1)}%`;
  };

  // Export analytics data - stable callback
  const handleExportData = useCallback(() => {
    if (!analyticsData) return;

    const exportData = {
      generated_at: new Date().toISOString(),
      period: {
        start: dateStrings.start,
        end: dateStrings.end
      },
      statistics: analyticsData?.statistics || {},
      execution_metrics: analyticsData?.executionMetrics?.metrics || {}
    };

    const blob = new Blob([JSON.stringify(exportData, null, 2)], {
      type: 'application/json'
    });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `workflow-analytics-${dateStrings.start}-to-${dateStrings.end}.json`;
    a.click();
    URL.revokeObjectURL(url);

    addNotification({
      type: 'success',
      title: 'Export Complete',
      message: 'Analytics data has been exported successfully.'
    });
  }, [analyticsData, dateStrings, addNotification]);

  if (!canViewAnalytics) {
    return (
      <PageContainer
        title="Access Denied"
        description="You don't have permission to view analytics"
      >
        <Card>
          <CardContent className="text-center py-8">
            <AlertTriangle className="h-12 w-12 text-theme-warning mx-auto mb-4" />
            <h3 className="text-lg font-medium mb-2">Access Denied</h3>
            <p className="text-theme-muted">
              You don't have permission to view workflow analytics.
            </p>
          </CardContent>
        </Card>
      </PageContainer>
    );
  }

  if (loading) {
    return (
      <PageContainer
        title="Workflow Analytics" 
        description="Loading analytics data..."
      >
        <div className="flex items-center justify-center py-12">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-theme-primary"></div>
          <span className="ml-2 text-theme-muted">Loading analytics data...</span>
        </div>
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title="Workflow Analytics"
      description="Performance insights and optimization recommendations for AI workflows"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'AI', href: '/app/ai' },
        { label: 'Analytics' }
      ]}
      actions={[
        {
          label: 'Export Data',
          onClick: handleExportData,
          icon: Download,
          variant: 'outline',
          disabled: !analyticsData
        }
      ]}
    >
      <div className="space-y-6">
        {/* Filters */}
        <div className="flex flex-col sm:flex-row gap-4">
          <div className="flex gap-2">
            <Select
              value={selectedPeriod}
              onChange={handlePeriodChange}
              options={[
                { value: '7', label: 'Last 7 days' },
                { value: '30', label: 'Last 30 days' },
                { value: '90', label: 'Last 90 days' },
                { value: '365', label: 'Last year' }
              ]}
              className="w-40"
            />
          </div>
          <div className="flex-1">
            <DateRangePicker
              startDate={startDate}
              endDate={endDate}
              onStartDateChange={(date) => date && setStartDate(date)}
              onEndDateChange={(date) => date && setEndDate(date)}
              onRangeChange={(range) => {
                setStartDate(range.startDate);
                setEndDate(range.endDate);
              }}
            />
          </div>
        </div>

        {loading ? (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
            {[...Array(8)].map((_, i) => (
              <Card key={i} className="animate-pulse">
                <CardContent className="p-4">
                  <div className="h-4 bg-theme-secondary rounded w-3/4 mb-2"></div>
                  <div className="h-6 bg-theme-secondary rounded w-1/2"></div>
                </CardContent>
              </Card>
            ))}
          </div>
        ) : analyticsData ? (
          <>
            {/* Overview Metrics */}
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
              <Card>
                <CardContent className="p-4">
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="text-sm text-theme-muted">Total Workflows</p>
                      <p className="text-2xl font-bold text-theme-primary">
                        {analyticsData?.statistics?.totalWorkflows || 0}
                      </p>
                    </div>
                    <BarChart3 className="h-8 w-8 text-theme-info" />
                  </div>
                </CardContent>
              </Card>

              <Card>
                <CardContent className="p-4">
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="text-sm text-theme-muted">Active Workflows</p>
                      <p className="text-2xl font-bold text-theme-primary">
                        {analyticsData?.statistics?.activeWorkflows || 0}
                      </p>
                    </div>
                    <Activity className="h-8 w-8 text-theme-success" />
                  </div>
                </CardContent>
              </Card>

              <Card>
                <CardContent className="p-4">
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="text-sm text-theme-muted">Total Executions</p>
                      <p className="text-2xl font-bold text-theme-primary">
                        {analyticsData?.executionMetrics?.metrics?.totalExecutions || 0}
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
                      <p className="text-sm text-theme-muted">Success Rate</p>
                      <p className="text-2xl font-bold text-theme-primary">
                        {formatPercentage(analyticsData?.executionMetrics?.metrics?.successRate || 0)}
                      </p>
                    </div>
                    <TrendingUp className="h-8 w-8 text-theme-success" />
                  </div>
                </CardContent>
              </Card>
            </div>

            {/* Performance Metrics */}
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
              <Card>
                <CardContent className="p-4">
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="text-sm text-theme-muted">Avg Execution Time</p>
                      <p className="text-2xl font-bold text-theme-primary">
                        {formatDuration(analyticsData?.executionMetrics?.metrics?.avgExecutionTime || 0)}
                      </p>
                    </div>
                    <Clock className="h-8 w-8 text-theme-info" />
                  </div>
                </CardContent>
              </Card>

              <Card>
                <CardContent className="p-4">
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="text-sm text-theme-muted">Failed Executions</p>
                      <p className="text-2xl font-bold text-theme-primary">
                        {analyticsData?.executionMetrics?.metrics?.failedExecutions || 0}
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
                      <p className="text-sm text-theme-muted">Min Execution Time</p>
                      <p className="text-2xl font-bold text-theme-primary">
                        {formatDuration(analyticsData?.executionMetrics?.metrics?.minExecutionTime || 0)}
                      </p>
                    </div>
                    <TrendingDown className="h-8 w-8 text-theme-success" />
                  </div>
                </CardContent>
              </Card>

              <Card>
                <CardContent className="p-4">
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="text-sm text-theme-muted">Max Execution Time</p>
                      <p className="text-2xl font-bold text-theme-primary">
                        {formatDuration(analyticsData?.executionMetrics?.metrics?.maxExecutionTime || 0)}
                      </p>
                    </div>
                    <TrendingUp className="h-8 w-8 text-theme-warning" />
                  </div>
                </CardContent>
              </Card>
            </div>

            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
              {/* Daily Executions Chart */}
              <Card>

                  <CardTitle className="flex items-center gap-2">
                    <BarChart3 className="h-5 w-5" />
                    Daily Executions
                  </CardTitle>

                <CardContent>
                  <div className="space-y-4">
                    {Object.entries(analyticsData?.executionMetrics?.metrics?.dailyExecutions || {}).map(([date, count]) => (
                      <div key={date} className="flex items-center justify-between">
                        <span className="text-sm text-theme-muted">
                          {new Date(date).toLocaleDateString()}
                        </span>
                        <span className="font-medium">{count}</span>
                      </div>
                    ))}
                  </div>
                </CardContent>
              </Card>

              {/* Most Active Users */}
              <Card>

                  <CardTitle className="flex items-center gap-2">
                    <Activity className="h-5 w-5" />
                    Most Active Users
                  </CardTitle>

                <CardContent>
                  <div className="space-y-4">
                    {Object.entries(analyticsData?.executionMetrics?.metrics?.mostActiveUsers || {}).map(([user, count]) => (
                      <div key={user} className="flex items-center justify-between">
                        <span className="text-sm text-theme-primary">{user}</span>
                        <span className="font-medium">{count} executions</span>
                      </div>
                    ))}
                  </div>
                </CardContent>
              </Card>
            </div>

            {/* Recommendations */}
            <Card>

                <CardTitle className="flex items-center gap-2">
                  <AlertTriangle className="h-5 w-5" />
                  Optimization Recommendations
                </CardTitle>

              <CardContent>
                <div className="space-y-4">
                  {(analyticsData?.executionMetrics?.metrics?.successRate || 0) < 90 && (
                    <div className="p-4 bg-theme-warning/10 border border-theme-warning/20 rounded-lg">
                      <h4 className="font-medium text-theme-warning mb-2">Low Success Rate</h4>
                      <p className="text-sm text-theme-warning">
                        Your workflows have a {formatPercentage(analyticsData?.executionMetrics?.metrics?.successRate || 0)} success rate. 
                        Consider reviewing failed executions and improving error handling.
                      </p>
                    </div>
                  )}

                  {(analyticsData?.executionMetrics?.metrics?.avgExecutionTime || 0) > 300000 && (
                    <div className="p-4 bg-theme-info/10 border border-theme-info/20 rounded-lg">
                      <h4 className="font-medium text-theme-info mb-2">High Execution Time</h4>
                      <p className="text-sm text-theme-info">
                        Average execution time is {formatDuration(analyticsData?.executionMetrics?.metrics?.avgExecutionTime || 0)}. 
                        Consider optimizing workflow logic or using parallel execution mode.
                      </p>
                    </div>
                  )}

                  {(analyticsData?.statistics?.draftWorkflows || 0) > (analyticsData?.statistics?.activeWorkflows || 0) && (
                    <div className="p-4 bg-theme-accent/10 border border-theme-accent/20 rounded-lg">
                      <h4 className="font-medium text-theme-accent mb-2">Many Draft Workflows</h4>
                      <p className="text-sm text-theme-accent">
                        You have {analyticsData?.statistics?.draftWorkflows || 0} draft workflows. 
                        Consider reviewing and publishing useful workflows.
                      </p>
                    </div>
                  )}

                  {(analyticsData?.executionMetrics?.metrics?.totalExecutions || 0) === 0 && (
                    <div className="p-4 bg-theme-surface border border-theme rounded-lg">
                      <h4 className="font-medium text-theme-primary mb-2">No Recent Executions</h4>
                      <p className="text-sm text-theme-tertiary">
                        No workflow executions found in the selected period.
                        Try expanding the date range or execute some workflows to see analytics.
                      </p>
                    </div>
                  )}
                </div>
              </CardContent>
            </Card>
          </>
        ) : (
          <Card>
            <CardContent className="text-center py-8">
              <BarChart3 className="h-12 w-12 text-theme-muted mx-auto mb-4 opacity-50" />
              <h3 className="text-lg font-medium mb-2">No Analytics Data</h3>
              <p className="text-theme-muted">
                No analytics data available for the selected period.
              </p>
            </CardContent>
          </Card>
        )}
      </div>
    </PageContainer>
  );
};