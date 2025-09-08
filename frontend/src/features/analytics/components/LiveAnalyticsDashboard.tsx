import React, { useState, useEffect, useCallback } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { Button } from '@/shared/components/ui/Button';
import { 
  TrendingUp, TrendingDown, DollarSign, Users, 
  BarChart3, Activity, Download, 
  RefreshCw, AlertTriangle, Target, Zap, Lock
} from 'lucide-react';
import { analyticsService, RevenueData, GrowthData, ChurnData, CustomerData } from '@/features/analytics/services/analyticsService';
import { useNotification } from '@/shared/hooks/useNotification';
import { hasPermissions } from '@/shared/utils/permissionUtils';

interface LiveAnalyticsDashboardProps {
  accountId?: string;
  autoRefresh?: boolean;
  refreshInterval?: number; // in seconds
}

interface MetricCardProps {
  title: string;
  value: string | number;
  change?: number | null;
  changeLabel?: string;
  icon: React.ReactNode;
  color?: 'primary' | 'success' | 'warning' | 'error' | 'info';
  loading?: boolean;
}

interface LiveMetric {
  current_revenue: number;
  active_subscriptions: number;
  new_subscriptions_today: number;
  churn_rate_this_month: number;
  mrr: number;
  arr: number;
  growth_rate: number;
  customer_count: number;
  conversion_rate: number;
  ltv: number;
  last_updated: string;
}

