import React from 'react';
import {
  BarChart3,
  AlertTriangle,
  Download
} from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { Select } from '@/shared/components/ui/Select';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { DateRangePicker } from '@/shared/components/ui/DateRangePicker';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import {
  AnalyticsSummaryCards,
  PerformanceMetrics,
  useAnalyticsData,
} from '@/features/ai/workflows/components/analytics-page';

// Extracted content component for embedding in tabbed pages
export const WorkflowAnalyticsContent: React.FC = () => {
  const {
    analyticsData,
    loading,
    startDate,
    setStartDate,
    endDate,
    setEndDate,
    selectedPeriod,
    canViewAnalytics,
    handlePeriodChange,
    formatDuration,
    formatPercentage,
    handleExportData,
  } = useAnalyticsData();

  usePageWebSocket({ pageType: 'ai', onDataUpdate: () => {} });

  if (!canViewAnalytics) {
    return (
      <Card>
        <CardContent className="text-center py-8">
          <AlertTriangle className="h-12 w-12 text-theme-warning mx-auto mb-4" />
          <h3 className="text-lg font-medium mb-2">Access Denied</h3>
          <p className="text-theme-muted">You don't have permission to view workflow analytics.</p>
        </CardContent>
      </Card>
    );
  }

  if (loading) {
    return <LoadingSpinner className="py-12" message="Loading analytics data..." />;
  }

  return (
    <div className="space-y-6">
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
        <button onClick={handleExportData} disabled={!analyticsData} className="btn-theme btn-theme-secondary btn-theme-sm flex items-center gap-2">
          <Download className="h-4 w-4" /> Export
        </button>
      </div>

      {analyticsData ? (
        <>
          <AnalyticsSummaryCards
            statistics={analyticsData.statistics}
            metrics={analyticsData.executionMetrics.metrics}
            formatDuration={formatDuration}
            formatPercentage={formatPercentage}
          />
          <PerformanceMetrics
            statistics={analyticsData.statistics}
            metrics={analyticsData.executionMetrics.metrics}
            formatDuration={formatDuration}
            formatPercentage={formatPercentage}
          />
        </>
      ) : (
        <Card>
          <CardContent className="text-center py-8">
            <BarChart3 className="h-12 w-12 text-theme-muted mx-auto mb-4 opacity-50" />
            <h3 className="text-lg font-medium mb-2">No Analytics Data</h3>
            <p className="text-theme-muted">No analytics data available for the selected period.</p>
          </CardContent>
        </Card>
      )}
    </div>
  );
};

export const WorkflowAnalyticsPage: React.FC = () => {
  const {
    analyticsData,
    loading,
    startDate,
    setStartDate,
    endDate,
    setEndDate,
    selectedPeriod,
    canViewAnalytics,
    handlePeriodChange,
    formatDuration,
    formatPercentage,
    handleExportData,
  } = useAnalyticsData();

  usePageWebSocket({ pageType: 'ai', onDataUpdate: () => {} });

  if (!canViewAnalytics) {
    return (
      <PageContainer title="Access Denied" description="You don't have permission to view analytics">
        <Card>
          <CardContent className="text-center py-8">
            <AlertTriangle className="h-12 w-12 text-theme-warning mx-auto mb-4" />
            <h3 className="text-lg font-medium mb-2">Access Denied</h3>
            <p className="text-theme-muted">You don't have permission to view workflow analytics.</p>
          </CardContent>
        </Card>
      </PageContainer>
    );
  }

  if (loading) {
    return (
      <PageContainer title="Workflow Analytics" description="Loading analytics data...">
        <LoadingSpinner className="py-12" message="Loading analytics data..." />
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

        {analyticsData ? (
          <>
            <AnalyticsSummaryCards
              statistics={analyticsData.statistics}
              metrics={analyticsData.executionMetrics.metrics}
              formatDuration={formatDuration}
              formatPercentage={formatPercentage}
            />
            <PerformanceMetrics
              statistics={analyticsData.statistics}
              metrics={analyticsData.executionMetrics.metrics}
              formatDuration={formatDuration}
              formatPercentage={formatPercentage}
            />
          </>
        ) : (
          <Card>
            <CardContent className="text-center py-8">
              <BarChart3 className="h-12 w-12 text-theme-muted mx-auto mb-4 opacity-50" />
              <h3 className="text-lg font-medium mb-2">No Analytics Data</h3>
              <p className="text-theme-muted">No analytics data available for the selected period.</p>
            </CardContent>
          </Card>
        )}
      </div>
    </PageContainer>
  );
};
