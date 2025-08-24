import React, { useState, useEffect, useCallback } from 'react';
import { useSelector } from 'react-redux';
import { useLocation } from 'react-router-dom';
import { RootState } from '@/shared/services';
import { analyticsService } from '@/features/analytics/services/analyticsService';
import { useAnalyticsWebSocket } from '@/shared/hooks/useAnalyticsWebSocket';

// Chart Components
import { RevenueChart } from '@/features/analytics/components/RevenueChart';
import { GrowthChart } from '@/features/analytics/components/GrowthChart';
import { ChurnChart } from '@/features/analytics/components/ChurnChart';
import { CustomerChart } from '@/features/analytics/components/CustomerChart';
import { CohortChart } from '@/features/analytics/components/CohortChart';
import { MetricsOverview } from '@/features/analytics/components/MetricsOverview';
import { LiveMetricsOverview } from '@/features/analytics/components/LiveMetricsOverview';
import { DateRangeFilter } from '@/features/analytics/components/DateRangeFilter';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { RefreshCw, Download } from 'lucide-react';

export interface AnalyticsData {
  revenue: any;
  growth: any;
  churn: any;
  customers: any;
  cohorts: any;
}

interface AnalyticsPageProps {}

// Fallback data generation functions
const generateFallbackRevenueData = (startDate: string, endDate: string) => {
  const data = [];
  const start = new Date(startDate);
  const end = new Date(endDate);
  
  let currentDate = new Date(start);
  let baseMRR = 5000;
  
  while (currentDate <= end) {
    const growth = 1 + (Math.random() * 0.2 - 0.1); // ±10% random growth
    baseMRR *= growth;
    
    data.push({
      date: currentDate.toISOString().split('T')[0],
      mrr: Math.round(baseMRR),
      arr: Math.round(baseMRR * 12),
      active_subscriptions: Math.round(baseMRR / 50), // Assume $50 average
      new_subscriptions: Math.round(Math.random() * 10),
      churned_subscriptions: Math.round(Math.random() * 5)
    });
    
    currentDate.setMonth(currentDate.getMonth() + 1);
  }
  
  return {
    current_metrics: {
      mrr: baseMRR,
      arr: baseMRR * 12,
      active_subscriptions: Math.round(baseMRR / 50),
      total_customers: Math.round(baseMRR / 50),
      arpu: 50,
      growth_rate: 15.5
    },
    historical_data: data,
    period: { start_date: startDate, end_date: endDate }
  };
};

const generateFallbackGrowthData = (startDate: string, endDate: string) => {
  const data = [];
  const start = new Date(startDate);
  const end = new Date(endDate);
  
  let currentDate = new Date(start);
  let baseMRR = 5000;
  
  while (currentDate <= end) {
    const growthRate = (Math.random() * 20 - 5); // -5% to 15% growth
    baseMRR *= (1 + growthRate / 100);
    
    data.push({
      date: currentDate.toISOString().split('T')[0],
      mrr: Math.round(baseMRR),
      growth_rate: Math.round(growthRate * 10) / 10,
      new_revenue: Math.round(baseMRR * 0.1),
      churned_revenue: Math.round(baseMRR * 0.05)
    });
    
    currentDate.setMonth(currentDate.getMonth() + 1);
  }
  
  return {
    compound_monthly_growth_rate: 8.5,
    monthly_growth_data: data,
    forecasting: {
      next_month_projection: Math.round(baseMRR * 1.1),
      confidence_interval: '±15%'
    },
    period: { start_date: startDate, end_date: endDate }
  };
};

const generateFallbackChurnData = (startDate: string, endDate: string) => {
  const data = [];
  const start = new Date(startDate);
  const end = new Date(endDate);
  
  let currentDate = new Date(start);
  
  while (currentDate <= end) {
    data.push({
      date: currentDate.toISOString().split('T')[0],
      customer_churn_rate: Math.random() * 8, // 0-8% churn
      revenue_churn_rate: Math.random() * 6, // 0-6% revenue churn
      churned_customers: Math.round(Math.random() * 15),
      churned_subscriptions: Math.round(Math.random() * 10)
    });
    
    currentDate.setMonth(currentDate.getMonth() + 1);
  }
  
  return {
    current_metrics: {
      customer_churn_rate: 3.2,
      average_customer_churn_rate: 4.1,
      average_revenue_churn_rate: 2.8,
      customer_retention_rate: 96.8
    },
    churn_trend: data,
    insights: {
      churn_risk_level: 'medium' as const,
      recommended_actions: [
        'Implement proactive customer success outreach',
        'Analyze churned customer feedback',
        'Consider loyalty programs'
      ]
    },
    period: { start_date: startDate, end_date: endDate }
  };
};