const MetricCard: React.FC<MetricCardProps> = ({
  title,
  value,
  change,
  changeLabel,
  icon,
  color = 'primary',
  loading = false
}) => {
  const colorClasses = {
    primary: 'bg-theme-interactive-primary bg-opacity-10 text-theme-interactive-primary',
    success: 'bg-theme-success bg-opacity-10 text-theme-success',
    warning: 'bg-theme-warning bg-opacity-10 text-theme-warning',
    error: 'bg-theme-error bg-opacity-10 text-theme-error',
    info: 'bg-theme-info bg-opacity-10 text-theme-info'
  };

  const changeColor = change !== undefined && change !== null && typeof change === 'number' ? (
    change >= 0 ? 'text-theme-success' : 'text-theme-error'
  ) : 'text-theme-secondary';

  if (loading) {
    return (
      <div className="bg-theme-surface rounded-lg border border-theme p-6">
        <div className="flex items-center justify-between">
          <div className="space-y-2">
            <div className="h-4 bg-theme-background rounded animate-pulse w-24"></div>
            <div className="h-8 bg-theme-background rounded animate-pulse w-16"></div>
            <div className="h-3 bg-theme-background rounded animate-pulse w-20"></div>
          </div>
          <div className={`w-12 h-12 rounded-lg flex items-center justify-center ${colorClasses[color as keyof typeof colorClasses]}`}>
            {icon}
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="bg-theme-surface rounded-lg border border-theme p-6 hover:shadow-lg transition-shadow">
      <div className="flex items-center justify-between">
        <div>
          <p className="text-sm text-theme-secondary mb-1">{title}</p>
          <p className="text-2xl font-bold text-theme-primary">
            {typeof value === 'number' ? value.toLocaleString() : value}
          </p>
          {change !== undefined && change !== null && typeof change === 'number' && (
            <div className={`flex items-center gap-1 text-sm ${changeColor} mt-1`}>
              {change >= 0 ? (
                <TrendingUp className="w-4 h-4" />
              ) : (
                <TrendingDown className="w-4 h-4" />
              )}
              <span>
                {Math.abs(change).toFixed(1)}% {changeLabel || 'vs last period'}
              </span>
            </div>
          )}
        </div>
        <div className={`w-12 h-12 rounded-lg flex items-center justify-center ${colorClasses[color as keyof typeof colorClasses]}`}>
          {icon}
        </div>
      </div>
    </div>
  );
};

export const LiveAnalyticsDashboard: React.FC<LiveAnalyticsDashboardProps> = ({
  accountId,
  autoRefresh = true,
  refreshInterval = 30
}) => {
  const { user } = useSelector((state: RootState) => state.auth);
  const [liveMetrics, setLiveMetrics] = useState<LiveMetric | null>(null);
  const [revenueData, setRevenueData] = useState<RevenueData | null>(null);
  const [growthData, setGrowthData] = useState<GrowthData | null>(null);
  const [churnData, setChurnData] = useState<ChurnData | null>(null);
  const [customerData, setCustomerData] = useState<CustomerData | null>(null);
  const [loading, setLoading] = useState(true);
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [selectedTimeRange, setSelectedTimeRange] = useState('30d');
  const [error, setError] = useState<string | null>(null);
  
  const { showNotification } = useNotification();
  
  // Check permissions before loading analytics
  const canViewAnalytics = hasPermissions(user, ['analytics.read']);
  const canExportAnalytics = hasPermissions(user, ['analytics.export']);

  const getDateRange = useCallback((range: string) => {
    const endDate = new Date();
    const startDate = new Date();
    
    switch (range) {
      case '7d':
        startDate.setDate(endDate.getDate() - 7);
        break;
      case '30d':
        startDate.setDate(endDate.getDate() - 30);
        break;
      case '90d':
        startDate.setDate(endDate.getDate() - 90);
        break;
      case '1y':
        startDate.setFullYear(endDate.getFullYear() - 1);
        break;
      default:
        startDate.setDate(endDate.getDate() - 30);
    }
    
    return {
      startDate: startDate.toISOString().split('T')[0],
      endDate: endDate.toISOString().split('T')[0]
    };
  }, []);

  const loadAnalyticsData = useCallback(async (showSpinner = true) => {
    // Don't load if user doesn't have permission
    if (!canViewAnalytics) {
      setLoading(false);
      setIsRefreshing(false);
      return;
    }
    
    try {
      if (showSpinner) setLoading(true);
      setIsRefreshing(!showSpinner);
      setError(null);

      const { startDate, endDate } = getDateRange(selectedTimeRange);

      // Load all analytics data in parallel
      const [liveResponse, revenueResponse, growthResponse, churnResponse, customerResponse] = await Promise.all([
        analyticsService.getLiveAnalytics(accountId),
        analyticsService.getRevenueAnalytics(startDate, endDate, accountId),
        analyticsService.getGrowthAnalytics(startDate, endDate, accountId),
        analyticsService.getChurnAnalytics(startDate, endDate, accountId),
        analyticsService.getCustomerAnalytics(startDate, endDate, accountId)
      ]);

      if (liveResponse.success) {
        setLiveMetrics(liveResponse.data);
      }
      if (revenueResponse.success) {
        setRevenueData(revenueResponse.data);
      }
      if (growthResponse.success) {
        setGrowthData(growthResponse.data);
      }
      if (churnResponse.success) {
        setChurnData(churnResponse.data);
      }
      if (customerResponse.success) {
        setCustomerData(customerResponse.data);
      }

      setLastUpdated(new Date());
    } catch (error: any) {
      setError('Failed to load analytics data');
      showNotification('Failed to load analytics data', 'error');
    } finally {
      setLoading(false);
      setIsRefreshing(false);
    }
  }, [accountId, selectedTimeRange, getDateRange, showNotification, canViewAnalytics]);

  // Auto-refresh effect
  useEffect(() => {
    loadAnalyticsData();
    
    // Temporarily disable auto-refresh to debug page refresh issues
    // if (autoRefresh) {
    //   const interval = setInterval(() => {
    //     // Only refresh if page is visible to prevent excessive API calls
    //     if (!document.hidden) {
    //       loadAnalyticsData(false); // Don't show spinner for auto-refresh
    //     }
    //   }, refreshInterval * 1000);
    //   
    //   return () => clearInterval(interval);
    // }
    
    console.log('LiveAnalyticsDashboard: Auto-refresh disabled for debugging'); // Debug log
  }, [loadAnalyticsData, autoRefresh, refreshInterval]);

  const handleExport = async (format: 'csv' | 'pdf') => {
    if (!canExportAnalytics) {
      showNotification('You do not have permission to export analytics', 'error');
      return;
    }
    
    try {
      const { startDate, endDate } = getDateRange(selectedTimeRange);
      await analyticsService.exportAnalytics(
        format, 
        'comprehensive',
        { startDate: new Date(startDate), endDate: new Date(endDate) },
        accountId
      );
      showNotification(`Analytics exported as ${format.toUpperCase()}`, 'success');
    } catch (error) {
      showNotification('Failed to export analytics', 'error');
    }
  };

  const formatCurrency = (amount: number) => {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD',
    }).format(amount / 100);
  };

  const formatPercentage = (value: number | null | undefined) => {
    if (value === null || value === undefined || typeof value !== 'number') {
      return '0.00%';
    }
    return `${value.toFixed(2)}%`;
  };

  // Show access denied if user doesn't have permission
  if (!canViewAnalytics) {
    return (
      <div className="text-center py-12">
        <Lock className="w-12 h-12 text-theme-secondary mx-auto mb-4" />
        <h3 className="text-lg font-medium text-theme-primary mb-2">Analytics Access Restricted</h3>
        <p className="text-theme-secondary">You need analytics.read permission to access this dashboard</p>
      </div>
    );
  }

  if (error && !liveMetrics) {
    return (
      <div className="text-center py-12">
        <AlertTriangle className="w-12 h-12 text-theme-error mx-auto mb-4" />
        <h3 className="text-lg font-medium text-theme-primary mb-2">Failed to Load Analytics</h3>
        <p className="text-theme-secondary mb-4">{error}</p>
        <Button variant="outline" onClick={() => loadAnalyticsData()}
          className="px-4 py-2 bg-theme-interactive-primary text-white rounded-md hover:bg-theme-interactive-primary-hover"
        >
          Retry
        </Button>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row gap-4 justify-between items-start sm:items-center">
        <div>
          <h2 className="text-2xl font-bold text-theme-primary">Live Analytics</h2>
          <p className="text-theme-secondary">
            Real-time insights into your subscription business
            {lastUpdated && (
              <span className="ml-2 text-xs">
                Last updated: {lastUpdated.toLocaleTimeString()}
              </span>
            )}
          </p>
        </div>
        
        <div className="flex items-center gap-3">
          {/* Time Range Selector */}
          <select
            value={selectedTimeRange}
            onChange={(e) => setSelectedTimeRange(e.target.value)}
            className="px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
          >
            <option value="7d">Last 7 days</option>
            <option value="30d">Last 30 days</option>
            <option value="90d">Last 90 days</option>
            <option value="1y">Last year</option>
          </select>
          
          {/* Refresh Button */}
          <Button variant="outline" onClick={() => loadAnalyticsData()}
            disabled={isRefreshing}
            className="p-2 border border-theme rounded-md text-theme-primary hover:bg-theme-surface disabled:opacity-50 disabled:cursor-not-allowed"
            title="Refresh Data"
          >
            <RefreshCw className={`w-4 h-4 ${isRefreshing ? 'animate-spin' : ''}`} />
          </Button>
          
          {/* Export Dropdown */}
          <div className="relative">
            <Button variant="outline" onClick={() => handleExport('csv')}
              className="px-3 py-2 border border-theme rounded-md text-theme-primary hover:bg-theme-surface flex items-center gap-2"
            >
              <Download className="w-4 h-4" />
              Export CSV
            </Button>
          </div>
        </div>
      </div>

      {/* Live Metrics Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        <MetricCard
          title="Monthly Recurring Revenue"
          value={liveMetrics ? formatCurrency(liveMetrics.mrr) : ''}
          change={growthData?.compound_monthly_growth_rate}
          changeLabel="growth rate"
          icon={<DollarSign className="w-6 h-6" />}
          color="success"
          loading={loading}
        />
        
        <MetricCard
          title="Active Subscriptions"
          value={liveMetrics?.active_subscriptions || 0}
          change={revenueData ? ((revenueData.current_metrics.active_subscriptions - (revenueData.historical_data[0]?.active_subscriptions || 0)) / (revenueData.historical_data[0]?.active_subscriptions || 1)) * 100 : undefined}
          icon={<Users className="w-6 h-6" />}
          color="primary"
          loading={loading}
        />
        
        <MetricCard
          title="Customer Churn Rate"
          value={churnData ? formatPercentage(churnData.current_metrics.customer_churn_rate) : ''}
          change={churnData?.churn_trend && churnData.churn_trend.length > 1 ? (
            churnData.churn_trend[churnData.churn_trend.length - 1]?.customer_churn_rate! -
            churnData.churn_trend[churnData.churn_trend.length - 2]?.customer_churn_rate!
          ) : undefined}
          icon={<TrendingDown className="w-6 h-6" />}
          color={churnData?.insights.churn_risk_level === 'high' ? 'error' : churnData?.insights.churn_risk_level === 'medium' ? 'warning' : 'success'}
          loading={loading}
        />
        
        <MetricCard
          title="Average LTV"
          value={customerData ? formatCurrency(customerData.current_metrics.ltv) : ''}
          change={customerData?.customer_growth_trend && customerData.customer_growth_trend.length > 1 ? (
            ((customerData.customer_growth_trend[customerData.customer_growth_trend.length - 1]?.ltv! -
              customerData.customer_growth_trend[customerData.customer_growth_trend.length - 2]?.ltv!) /
              customerData.customer_growth_trend[customerData.customer_growth_trend.length - 2]?.ltv!) * 100
          ) : undefined}
          icon={<Target className="w-6 h-6" />}
          color="info"
          loading={loading}
        />
      </div>

      {/* Secondary Metrics */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        <MetricCard
          title="New Subscriptions Today"
          value={liveMetrics?.new_subscriptions_today || 0}
          icon={<Zap className="w-6 h-6" />}
          color="success"
          loading={loading}
        />
        
        <MetricCard
          title="Annual Recurring Revenue"
          value={liveMetrics ? formatCurrency(liveMetrics.arr) : ''}
          icon={<BarChart3 className="w-6 h-6" />}
          color="primary"
          loading={loading}
        />
        
        <MetricCard
          title="Average Revenue Per User"
          value={customerData ? formatCurrency(customerData.current_metrics.arpu) : ''}
          icon={<Activity className="w-6 h-6" />}
          color="info"
          loading={loading}
        />
      </div>

      {/* Insights and Alerts */}
      {churnData?.insights.churn_risk_level === 'high' && churnData.insights.recommended_actions.length > 0 && (
        <div className="bg-theme-error-background border border-theme-error rounded-lg p-4">
          <div className="flex items-start gap-3">
            <AlertTriangle className="w-5 h-5 text-theme-error mt-0.5" />
            <div>
              <h4 className="font-medium text-theme-error mb-2">High Churn Risk Detected</h4>
              <ul className="list-disc list-inside text-sm text-theme-error space-y-1">
                {churnData.insights.recommended_actions.map((action, index) => (
                  <li key={index}>{action}</li>
                ))}
              </ul>
            </div>
          </div>
        </div>
      )}

      {/* Growth Forecast */}
      {growthData?.forecasting && (
        <div className="bg-theme-success-background border border-theme-success rounded-lg p-4">
          <div className="flex items-start gap-3">
            <TrendingUp className="w-5 h-5 text-theme-success mt-0.5" />
            <div>
              <h4 className="font-medium text-theme-success mb-2">Growth Forecast</h4>
              <p className="text-sm text-theme-success">
                Projected MRR for next month: <span className="font-semibold">
                  {formatCurrency(growthData.forecasting.next_month_projection)}
                </span>
              </p>
              <p className="text-xs text-theme-success mt-1">
                Confidence interval: {growthData.forecasting.confidence_interval}
              </p>
            </div>
          </div>
        </div>
      )}

      {/* Auto-refresh indicator */}
      {autoRefresh && (
        <div className="text-center">
          <p className="text-xs text-theme-secondary flex items-center justify-center gap-2">
            <Activity className="w-3 h-3" />
            Auto-refreshing every {refreshInterval} seconds
          </p>
        </div>
      )}
    </div>
  );
};

export default LiveAnalyticsDashboard;