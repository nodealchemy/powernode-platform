import React, { useState, useEffect, useCallback } from 'react';
import {
  BarChart3,
  Clock,
  DollarSign,
  Lightbulb,
  RefreshCw,
  TrendingDown,
  TrendingUp,
  Zap,
  Target,
  PieChart,
  Users,
  Workflow
} from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Select } from '@/shared/components/ui/Select';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import {
  roiApi,
  RoiDashboard as DashboardData,
  RoiProjections,
  RoiRecommendation,
  PeriodComparison
} from '@/shared/services/ai';

type TimeRange = '7d' | '14d' | '30d' | '60d' | '90d' | '180d' | '365d';

export const RoiDashboard: React.FC = () => {
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [timeRange, setTimeRange] = useState<TimeRange>('30d');
  const [hourlyRate, setHourlyRate] = useState<number>(75);
  const [dashboardData, setDashboardData] = useState<DashboardData | null>(null);
  const [projections, setProjections] = useState<RoiProjections | null>(null);
  const [recommendations, setRecommendations] = useState<RoiRecommendation[]>([]);
  const [comparison, setComparison] = useState<PeriodComparison | null>(null);

  const { addNotification } = useNotifications();

  const loadData = useCallback(async (showSpinner = true) => {
    try {
      if (showSpinner) setLoading(true);
      else setRefreshing(true);

      const [dashboard, projectionsData, recommendationsData, comparisonData] = await Promise.all([
        roiApi.getDashboard(timeRange, hourlyRate),
        roiApi.getProjections(),
        roiApi.getRecommendations(),
        roiApi.compare()
      ]);

      setDashboardData(dashboard);
      setProjections(projectionsData);
      setRecommendations(recommendationsData);
      setComparison(comparisonData);

    } catch (error) {
      if (process.env.NODE_ENV === 'development') {
        console.error('Failed to load ROI data:', error);
      }
      addNotification({
        type: 'error',
        title: 'ROI Error',
        message: 'Failed to load ROI data. Please try again.'
      });
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [timeRange, hourlyRate, addNotification]);

  const handleRefresh = useCallback(() => {
    loadData(false);
  }, [loadData]);

  // Initial load
  useEffect(() => {
    loadData();
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  // Reload when filters change
  useEffect(() => {
    if (dashboardData) {
      loadData(false);
    }
  }, [timeRange, hourlyRate]); // eslint-disable-line react-hooks/exhaustive-deps

  const formatCurrency = (amount: number) => {
    if (amount >= 1000000) return `$${(amount / 1000000).toFixed(1)}M`;
    if (amount >= 1000) return `$${(amount / 1000).toFixed(1)}K`;
    return `$${amount.toFixed(2)}`;
  };

  const formatHours = (hours: number) => {
    if (hours >= 1000) return `${(hours / 1000).toFixed(1)}K hrs`;
    return `${hours.toFixed(1)} hrs`;
  };

  const getRoiBadge = (roi: number) => {
    if (roi >= 500) return <Badge variant="success" size="sm">Excellent</Badge>;
    if (roi >= 200) return <Badge variant="success" size="sm">Good</Badge>;
    if (roi >= 100) return <Badge variant="info" size="sm">Positive</Badge>;
    if (roi >= 0) return <Badge variant="warning" size="sm">Break-even</Badge>;
    return <Badge variant="danger" size="sm">Negative</Badge>;
  };

  const getTrendIcon = (direction: string) => {
    switch (direction) {
      case 'improving':
      case 'increasing':
        return <TrendingUp className="h-4 w-4 text-theme-success" />;
      case 'declining':
      case 'decreasing':
        return <TrendingDown className="h-4 w-4 text-theme-error" />;
      default:
        return <BarChart3 className="h-4 w-4 text-theme-muted" />;
    }
  };

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'AI', href: '/app/ai' },
    { label: 'ROI Analytics' }
  ];

  const pageActions = [
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: handleRefresh,
      variant: 'outline' as const,
      icon: RefreshCw,
      disabled: refreshing
    }
  ];

  if (loading) {
    return (
      <PageContainer
        title="ROI Analytics"
        description="Track the business value and ROI of your AI investments"
        breadcrumbs={breadcrumbs}
      >
        <LoadingSpinner className="py-12" />
      </PageContainer>
    );
  }

  if (!dashboardData) {
    return (
      <PageContainer
        title="ROI Analytics"
        description="Track the business value and ROI of your AI investments"
        breadcrumbs={breadcrumbs}
      >
        <div className="text-center py-12">
          <Target className="h-12 w-12 text-theme-warning mx-auto mb-4" />
          <h3 className="text-lg font-semibold mb-2">No Data Available</h3>
          <p className="text-theme-tertiary">Start using AI features to see ROI analytics.</p>
        </div>
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title="ROI Analytics"
      description="Track the business value and ROI of your AI investments"
      breadcrumbs={breadcrumbs}
      actions={pageActions}
    >
      {/* Controls */}
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-4">
          <Select
            value={timeRange}
            onValueChange={(val) => setTimeRange(val as TimeRange)}
            options={[
              { value: '7d', label: 'Last 7 days' },
              { value: '14d', label: 'Last 14 days' },
              { value: '30d', label: 'Last 30 days' },
              { value: '60d', label: 'Last 60 days' },
              { value: '90d', label: 'Last 90 days' },
              { value: '180d', label: 'Last 6 months' },
              { value: '365d', label: 'Last year' }
            ]}
          />

          <Select
            value={String(hourlyRate)}
            onValueChange={(val) => setHourlyRate(Number(val))}
            options={[
              { value: '50', label: '$50/hr rate' },
              { value: '75', label: '$75/hr rate' },
              { value: '100', label: '$100/hr rate' },
              { value: '150', label: '$150/hr rate' },
              { value: '200', label: '$200/hr rate' }
            ]}
          />
        </div>

        <div className="flex items-center gap-2">
          {getRoiBadge(dashboardData.summary.roi_percentage)}
          <span className="text-sm text-theme-tertiary">Overall ROI</span>
        </div>
      </div>

      {/* Main ROI Card */}
      <Card className="p-6 mb-6 bg-gradient-to-r from-theme-surface to-theme-background">
        <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
          <div className="text-center">
            <p className="text-sm text-theme-tertiary mb-1">ROI</p>
            <p className={`text-4xl font-bold ${
              dashboardData.summary.roi_percentage >= 100 ? 'text-theme-success' :
              dashboardData.summary.roi_percentage >= 0 ? 'text-theme-warning' : 'text-theme-error'
            }`}>
              {dashboardData.summary.roi_percentage.toFixed(0)}%
            </p>
          </div>
          <div className="text-center">
            <p className="text-sm text-theme-tertiary mb-1">Value Generated</p>
            <p className="text-4xl font-bold text-theme-success">
              {formatCurrency(dashboardData.summary.total_value_generated_usd)}
            </p>
          </div>
          <div className="text-center">
            <p className="text-sm text-theme-tertiary mb-1">AI Cost</p>
            <p className="text-4xl font-bold text-theme-primary">
              {formatCurrency(dashboardData.summary.total_ai_cost_usd)}
            </p>
          </div>
          <div className="text-center">
            <p className="text-sm text-theme-tertiary mb-1">Time Saved</p>
            <p className="text-4xl font-bold text-theme-info">
              {formatHours(dashboardData.summary.total_time_saved_hours)}
            </p>
          </div>
        </div>
      </Card>

      {/* Summary Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <Card className="p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-theme-tertiary">Tasks Completed</p>
              <p className="text-2xl font-semibold text-theme-primary">
                {dashboardData.summary.tasks_completed.toLocaleString()}
              </p>
            </div>
            <Target className="h-8 w-8 text-theme-info" />
          </div>
        </Card>

        <Card className="p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-theme-tertiary">Cost per Task</p>
              <p className="text-2xl font-semibold text-theme-primary">
                ${dashboardData.summary.cost_per_task.toFixed(3)}
              </p>
            </div>
            <DollarSign className="h-8 w-8 text-theme-success" />
          </div>
        </Card>

        <Card className="p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-theme-tertiary">Avg Time Saved/Task</p>
              <p className="text-2xl font-semibold text-theme-primary">
                {(dashboardData.efficiency.avg_time_saved_per_task_hours * 60).toFixed(0)} min
              </p>
            </div>
            <Clock className="h-8 w-8 text-theme-warning" />
          </div>
        </Card>

        <Card className="p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-theme-tertiary">Automation Rate</p>
              <p className="text-2xl font-semibold text-theme-primary">
                {(dashboardData.efficiency.automation_rate * 100).toFixed(0)}%
              </p>
            </div>
            <Zap className="h-8 w-8 text-theme-info" />
          </div>
        </Card>
      </div>

      {/* Period Comparison & Projections */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
        {/* Period Comparison */}
        {comparison && (
          <Card className="p-6">
            <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
              <BarChart3 className="h-5 w-5" />
              Period Comparison
            </h3>
            <div className="space-y-4">
              <div className="grid grid-cols-3 gap-4 text-center">
                <div>
                  <p className="text-xs text-theme-tertiary">Metric</p>
                </div>
                <div>
                  <p className="text-xs text-theme-tertiary">Current</p>
                </div>
                <div>
                  <p className="text-xs text-theme-tertiary">Change</p>
                </div>
              </div>

              <div className="grid grid-cols-3 gap-4 p-3 bg-theme-surface rounded-lg">
                <p className="text-sm font-medium text-theme-primary">ROI</p>
                <p className="text-sm text-center">{comparison.current_period.roi_percentage.toFixed(0)}%</p>
                <div className="flex items-center justify-center gap-1">
                  {comparison.changes.roi_change_points >= 0 ? (
                    <TrendingUp className="h-3 w-3 text-theme-success" />
                  ) : (
                    <TrendingDown className="h-3 w-3 text-theme-error" />
                  )}
                  <span className={comparison.changes.roi_change_points >= 0 ? 'text-theme-success' : 'text-theme-error'}>
                    {comparison.changes.roi_change_points >= 0 ? '+' : ''}{comparison.changes.roi_change_points.toFixed(1)} pts
                  </span>
                </div>
              </div>

              <div className="grid grid-cols-3 gap-4 p-3 bg-theme-surface rounded-lg">
                <p className="text-sm font-medium text-theme-primary">Value</p>
                <p className="text-sm text-center">{formatCurrency(comparison.current_period.value_usd)}</p>
                <div className="flex items-center justify-center gap-1">
                  {comparison.changes.value_change_percentage >= 0 ? (
                    <TrendingUp className="h-3 w-3 text-theme-success" />
                  ) : (
                    <TrendingDown className="h-3 w-3 text-theme-error" />
                  )}
                  <span className={comparison.changes.value_change_percentage >= 0 ? 'text-theme-success' : 'text-theme-error'}>
                    {comparison.changes.value_change_percentage >= 0 ? '+' : ''}{comparison.changes.value_change_percentage.toFixed(1)}%
                  </span>
                </div>
              </div>

              <div className="grid grid-cols-3 gap-4 p-3 bg-theme-surface rounded-lg">
                <p className="text-sm font-medium text-theme-primary">Cost</p>
                <p className="text-sm text-center">{formatCurrency(comparison.current_period.cost_usd)}</p>
                <div className="flex items-center justify-center gap-1">
                  {comparison.changes.cost_change_percentage <= 0 ? (
                    <TrendingDown className="h-3 w-3 text-theme-success" />
                  ) : (
                    <TrendingUp className="h-3 w-3 text-theme-error" />
                  )}
                  <span className={comparison.changes.cost_change_percentage <= 0 ? 'text-theme-success' : 'text-theme-error'}>
                    {comparison.changes.cost_change_percentage >= 0 ? '+' : ''}{comparison.changes.cost_change_percentage.toFixed(1)}%
                  </span>
                </div>
              </div>

              <div className="grid grid-cols-3 gap-4 p-3 bg-theme-surface rounded-lg">
                <p className="text-sm font-medium text-theme-primary">Time Saved</p>
                <p className="text-sm text-center">{formatHours(comparison.current_period.time_saved_hours)}</p>
                <div className="flex items-center justify-center gap-1">
                  {comparison.changes.time_saved_change_percentage >= 0 ? (
                    <TrendingUp className="h-3 w-3 text-theme-success" />
                  ) : (
                    <TrendingDown className="h-3 w-3 text-theme-error" />
                  )}
                  <span className={comparison.changes.time_saved_change_percentage >= 0 ? 'text-theme-success' : 'text-theme-error'}>
                    {comparison.changes.time_saved_change_percentage >= 0 ? '+' : ''}{comparison.changes.time_saved_change_percentage.toFixed(1)}%
                  </span>
                </div>
              </div>
            </div>
          </Card>
        )}

        {/* Projections */}
        {projections && (
          <Card className="p-6">
            <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
              <PieChart className="h-5 w-5" />
              Projections
            </h3>

            <div className="space-y-4">
              <div className="p-4 bg-theme-surface rounded-lg">
                <p className="text-sm text-theme-tertiary mb-2">Monthly Projection</p>
                <div className="grid grid-cols-3 gap-4">
                  <div>
                    <p className="text-xs text-theme-tertiary">Cost</p>
                    <p className="font-semibold">{formatCurrency(projections.monthly_projection.projected_cost_usd)}</p>
                  </div>
                  <div>
                    <p className="text-xs text-theme-tertiary">Value</p>
                    <p className="font-semibold text-theme-success">{formatCurrency(projections.monthly_projection.projected_value_usd)}</p>
                  </div>
                  <div>
                    <p className="text-xs text-theme-tertiary">ROI</p>
                    <p className="font-semibold">{projections.monthly_projection.projected_roi_percentage.toFixed(0)}%</p>
                  </div>
                </div>
                <div className="mt-2">
                  <Badge variant="outline" size="sm">
                    {(projections.monthly_projection.confidence * 100).toFixed(0)}% confidence
                  </Badge>
                </div>
              </div>

              <div className="p-4 bg-theme-surface rounded-lg">
                <p className="text-sm text-theme-tertiary mb-2">Quarterly Projection</p>
                <div className="grid grid-cols-3 gap-4">
                  <div>
                    <p className="text-xs text-theme-tertiary">Cost</p>
                    <p className="font-semibold">{formatCurrency(projections.quarterly_projection.projected_cost_usd)}</p>
                  </div>
                  <div>
                    <p className="text-xs text-theme-tertiary">Value</p>
                    <p className="font-semibold text-theme-success">{formatCurrency(projections.quarterly_projection.projected_value_usd)}</p>
                  </div>
                  <div>
                    <p className="text-xs text-theme-tertiary">ROI</p>
                    <p className="font-semibold">{projections.quarterly_projection.projected_roi_percentage.toFixed(0)}%</p>
                  </div>
                </div>
              </div>

              <div className="p-4 bg-theme-surface rounded-lg">
                <p className="text-sm text-theme-tertiary mb-2">Trend Analysis</p>
                <div className="grid grid-cols-3 gap-4">
                  <div className="flex items-center gap-2">
                    {getTrendIcon(projections.trend_analysis.cost_trend)}
                    <span className="text-sm">Cost</span>
                  </div>
                  <div className="flex items-center gap-2">
                    {getTrendIcon(projections.trend_analysis.value_trend)}
                    <span className="text-sm">Value</span>
                  </div>
                  <div className="flex items-center gap-2">
                    {getTrendIcon(projections.trend_analysis.roi_trend)}
                    <span className="text-sm">ROI</span>
                  </div>
                </div>
              </div>
            </div>
          </Card>
        )}
      </div>

      {/* Top Performers */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
        {/* Top Workflows */}
        <Card className="p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
            <Workflow className="h-5 w-5" />
            Top ROI Workflows
          </h3>
          <div className="space-y-3">
            {dashboardData.top_performers.workflows.map((workflow, index) => (
              <div key={workflow.id} className="flex items-center justify-between p-3 bg-theme-surface rounded-lg">
                <div className="flex items-center gap-3">
                  <div className={`w-6 h-6 rounded flex items-center justify-center text-white text-xs font-bold ${
                    index === 0 ? 'bg-theme-success' :
                    index === 1 ? 'bg-theme-info' : 'bg-theme-muted'
                  }`}>
                    {index + 1}
                  </div>
                  <div>
                    <p className="font-medium text-theme-primary">{workflow.name}</p>
                    <p className="text-xs text-theme-tertiary">
                      {formatCurrency(workflow.value_generated_usd)} generated
                    </p>
                  </div>
                </div>
                <div className="text-right">
                  <p className={`font-semibold ${
                    workflow.roi_percentage >= 200 ? 'text-theme-success' : 'text-theme-primary'
                  }`}>
                    {workflow.roi_percentage.toFixed(0)}% ROI
                  </p>
                </div>
              </div>
            ))}
          </div>
        </Card>

        {/* Top Agents */}
        <Card className="p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
            <Users className="h-5 w-5" />
            Top ROI Agents
          </h3>
          <div className="space-y-3">
            {dashboardData.top_performers.agents.map((agent, index) => (
              <div key={agent.id} className="flex items-center justify-between p-3 bg-theme-surface rounded-lg">
                <div className="flex items-center gap-3">
                  <div className={`w-6 h-6 rounded flex items-center justify-center text-white text-xs font-bold ${
                    index === 0 ? 'bg-theme-success' :
                    index === 1 ? 'bg-theme-info' : 'bg-theme-muted'
                  }`}>
                    {index + 1}
                  </div>
                  <div>
                    <p className="font-medium text-theme-primary">{agent.name}</p>
                    <p className="text-xs text-theme-tertiary">
                      {agent.tasks_completed} tasks completed
                    </p>
                  </div>
                </div>
                <div className="text-right">
                  <p className={`font-semibold ${
                    agent.roi_percentage >= 200 ? 'text-theme-success' : 'text-theme-primary'
                  }`}>
                    {agent.roi_percentage.toFixed(0)}% ROI
                  </p>
                </div>
              </div>
            ))}
          </div>
        </Card>
      </div>

      {/* Recommendations */}
      {recommendations.length > 0 && (
        <Card className="p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
            <Lightbulb className="h-5 w-5 text-theme-warning" />
            Optimization Recommendations
          </h3>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {recommendations.slice(0, 4).map((rec) => (
              <div key={rec.id} className="p-4 bg-theme-surface rounded-lg border border-theme">
                <div className="flex items-start justify-between mb-2">
                  <div>
                    <p className="font-medium text-theme-primary">{rec.title}</p>
                    <Badge
                      variant={rec.priority === 'high' ? 'danger' : rec.priority === 'medium' ? 'warning' : 'outline'}
                      size="sm"
                      className="mt-1"
                    >
                      {rec.priority} priority
                    </Badge>
                  </div>
                  <Badge variant="outline" size="sm">{rec.category}</Badge>
                </div>
                <p className="text-sm text-theme-secondary mt-2">{rec.description}</p>
                {(rec.potential_savings_usd || rec.potential_roi_improvement) && (
                  <div className="flex items-center gap-4 mt-3">
                    {rec.potential_savings_usd && (
                      <span className="text-xs text-theme-success flex items-center gap-1">
                        <DollarSign className="h-3 w-3" />
                        Save {formatCurrency(rec.potential_savings_usd)}
                      </span>
                    )}
                    {rec.potential_roi_improvement && (
                      <span className="text-xs text-theme-success flex items-center gap-1">
                        <TrendingUp className="h-3 w-3" />
                        +{rec.potential_roi_improvement}% ROI
                      </span>
                    )}
                  </div>
                )}
              </div>
            ))}
          </div>
        </Card>
      )}
    </PageContainer>
  );
};

export default RoiDashboard;
