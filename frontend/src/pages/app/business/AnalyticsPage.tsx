import React, { useState, useEffect, useCallback, useRef } from 'react';
import { useSelector } from 'react-redux';
import { useLocation } from 'react-router-dom';
import { RootState } from '@/shared/services';
import { analyticsService } from '@/features/business/analytics/services/analyticsService';
import { useAnalyticsWebSocket } from '@/shared/hooks/useAnalyticsWebSocket';
import { hasPermissions } from '@/shared/utils/permissionUtils';

// Chart Components
import { RevenueChart } from '@/features/business/analytics/components/RevenueChart';
import { GrowthChart } from '@/features/business/analytics/components/GrowthChart';
import { ChurnChart } from '@/features/business/analytics/components/ChurnChart';
import { CustomerChart } from '@/features/business/analytics/components/CustomerChart';
import { CohortChart } from '@/features/business/analytics/components/CohortChart';
import { MetricsOverview } from '@/features/business/analytics/components/MetricsOverview';
import { LiveMetricsOverview } from '@/features/business/analytics/components/LiveMetricsOverview';
import { DateRangeFilter } from '@/features/business/analytics/components/DateRangeFilter';
import { AnalyticsExportModal } from '@/features/business/analytics/components/AnalyticsExportModal';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { RefreshCw, Download, Lock, Clock } from 'lucide-react';

// Types and utilities
import type { AnalyticsData } from '@/features/business/analytics/types';
import {
  generateFallbackRevenueData,
  generateFallbackGrowthData,
  generateFallbackChurnData,
  generateFallbackCustomerData,
  generateFallbackCohortData
} from '@/features/business/analytics/utils/fallbackDataGenerators';

// Re-export for backwards compatibility
export type { AnalyticsData } from '@/features/business/analytics/types';

// Format relative time for last updated display
const formatRelativeTime = (date: Date | null): string => {
  if (!date) return '';

  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffSeconds = Math.floor(diffMs / 1000);
  const diffMinutes = Math.floor(diffSeconds / 60);
  const diffHours = Math.floor(diffMinutes / 60);

  if (diffSeconds < 60) {
    return 'just now';
  } else if (diffMinutes < 60) {
    return `${diffMinutes} minute${diffMinutes !== 1 ? 's' : ''} ago`;
  } else if (diffHours < 24) {
    return `${diffHours} hour${diffHours !== 1 ? 's' : ''} ago`;
  } else {
    return date.toLocaleString();
  }
};

interface AnalyticsPageProps {}

