import React, { useState, useEffect, useCallback } from 'react';
import {
  BarChart3,
  RefreshCw,
  TrendingDown,
  TrendingUp,
  Target,
} from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Select } from '@/shared/components/ui/Select';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import {
  roiApi,
  RoiDashboard as DashboardData,
  RoiProjections,
  RoiRecommendation,
  PeriodComparison
} from '@/shared/services/ai';
import { RoiSummaryCards } from './RoiSummaryCards';
import { RoiProjectionsChart } from './RoiProjectionsChart';
import { RoiRecommendations } from './RoiRecommendations';
import { RoiComparisonTable } from './RoiComparisonTable';

type TimeRange = '7d' | '14d' | '30d' | '60d' | '90d' | '180d' | '365d';

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

    } catch (_error) {
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

  useEffect(() => {
    loadData();
  }, []);

  useEffect(() => {
    if (dashboardData) {
      loadData(false);
    }
  }, [timeRange, hourlyRate]);

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

      <RoiSummaryCards
        dashboardData={dashboardData}
        formatCurrency={formatCurrency}
        formatHours={formatHours}
      />

      <RoiProjectionsChart
        projections={projections}
        comparison={comparison}
        formatCurrency={formatCurrency}
        formatHours={formatHours}
        getTrendIcon={getTrendIcon}
      />

      <RoiComparisonTable
        dashboardData={dashboardData}
        formatCurrency={formatCurrency}
      />

      <RoiRecommendations
        recommendations={recommendations}
        formatCurrency={formatCurrency}
      />
    </PageContainer>
  );
};

export default RoiDashboard;