const generateFallbackCustomerData = (startDate: string, endDate: string) => {
  const data = [];
  const start = new Date(startDate);
  const end = new Date(endDate);
  
  let currentDate = new Date(start);
  let totalCustomers = 100;
  
  while (currentDate <= end) {
    const newCustomers = Math.round(Math.random() * 20);
    const churnedCustomers = Math.round(Math.random() * 8);
    totalCustomers += (newCustomers - churnedCustomers);
    
    data.push({
      date: currentDate.toISOString().split('T')[0],
      total_customers: totalCustomers,
      new_customers: newCustomers,
      churned_customers: churnedCustomers,
      net_growth: newCustomers - churnedCustomers,
      arpu: Math.round((40 + Math.random() * 30) * 100) / 100, // $40-70
      ltv: Math.round((800 + Math.random() * 600) * 100) / 100 // $800-1400
    });
    
    currentDate.setMonth(currentDate.getMonth() + 1);
  }
  
  return {
    current_metrics: {
      total_customers: totalCustomers,
      arpu: 55.50,
      ltv: 1100.00,
      ltv_to_cac_ratio: 3.2
    },
    customer_growth_trend: data,
    segmentation: {
      by_plan: [
        { plan: 'Starter', customers: Math.round(totalCustomers * 0.6) },
        { plan: 'Professional', customers: Math.round(totalCustomers * 0.3) },
        { plan: 'Enterprise', customers: Math.round(totalCustomers * 0.1) }
      ],
      by_tenure: [
        { segment: 'New (0-3 months)', customers: Math.round(totalCustomers * 0.25) },
        { segment: 'Growing (3-12 months)', customers: Math.round(totalCustomers * 0.45) },
        { segment: 'Mature (12+ months)', customers: Math.round(totalCustomers * 0.30) }
      ]
    },
    period: { start_date: startDate, end_date: endDate }
  };
};

const generateFallbackCohortData = () => {
  const cohorts = [];
  
  for (let i = 0; i < 12; i++) {
    const cohortDate = new Date();
    cohortDate.setMonth(cohortDate.getMonth() - i);
    const cohortSize = Math.round(20 + Math.random() * 40);
    
    const retentionRates = [];
    let retentionRate = 1.0;
    
    for (let month = 0; month < 12; month++) {
      if (month > 0) {
        retentionRate *= (0.85 + Math.random() * 0.10); // 85-95% retention month over month
      }
      
      retentionRates.push({
        month,
        retention_rate: retentionRate,
        retained_customers: Math.round(cohortSize * retentionRate)
      });
    }
    
    cohorts.push({
      cohort_date: cohortDate.toISOString().slice(0, 7), // YYYY-MM format
      cohort_size: cohortSize,
      retention_rates: retentionRates
    });
  }
  
  return {
    cohorts,
    summary: {
      total_cohorts: cohorts.length,
      average_first_month_retention: 92.5,
      average_six_month_retention: 68.8
    }
  };
};

