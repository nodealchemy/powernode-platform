import React, { useState, useEffect } from 'react';
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
        setLastUpdated(new Date());
      }
    },
    onError: (errorMessage) => {
      console.error('Analytics WebSocket error:', errorMessage);
    }
  });
  
  const [data, setData] = useState<AnalyticsData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null);
  
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
  const loadAnalyticsData = async (showLoading = true) => {
    try {
      if (showLoading) {
        setLoading(true);
      } else {
        setRefreshing(true);
      }
      setError(null);

      const startDate = dateRange.startDate.toISOString().split('T')[0];
      const endDate = dateRange.endDate.toISOString().split('T')[0];

      // Fetch all analytics data in parallel
      const [revenue, growth, churn, customers, cohorts] = await Promise.all([
        analyticsService.getRevenueAnalytics(startDate, endDate),
        analyticsService.getGrowthAnalytics(startDate, endDate),
        analyticsService.getChurnAnalytics(startDate, endDate),
        analyticsService.getCustomerAnalytics(startDate, endDate),
        analyticsService.getCohortAnalytics()
      ]);

      setData({
        revenue: revenue.data,
        growth: growth.data,
        churn: churn.data,
        customers: customers.data,
        cohorts: cohorts.data
      });
      
      setLastUpdated(new Date());
    } catch (err) {
      console.error('Failed to load analytics data:', err);
      setError(err instanceof Error ? err.message : 'Failed to load analytics data');
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  };

  // Initial data load
  useEffect(() => {
    loadAnalyticsData();
  }, [dateRange]);

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
  }, [isConnected, data, requestAnalyticsUpdate]);

  const handleDateRangeChange = (newDateRange: { startDate: Date; endDate: Date }) => {
    setDateRange(newDateRange);
  };

  const handleRefresh = () => {
    loadAnalyticsData(false);
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
      <div className="min-h-screen bg-gray-50 p-6">
        <div className="max-w-7xl mx-auto">
          <div className="bg-red-50 border border-red-200 rounded-lg p-6">
            <div className="flex items-center">
              <div className="flex-shrink-0">
                <span className="text-red-500 text-xl">⚠️</span>
              </div>
              <div className="ml-3">
                <h3 className="text-sm font-medium text-red-800">Error Loading Analytics</h3>
                <p className="mt-1 text-sm text-red-700">{error}</p>
                <button
                  onClick={() => loadAnalyticsData()}
                  className="mt-2 px-3 py-1 bg-red-600 text-white rounded text-sm hover:bg-red-700"
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
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <div className="bg-white shadow-sm border-b border-gray-200">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between py-4">
            <div>
              <h1 className="text-2xl font-bold text-gray-900">Analytics Dashboard</h1>
              <p className="text-sm text-gray-500">
                Real-time insights for {user?.account?.name || 'your business'}
              </p>
            </div>
            
            <div className="flex items-center space-x-4">
              {/* Real-time indicator */}
              <div className="flex items-center space-x-2">
                <div className={`w-2 h-2 rounded-full ${isConnected ? 'bg-green-500' : 'bg-gray-400'}`} />
                <span className="text-xs text-gray-500">
                  {isConnected ? 'Real-time' : 'Offline'}
                </span>
              </div>

              {/* Last updated */}
              {lastUpdated && (
                <span className="text-xs text-gray-500">
                  Updated {lastUpdated.toLocaleTimeString()}
                </span>
              )}

              {/* Refresh button */}
              <button
                onClick={handleRefresh}
                disabled={refreshing}
                className="p-2 text-gray-500 hover:text-gray-700 disabled:opacity-50"
                title="Refresh data"
              >
                <span className={`text-lg ${refreshing ? 'animate-spin' : ''}`}>🔄</span>
              </button>

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
                    ? 'border-blue-500 text-blue-600'
                    : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
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