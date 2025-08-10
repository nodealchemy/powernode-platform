import React, { useState, useEffect, useCallback } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '../../store';
import { analyticsService } from '../../services/analyticsService';
import { useWebSocketConnection } from '../../hooks/useWebSocketConnection';
import { useAnalyticsWebSocket } from '../../hooks/useAnalyticsWebSocket';

// Chart Components
import { RevenueChart } from '../../components/analytics/RevenueChart';
import { GrowthChart } from '../../components/analytics/GrowthChart';
import { ChurnChart } from '../../components/analytics/ChurnChart';
import { CustomerChart } from '../../components/analytics/CustomerChart';
import { CohortChart } from '../../components/analytics/CohortChart';
import { MetricsOverview } from '../../components/analytics/MetricsOverview';
import { DateRangeFilter } from '../../components/analytics/DateRangeFilter';
import { AnalyticsExport } from '../../components/analytics/AnalyticsExport';
import { LoadingSpinner } from '../../components/common/LoadingSpinner';

export interface AnalyticsData {
  revenue: any;
  growth: any;
  churn: any;
  customers: any;
  cohorts: any;
}

interface AnalyticsPageProps {}

export const AnalyticsPage: React.FC<AnalyticsPageProps> = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  const { isConnected } = useWebSocketConnection();
  
  // Analytics WebSocket for real-time updates
  const { requestAnalyticsUpdate } = useAnalyticsWebSocket({
    onAnalyticsUpdate: (updateData) => {
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
    },
    onError: (errorMessage) => {
      console.error('Analytics WebSocket error:', errorMessage);
    }
  });
  
  const [data, setData] = useState<AnalyticsData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
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
  const [activeTab, setActiveTab] = useState<'overview' | 'revenue' | 'growth' | 'churn' | 'customers' | 'cohorts'>('overview');

  // Load analytics data
  const loadAnalyticsData = useCallback(async (showLoading = true) => {
    try {
      if (showLoading) {
        setLoading(true);
      }
      setError(null);

      const startDate = dateRange.startDate.toISOString().split('T')[0];
      const endDate = dateRange.endDate.toISOString().split('T')[0];

      console.log('Loading analytics data for date range:', { startDate, endDate });

      // Try to fetch each analytics endpoint individually to identify issues
      let analyticsData: any = {};
      
      try {
        console.log('Fetching revenue analytics...');
        const revenue = await analyticsService.getRevenueAnalytics(startDate, endDate);
        console.log('Revenue response:', revenue);
        analyticsData.revenue = revenue.data;
      } catch (revenueError) {
        console.error('Revenue analytics failed:', revenueError);
        // Provide fallback data
        analyticsData.revenue = {
          current_metrics: { mrr: 0, arr: 0, active_subscriptions: 0, total_customers: 0, arpu: 0, growth_rate: 0 },
          historical_data: [],
          period: { start_date: startDate, end_date: endDate }
        };
      }

      try {
        console.log('Fetching growth analytics...');
        const growth = await analyticsService.getGrowthAnalytics(startDate, endDate);
        console.log('Growth response:', growth);
        analyticsData.growth = growth.data;
      } catch (growthError) {
        console.error('Growth analytics failed:', growthError);
        analyticsData.growth = {
          compound_monthly_growth_rate: 0,
          monthly_growth_data: [],
          forecasting: { next_month_projection: 0, confidence_interval: '±0%' },
          period: { start_date: startDate, end_date: endDate }
        };
      }

      try {
        console.log('Fetching churn analytics...');
        const churn = await analyticsService.getChurnAnalytics(startDate, endDate);
        console.log('Churn response:', churn);
        analyticsData.churn = churn.data;
      } catch (churnError) {
        console.error('Churn analytics failed:', churnError);
        analyticsData.churn = {
          current_metrics: { customer_churn_rate: 0, average_customer_churn_rate: 0, average_revenue_churn_rate: 0, customer_retention_rate: 100 },
          churn_trend: [],
          insights: { churn_risk_level: 'low', recommended_actions: [] },
          period: { start_date: startDate, end_date: endDate }
        };
      }

      try {
        console.log('Fetching customer analytics...');
        const customers = await analyticsService.getCustomerAnalytics(startDate, endDate);
        console.log('Customer response:', customers);
        analyticsData.customers = customers.data;
      } catch (customerError) {
        console.error('Customer analytics failed:', customerError);
        analyticsData.customers = {
          current_metrics: { total_customers: 0, arpu: 0, ltv: 0, ltv_to_cac_ratio: 0 },
          customer_growth_trend: [],
          segmentation: { by_plan: [], by_tenure: [] },
          period: { start_date: startDate, end_date: endDate }
        };
      }

      try {
        console.log('Fetching cohort analytics...');
        const cohorts = await analyticsService.getCohortAnalytics();
        console.log('Cohort response:', cohorts);
        analyticsData.cohorts = cohorts.data;
      } catch (cohortError) {
        console.error('Cohort analytics failed:', cohortError);
        analyticsData.cohorts = {
          cohorts: [],
          summary: { total_cohorts: 0, average_first_month_retention: 0, average_six_month_retention: 0 }
        };
      }

      setData(analyticsData);
      // setLastUpdated(new Date()); // TODO: Display last updated timestamp
      console.log('Analytics data loaded successfully:', analyticsData);
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

  // Auto-refresh data when connected via WebSocket
  useEffect(() => {
    if (isConnected && data) {
      const interval = setInterval(() => {
        // Request real-time analytics update via WebSocket
        requestAnalyticsUpdate();
        
        // Also do a full refresh less frequently
        if (Date.now() % (5 * 60 * 1000) < 30000) { // Every 5 minutes
          loadAnalyticsData(false);
        }
      }, 30000); // Check every 30 seconds

      return () => clearInterval(interval);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isConnected, data, requestAnalyticsUpdate]); // Removed loadAnalyticsData to avoid circular dependency

  const handleDateRangeChange = (newDateRange: { startDate: Date; endDate: Date }) => {
    setDateRange(newDateRange);
  };


  const tabs = [
    { id: 'overview', label: 'Overview', icon: '📊' },
    { id: 'revenue', label: 'Revenue', icon: '💰' },
    { id: 'growth', label: 'Growth', icon: '📈' },
    { id: 'churn', label: 'Churn', icon: '📉' },
    { id: 'customers', label: 'Customers', icon: '👥' },
    { id: 'cohorts', label: 'Cohorts', icon: '🔄' }
  ] as const;

  if (loading) {
    return <LoadingSpinner size="large" message="Loading analytics data..." />;
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
                  className="mt-2 px-3 py-1 bg-theme-error text-white rounded text-sm hover:opacity-80"
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
    return <LoadingSpinner size="large" message="No analytics data available" />;
  }

  return (
    <div className="min-h-screen bg-theme-background-secondary">
      {/* Header */}
      <div className="card-theme shadow-sm border-b border-theme">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between py-4">
            <div>
              <h1 className="text-2xl font-bold text-theme-primary">Analytics Dashboard</h1>
              <p className="text-sm text-theme-secondary">
                Real-time insights for {user?.account?.name || 'your business'}
              </p>
            </div>
            
            <div className="flex items-center space-x-4">
              {/* Export button */}
              <AnalyticsExport 
                dateRange={dateRange}
                onExport={(format, reportType) => 
                  analyticsService.exportAnalytics(format, reportType, dateRange)
                }
              />
            </div>
          </div>

          {/* Date Range Filter */}
          <div className="pb-4">
            <DateRangeFilter
              dateRange={dateRange}
              onChange={handleDateRangeChange}
            />
          </div>

          {/* Navigation Tabs */}
          <div className="flex space-x-8 -mb-px">
            {tabs.map((tab) => (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={`flex items-center space-x-2 py-2 px-1 border-b-2 font-medium text-sm whitespace-nowrap ${
                  activeTab === tab.id
                    ? 'border-theme-link text-theme-link'
                    : 'border-transparent text-theme-secondary hover:text-theme-primary hover:border-theme'
                }`}
              >
                <span>{tab.icon}</span>
                <span>{tab.label}</span>
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* Main Content */}
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
        {activeTab === 'overview' && (
          <div className="space-y-6">
            <MetricsOverview data={data} />
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
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
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
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
        )}

        {activeTab === 'revenue' && (
          <RevenueChart 
            data={data.revenue.historical_data}
            currentMetrics={data.revenue.current_metrics}
            title="Revenue Analytics"
          />
        )}

        {activeTab === 'growth' && (
          <GrowthChart 
            data={data.growth.monthly_growth_data}
            compoundGrowthRate={data.growth.compound_monthly_growth_rate}
            forecasting={data.growth.forecasting}
            title="Growth Analytics"
          />
        )}

        {activeTab === 'churn' && (
          <ChurnChart 
            data={data.churn.churn_trend}
            currentMetrics={data.churn.current_metrics}
            insights={data.churn.insights}
            title="Churn Analysis"
          />
        )}

        {activeTab === 'customers' && (
          <CustomerChart 
            data={data.customers.customer_growth_trend}
            currentMetrics={data.customers.current_metrics}
            segmentation={data.customers.segmentation}
            title="Customer Analytics"
          />
        )}

        {activeTab === 'cohorts' && (
          <CohortChart 
            data={data.cohorts.cohorts}
            summary={data.cohorts.summary}
            title="Cohort Retention Analysis"
          />
        )}
      </div>
    </div>
  );
};