export const AnalyticsPage: React.FC<AnalyticsPageProps> = () => {
AnalyticsPage.displayName = 'AnalyticsPage';
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
  
  // Stable callbacks to prevent WebSocket reconnections
  const handleAnalyticsUpdate = useCallback((updateData: any) => {
    // Update specific metrics without full reload
    if (data && updateData.current_metrics) {
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
      // setLastUpdated(new Date()); // TODO: Display last updated timestamp
    }
  }, []);

  const handleWebSocketError = useCallback((errorMessage: string) => {
    console.error('Analytics WebSocket error:', errorMessage);
  }, []);

  // Analytics WebSocket for real-time updates
  const { requestAnalyticsUpdate, isConnected } = useAnalyticsWebSocket({
    onAnalyticsUpdate: handleAnalyticsUpdate,
    onError: handleWebSocketError
  });
  
  const [data, setData] = useState<AnalyticsData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [usingFallbackData, setUsingFallbackData] = useState(false);
  const [showExportModal, setShowExportModal] = useState(false);
  // const [lastUpdated, setLastUpdated] = useState<Date | null>(null); // TODO: Display last updated timestamp
  
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
  
  // Update active tab when URL changes
  useEffect(() => {
    const newActiveTab = getActiveTabFromPath();
    if (newActiveTab !== activeTab) {
      setActiveTab(newActiveTab);
    }
  }, [location.pathname, getActiveTabFromPath, activeTab]);

  // Load analytics data
  const loadAnalyticsData = useCallback(async (showLoading = true) => {
    try {
      if (showLoading) {
        setLoading(true);
      }
      setError(null);
      setUsingFallbackData(false);

      const startDate = dateRange.startDate.toISOString().split('T')[0];
      const endDate = dateRange.endDate.toISOString().split('T')[0];


      // Try to fetch each analytics endpoint individually to identify issues
      let analyticsData: unknown = {};
      
      try {
        const revenue = await analyticsService.getRevenueAnalytics(startDate, endDate);
        analyticsData.revenue = revenue.data;
      } catch (revenueError) {
        console.error('Revenue analytics failed:', revenueError);
        // Provide realistic fallback data for demonstration
        const fallbackData = generateFallbackRevenueData(startDate, endDate);
        analyticsData.revenue = fallbackData;
        setUsingFallbackData(true);
      }

      try {
        const growth = await analyticsService.getGrowthAnalytics(startDate, endDate);
        analyticsData.growth = growth.data;
      } catch (growthError) {
        console.error('Growth analytics failed:', growthError);
        const fallbackData = generateFallbackGrowthData(startDate, endDate);
        analyticsData.growth = fallbackData;
        setUsingFallbackData(true);
      }

      try {
        const churn = await analyticsService.getChurnAnalytics(startDate, endDate);
        analyticsData.churn = churn.data;
      } catch (churnError) {
        console.error('Churn analytics failed:', churnError);
        const fallbackData = generateFallbackChurnData(startDate, endDate);
        analyticsData.churn = fallbackData;
        setUsingFallbackData(true);
      }

      try {
        const customers = await analyticsService.getCustomerAnalytics(startDate, endDate);
        analyticsData.customers = customers.data;
      } catch (customerError) {
        console.error('Customer analytics failed:', customerError);
        const fallbackData = generateFallbackCustomerData(startDate, endDate);
        analyticsData.customers = fallbackData;
        setUsingFallbackData(true);
      }

      try {
        const cohorts = await analyticsService.getCohortAnalytics();
        analyticsData.cohorts = cohorts.data;
      } catch (cohortError) {
        console.error('Cohort analytics failed:', cohortError);
        const fallbackData = generateFallbackCohortData();
        analyticsData.cohorts = fallbackData;
        setUsingFallbackData(true);
      }

      setData(analyticsData);
      // setLastUpdated(new Date()); // TODO: Display last updated timestamp
    } catch (err) {
      console.error('Failed to load analytics data:', err);
      setError(err instanceof Error ? err.message : 'Failed to load analytics data');
    } finally {
      setLoading(false);
    }
  }, [dateRange]);

  // Initial data load
  useEffect(() => {
    loadAnalyticsData();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [dateRange]); // Only depend on dateRange, not loadAnalyticsData to avoid circular dependency

  // Auto-refresh analytics data when WebSocket is connected
  useEffect(() => {
    if (isConnected && data) {
      const interval = setInterval(() => {
        // Request real-time analytics update via WebSocket
        requestAnalyticsUpdate();
      }, 30000); // Request update every 30 seconds

      return () => {
        clearInterval(interval);
      };
    }
  }, [isConnected, data, requestAnalyticsUpdate]);

  const handleDateRangeChange = (newDateRange: { startDate: Date; endDate: Date }) => {
    setDateRange(newDateRange);
  };

  // Export functionality
  const handleExport = async (format: 'csv' | 'pdf', reportType: string) => {
    try {
      await analyticsService.exportAnalytics(format, reportType, dateRange);
      setShowExportModal(false);
    } catch (error) {
      console.error('Export failed:', error);
    }
  };

  // Define page actions for PageContainer
  const pageActions: PageAction[] = [
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: () => loadAnalyticsData(),
      variant: 'secondary',
      icon: RefreshCw,
      disabled: loading
    },
    {
      id: 'export',
      label: 'Export',
      onClick: () => setShowExportModal(true),
      variant: 'secondary',
      icon: Download,
      disabled: loading || !data
    }
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
                  onClick={() => loadAnalyticsData()}
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
    const baseBreadcrumbs = [
      { label: 'Dashboard', href: '/app', icon: '🏠' },
      { label: 'Business', href: '/app/business', icon: '💼' },
      { label: 'Analytics', icon: '📊' }
    ];
    
    // Add active tab to breadcrumbs if not the default overview tab
    const activeTabInfo = tabs.find(tab => tab.id === activeTab);
    if (activeTabInfo && activeTab !== 'overview') {
      baseBreadcrumbs.push({
        label: activeTabInfo.label,
        icon: activeTabInfo.icon
      });
    }
    
    return baseBreadcrumbs;
  };

  return (
    <PageContainer
      title="Analytics Dashboard"
      description={`Real-time insights for ${user?.account?.name || 'your business'}`}
      breadcrumbs={getBreadcrumbs()}
      actions={pageActions}
    >
      {/* Date Range Filter */}
      <div className="mb-6">
        <DateRangeFilter
          dateRange={dateRange}
          onChange={handleDateRangeChange}
        />
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
                onClick={() => loadAnalyticsData()}
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
              updateInterval={15000}
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
      {showExportModal && (
        <div className="fixed inset-0 z-50 overflow-y-auto">
          <div className="flex items-end justify-center min-h-screen pt-4 px-4 pb-20 text-center sm:block sm:p-0">
            {/* Backdrop */}
            <div 
              className="fixed inset-0 bg-black bg-opacity-50 transition-opacity" 
              onClick={() => setShowExportModal(false)}
            />
            
            {/* Modal */}
            <div className="inline-block align-bottom bg-theme-surface rounded-lg px-4 pt-5 pb-4 text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-2xl sm:w-full sm:p-6 relative z-10">
              <div className="w-full">
                <div className="flex justify-between items-center mb-4">
                  <h3 className="text-lg leading-6 font-medium text-theme-primary">
                    Export Analytics Data
                  </h3>
                  <button
                    onClick={() => setShowExportModal(false)}
                    className="text-theme-tertiary hover:text-theme-secondary"
                  >
                    ✕
                  </button>
                </div>
                
                <p className="text-sm text-theme-secondary mb-6">
                  Export data from {dateRange.startDate.toLocaleDateString()} to {dateRange.endDate.toLocaleDateString()}
                </p>
                
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 mb-6">
                  {[
                    { type: 'revenue', label: 'Revenue Analytics', description: 'MRR, ARR, growth trends', icon: '💰' },
                    { type: 'growth', label: 'Growth Analytics', description: 'Growth rates, new revenue', icon: '📈' },
                    { type: 'churn', label: 'Churn Analysis', description: 'Customer and revenue churn', icon: '📉' },
                    { type: 'customers', label: 'Customer Analytics', description: 'Customer growth, ARPU, LTV', icon: '👥' },
                    { type: 'cohorts', label: 'Cohort Analysis', description: 'Customer retention by cohort', icon: '🔄' },
                    { type: 'all', label: 'Complete Report', description: 'All analytics data', icon: '📊' }
                  ].map((option) => (
                    <div key={option.type} className="border border-theme rounded-lg p-4">
                      <div className="flex items-start space-x-3 mb-3">
                        <span className="text-lg">{option.icon}</span>
                        <div className="flex-1 min-w-0">
                          <h4 className="text-sm font-medium text-theme-primary">{option.label}</h4>
                          <p className="text-xs text-theme-tertiary">{option.description}</p>
                        </div>
                      </div>
                      
                      <div className="flex space-x-2">
                        <button
                          onClick={() => handleExport('csv', option.type)}
                          className="flex-1 px-3 py-2 text-xs bg-theme-success-background text-theme-success rounded hover:bg-theme-success-background-hover"
                        >
                          CSV
                        </button>
                        <button
                          onClick={() => handleExport('pdf', option.type)}
                          className="flex-1 px-3 py-2 text-xs bg-theme-error-background text-theme-error rounded hover:bg-theme-error-background-hover"
                        >
                          PDF
                        </button>
                      </div>
                    </div>
                  ))}
                </div>
                
                <div className="bg-theme-background-secondary p-3 rounded-lg">
                  <div className="flex items-start text-xs text-theme-tertiary">
                    <span className="text-lg mr-2">ℹ️</span>
                    <div>
                      <p>CSV exports include raw data for further analysis.</p>
                      <p className="mt-1">PDF reports include formatted charts and summaries.</p>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}
    </PageContainer>
  );
};