export const AnalyticsPage: React.FC<AnalyticsPageProps> = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  const location = useLocation();
  
  // Get active tab from URL path
  const getActiveTabFromPath = useCallback(() => {
    const path = location.pathname;
    if (path === '/app/business/analytics') return 'overview';
    if (path.includes('/live')) return 'live';
    if (path.includes('/revenue')) return 'revenue';
    if (path.includes('/growth')) return 'growth';
    if (path.includes('/churn')) return 'churn';
    if (path.includes('/customers')) return 'customers';
    if (path.includes('/cohorts')) return 'cohorts';
    return 'overview';
  }, [location.pathname]);
  
  // Type guard for analytics update data
  const isAnalyticsUpdateData = (data: unknown): data is { current_metrics?: Record<string, any> } => {
    return typeof data === 'object' && data !== null;
  };

  // Stable callbacks to prevent WebSocket reconnections
  const handleAnalyticsUpdate = useCallback((updateData: unknown) => {
    // Update specific metrics without full reload
    if (isAnalyticsUpdateData(updateData) && updateData.current_metrics) {
      setData(prevData => prevData ? {
        ...prevData,
        revenue: {
          ...prevData.revenue,
          current_metrics: {
            ...prevData.revenue.current_metrics,
            ...updateData.current_metrics
          }
        }
      } : prevData);
      setLastUpdated(new Date());
    }
  }, []);

  const handleWebSocketError = useCallback((_errorMessage: string) => {
    // Error handling could be added here
  }, []);

  // Analytics WebSocket for real-time updates
  // WebSocket receives pushed updates via handleAnalyticsUpdate callback
  useAnalyticsWebSocket({
    onAnalyticsUpdate: handleAnalyticsUpdate,
    onError: handleWebSocketError
  });
  
  // Refs to track loading state and prevent double-loading in StrictMode
  const isInitialLoad = useRef(true);

  const [data, setData] = useState<AnalyticsData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [usingFallbackData, setUsingFallbackData] = useState(false);
  const [showExportModal, setShowExportModal] = useState(false);
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null);
  
  // Check permissions before loading analytics
  const canViewAnalytics = hasPermissions(user, ['ai.analytics.read', 'admin.access']);
  const canExportAnalytics = hasPermissions(user, ['ai.analytics.export', 'admin.access']);
  
  // Date range state
  const [dateRange, setDateRange] = useState<{
    startDate: Date;
    endDate: Date;
  }>({
    startDate: new Date(Date.now() - 365 * 24 * 60 * 60 * 1000), // 1 year ago
    endDate: new Date()
  });

  // Active tab state
  const [activeTab, setActiveTab] = useState(() => getActiveTabFromPath());
  
  // Update active tab when URL changes (with debouncing)
  useEffect(() => {
    const timeoutId = setTimeout(() => {
      const newActiveTab = getActiveTabFromPath();
      if (newActiveTab !== activeTab) {
        setActiveTab(newActiveTab);
      }
    }, 50);

    return () => clearTimeout(timeoutId);
  }, [location.pathname]); // eslint-disable-line react-hooks/exhaustive-deps

  // Load analytics data with StrictMode protection
  const loadAnalyticsData = useCallback(async (force = false) => {
    // Prevent double-loading in React.StrictMode during initial mount
    if (isInitialLoad.current && !force && data && !usingFallbackData) {
      return;
    }

    // Don't load if user doesn't have permission
    if (!canViewAnalytics) {
      setLoading(false);
      return;
    }

    try {
      setLoading(true);
      setError(null);
      setUsingFallbackData(false);

      const startDate = dateRange.startDate.toISOString().split('T')[0];
      const endDate = dateRange.endDate.toISOString().split('T')[0];


      // Try to fetch each analytics endpoint individually to identify issues
      let analyticsData: Partial<AnalyticsData> = {};
      
      try {
        const revenue = await analyticsService.getRevenueAnalytics(startDate, endDate);
        analyticsData.revenue = revenue.data;
      } catch (revenueError) {
        // Provide realistic fallback data for demonstration
        const fallbackData = generateFallbackRevenueData(startDate, endDate);
        analyticsData.revenue = fallbackData;
        setUsingFallbackData(true);
      }

      try {
        const growth = await analyticsService.getGrowthAnalytics(startDate, endDate);
        analyticsData.growth = growth.data;
      } catch (growthError) {
        const fallbackData = generateFallbackGrowthData(startDate, endDate);
        analyticsData.growth = fallbackData;
        setUsingFallbackData(true);
      }

      try {
        const churn = await analyticsService.getChurnAnalytics(startDate, endDate);
        analyticsData.churn = churn.data;
      } catch (churnError) {
        const fallbackData = generateFallbackChurnData(startDate, endDate);
        analyticsData.churn = fallbackData;
        setUsingFallbackData(true);
      }

      try {
        const customers = await analyticsService.getCustomerAnalytics(startDate, endDate);
        analyticsData.customers = customers.data;
      } catch (customerError) {
        const fallbackData = generateFallbackCustomerData(startDate, endDate);
        analyticsData.customers = fallbackData;
        setUsingFallbackData(true);
      }

      try {
        const cohorts = await analyticsService.getCohortAnalytics();
        analyticsData.cohorts = cohorts.data;
      } catch (cohortError) {
        const fallbackData = generateFallbackCohortData();
        analyticsData.cohorts = fallbackData;
        setUsingFallbackData(true);
      }

      // Type assertion is safe here since we've populated all required fields
      setData(analyticsData as AnalyticsData);
      isInitialLoad.current = false;
      setLastUpdated(new Date());
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load analytics data');
    } finally {
      setLoading(false);
    }
  }, [dateRange.startDate.getTime(), dateRange.endDate.getTime(), canViewAnalytics]); // eslint-disable-line react-hooks/exhaustive-deps

  // Initial data load with StrictMode protection
  // WebSocket via useAnalyticsWebSocket handles real-time updates
  useEffect(() => {
    const timeoutId = setTimeout(() => {
      loadAnalyticsData();
    }, 0);
    return () => clearTimeout(timeoutId);
  }, [dateRange.startDate, dateRange.endDate]); // eslint-disable-line react-hooks/exhaustive-deps

  const handleDateRangeChange = (newDateRange: { startDate: Date; endDate: Date }) => {
    setDateRange(newDateRange);
  };

  // Export functionality
  const handleExport = async (format: 'csv' | 'pdf', reportType: string) => {
    if (!canExportAnalytics) {
      return; // Don't export if user doesn't have permission
    }

    try {
      await analyticsService.exportAnalytics(format, reportType, dateRange);
      setShowExportModal(false);
    } catch (_error) {
      // Error handling could be added here
    }
  };

  // Define page actions for PageContainer
  const pageActions: PageAction[] = [
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: () => loadAnalyticsData(true), // Force refresh when manually triggered
      variant: 'secondary',
      icon: RefreshCw,
      disabled: loading
    },
    // Only show export if user has permission
    ...(canExportAnalytics ? [{
      id: 'export',
      label: 'Export',
      onClick: () => setShowExportModal(true),
      variant: 'secondary' as const,
      icon: Download,
      disabled: loading || !data
    }] : [])
  ];

  const tabs = [
    { id: 'overview', label: 'Overview', icon: '📊', path: '/' },
    { id: 'live', label: 'Live', icon: '🔴', path: '/live' },
    { id: 'revenue', label: 'Revenue', icon: '💰', path: '/revenue' },
    { id: 'growth', label: 'Growth', icon: '📈', path: '/growth' },
    { id: 'churn', label: 'Churn', icon: '📉', path: '/churn' },
    { id: 'customers', label: 'Customers', icon: '👥', path: '/customers' },
    { id: 'cohorts', label: 'Cohorts', icon: '🔄', path: '/cohorts' }
  ];

  if (loading) {
    return <LoadingSpinner size="lg" message="Loading analytics data..." />;
  }

  if (error) {
    return (
      <div className="min-h-screen bg-theme-background-secondary p-6">
        <div className="max-w-7xl mx-auto">
          <div className="bg-theme-error text-theme-error card-theme p-6">
            <div className="flex items-center">
              <div className="flex-shrink-0">
                <span className="text-theme-error text-xl">⚠️</span>
              </div>
              <div className="ml-3">
                <h3 className="text-sm font-medium text-theme-error">Error Loading Analytics</h3>
                <p className="mt-1 text-sm text-theme-error">{error}</p>
                <button
                  onClick={() => loadAnalyticsData(true)}
                  className="mt-2 px-3 py-1 bg-theme-error text-theme-error-contrast rounded text-sm hover:opacity-80"
                >
                  Try Again
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    );
  }

  if (!data) {
    return <LoadingSpinner size="lg" message="No analytics data available" />;
  }

  // Dynamic breadcrumbs based on active tab
  const getBreadcrumbs = () => {
    const baseBreadcrumbs: Array<{ label: string; href?: string }> = [
      { label: 'Dashboard', href: '/app' },
      { label: 'Business', href: '/app/business' },
      { label: 'Analytics' }
    ];

    // Add active tab to breadcrumbs if not the default overview tab
    const activeTabInfo = tabs.find(tab => tab.id === activeTab);
    if (activeTabInfo && activeTab !== 'overview') {
      baseBreadcrumbs.push({
        label: activeTabInfo.label
      });
    }

    return baseBreadcrumbs;
  };

  // Show access denied if user doesn't have permission
  if (!canViewAnalytics) {
    return (
      <PageContainer
        title="Analytics Dashboard"
        description="Analytics insights and reporting"
        breadcrumbs={getBreadcrumbs()}
        actions={[]}
      >
        <div className="text-center py-12">
          <Lock className="w-12 h-12 text-theme-secondary mx-auto mb-4" />
          <h3 className="text-lg font-medium text-theme-primary mb-2">Analytics Access Restricted</h3>
          <p className="text-theme-secondary">You need analytics.read permission to access this dashboard</p>
        </div>
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title="Analytics Dashboard"
      description={`Real-time insights for ${user?.account?.name || 'your business'}`}
      breadcrumbs={getBreadcrumbs()}
      actions={pageActions}
    >
      {/* Date Range Filter with Last Updated */}
      <div className="mb-6 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <DateRangeFilter
          dateRange={dateRange}
          onChange={handleDateRangeChange}
        />
        {lastUpdated && (
          <div className="flex items-center gap-2 text-sm text-theme-secondary">
            <Clock className="h-4 w-4" />
            <span>Last updated: {formatRelativeTime(lastUpdated)}</span>
          </div>
        )}
      </div>

      {/* Fallback Data Notification */}
      {usingFallbackData && (
        <div className="bg-theme-warning-background border border-theme-warning-border text-theme-warning px-4 py-3 mb-6 rounded-lg">
          <div className="flex items-center">
            <div className="flex-shrink-0">
              <span className="text-lg">ℹ️</span>
            </div>
            <div className="ml-3">
              <p className="text-sm font-medium">
                Currently displaying demo data. Some analytics endpoints may be unavailable.
              </p>
            </div>
            <div className="ml-auto pl-3">
              <button
                onClick={() => loadAnalyticsData(true)}
                className="text-sm font-medium text-theme-warning underline hover:no-underline"
              >
                Retry
              </button>
            </div>
          </div>
        </div>
      )}

      <TabContainer
        tabs={tabs}
        activeTab={activeTab}
        onTabChange={setActiveTab}
        basePath="/app/business/analytics"
        variant="underline"
        className="mb-6"
      >
        <TabPanel tabId="overview" activeTab={activeTab}>
          <div className="space-y-4 sm:space-y-6">
            <MetricsOverview data={data} />
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 sm:gap-6">
              <RevenueChart 
                data={data.revenue.historical_data} 
                title="Revenue Trend (Last 12 Months)"
                compact
              />
              <GrowthChart 
                data={data.growth.monthly_growth_data} 
                title="Growth Rate"
                compact
              />
            </div>
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 sm:gap-6">
              <ChurnChart 
                data={data.churn.churn_trend} 
                title="Churn Analysis"
                compact
              />
              <CustomerChart 
                data={data.customers.customer_growth_trend} 
                title="Customer Growth"
                compact
              />
            </div>
          </div>
        </TabPanel>

        <TabPanel tabId="live" activeTab={activeTab}>
          <div className="space-y-4 sm:space-y-6">
            <LiveMetricsOverview 
              accountId={user?.account?.id}
              showTodayActivity={true}
              showWeeklyTrend={true}
              updateInterval={30000}
            />
          </div>
        </TabPanel>

        <TabPanel tabId="revenue" activeTab={activeTab}>
          <div className="chart-container">
            <RevenueChart 
              data={data.revenue.historical_data}
              currentMetrics={data.revenue.current_metrics}
              title="Revenue Analytics"
            />
          </div>
        </TabPanel>

        <TabPanel tabId="growth" activeTab={activeTab}>
          <div className="chart-container">
            <GrowthChart 
              data={data.growth.monthly_growth_data}
              compoundGrowthRate={data.growth.compound_monthly_growth_rate}
              forecasting={data.growth.forecasting}
              title="Growth Analytics"
            />
          </div>
        </TabPanel>

        <TabPanel tabId="churn" activeTab={activeTab}>
          <div className="chart-container">
            <ChurnChart 
              data={data.churn.churn_trend}
              currentMetrics={data.churn.current_metrics}
              insights={data.churn.insights}
              title="Churn Analysis"
            />
          </div>
        </TabPanel>

        <TabPanel tabId="customers" activeTab={activeTab}>
          <div className="chart-container">
            <CustomerChart 
              data={data.customers.customer_growth_trend}
              currentMetrics={data.customers.current_metrics}
              segmentation={data.customers.segmentation}
              title="Customer Analytics"
            />
          </div>
        </TabPanel>

        <TabPanel tabId="cohorts" activeTab={activeTab}>
          <div className="chart-container">
            <CohortChart 
              data={data.cohorts.cohorts}
              summary={data.cohorts.summary}
              title="Cohort Retention Analysis"
            />
          </div>
        </TabPanel>
      </TabContainer>

      {/* Export Modal */}
      <AnalyticsExportModal
        isOpen={showExportModal}
        onClose={() => setShowExportModal(false)}
        dateRange={dateRange}
        onExport={handleExport}
      />
    </PageContainer>
  );
};