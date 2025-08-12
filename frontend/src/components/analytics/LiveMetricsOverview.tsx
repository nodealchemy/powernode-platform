import React, { useState, useEffect } from 'react';
import { 
  DollarSign, 
  Users, 
  TrendingUp, 
  TrendingDown, 
  Activity,
  Clock,
  AlertCircle,
  Wifi,
  WifiOff
} from 'lucide-react';
import { useAnalyticsWebSocket } from '../../hooks/useAnalyticsWebSocket';
import { analyticsService } from '../../services/analyticsService';
import { LoadingSpinner } from '../ui/LoadingSpinner';

interface LiveMetrics {
  current_metrics: {
    mrr: number;
    arr: number;
    active_customers: number;
    churn_rate: number;
    arpu: number;
    growth_rate: number;
  };
  today_activity: {
    new_subscriptions: number;
    cancelled_subscriptions: number;
    payments_processed: number;
    failed_payments: number;
    revenue_today: number;
  };
  weekly_trend: Array<{
    date: string;
    new_subscriptions: number;
    revenue: number;
    payments_count: number;
  }>;
  last_updated: string;
  account_id?: string;
}

interface LiveMetricsOverviewProps {
  className?: string;
  accountId?: string;
  showTodayActivity?: boolean;
  showWeeklyTrend?: boolean;
  updateInterval?: number;
}

export const LiveMetricsOverview: React.FC<LiveMetricsOverviewProps> = ({
  className = '',
  accountId,
  showTodayActivity = true,
  showWeeklyTrend = false,
  updateInterval = 30000
}) => {
  const [metrics, setMetrics] = useState<LiveMetrics | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null);
  const [isLive, setIsLive] = useState(false);

  // WebSocket connection for real-time updates
  const { requestAnalyticsUpdate, isConnected } = useAnalyticsWebSocket({
    accountId,
    autoRequest: true,
    requestInterval: updateInterval,
    onAnalyticsUpdate: (data) => {
      console.log('Live metrics update received:', data);
      if (data.current_metrics) {
        setMetrics(prevMetrics => {
          if (!prevMetrics) return null;
          
          return {
            ...prevMetrics,
            current_metrics: {
              ...prevMetrics.current_metrics,
              ...data.current_metrics
            },
            today_activity: data.today_activity || prevMetrics.today_activity,
            weekly_trend: data.weekly_trend || prevMetrics.weekly_trend,
            last_updated: data.timestamp || new Date().toISOString(),
            account_id: data.account_id || prevMetrics.account_id
          };
        });
        setLastUpdated(new Date());
        setIsLive(true);
      }
    },
    onError: (errorMessage) => {
      console.error('Live metrics WebSocket error:', errorMessage);
      setError(errorMessage);
      setIsLive(false);
    }
  });

  // Initial data load
  useEffect(() => {
    const loadInitialData = async () => {
      try {
        setLoading(true);
        setError(null);
        
        const response = await analyticsService.getLiveAnalytics(accountId);
        if (response.success && response.data) {
          setMetrics(response.data);
          setLastUpdated(new Date());
          setIsLive(true);
        } else {
          setError(response.error || 'Failed to load live metrics');
        }
      } catch (err) {
        console.error('Failed to load live metrics:', err);
        setError('Failed to load live metrics');
      } finally {
        setLoading(false);
      }
    };

    loadInitialData();
  }, [accountId]);

  // Connection status indicator
  useEffect(() => {
    setIsLive(isConnected);
  }, [isConnected]);

  // Manual refresh function
  const handleRefresh = () => {
    if (isConnected) {
      requestAnalyticsUpdate();
    } else {
      // Fallback to API call if WebSocket not connected
      analyticsService.getLiveAnalytics(accountId)
        .then(response => {
          if (response.success && response.data) {
            setMetrics(response.data);
            setLastUpdated(new Date());
          }
        })
        .catch(err => {
          console.error('Manual refresh failed:', err);
          setError('Failed to refresh metrics');
        });
    }
  };

  const formatCurrency = (amount: number) => {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD',
      minimumFractionDigits: 0,
      maximumFractionDigits: 0
    }).format(amount);
  };

  const formatPercentage = (percentage: number) => {
    return `${percentage >= 0 ? '+' : ''}${percentage.toFixed(1)}%`;
  };

  if (loading) {
    return (
      <div className={`bg-theme-surface rounded-lg border border-theme p-6 ${className}`}>
        <div className="flex justify-center">
          <LoadingSpinner size="lg" />
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className={`bg-theme-surface rounded-lg border border-theme p-6 ${className}`}>
        <div className="flex items-center gap-3 text-theme-error">
          <AlertCircle className="w-5 h-5" />
          <span>{error}</span>
          <button 
            onClick={handleRefresh}
            className="ml-auto px-3 py-1 bg-theme-interactive-primary text-white rounded text-sm hover:bg-theme-interactive-primary-hover"
          >
            Retry
          </button>
        </div>
      </div>
    );
  }

  if (!metrics) {
    return (
      <div className={`bg-theme-surface rounded-lg border border-theme p-6 ${className}`}>
        <div className="text-center text-theme-secondary">
          No live metrics data available
        </div>
      </div>
    );
  }

  return (
    <div className={`bg-theme-surface rounded-lg border border-theme overflow-hidden ${className}`}>
      {/* Header */}
      <div className="px-6 py-4 border-b border-theme">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <h3 className="text-lg font-semibold text-theme-primary">Live Metrics</h3>
            <div className="flex items-center gap-1">
              {isLive ? (
                <Wifi className="w-4 h-4 text-theme-success" />
              ) : (
                <WifiOff className="w-4 h-4 text-theme-error" />
              )}
              <span className={`text-xs ${isLive ? 'text-theme-success' : 'text-theme-error'}`}>
                {isLive ? 'Live' : 'Disconnected'}
              </span>
            </div>
          </div>
          
          <div className="flex items-center gap-3">
            {lastUpdated && (
              <div className="flex items-center gap-1 text-xs text-theme-secondary">
                <Clock className="w-3 h-3" />
                <span>Updated {lastUpdated.toLocaleTimeString()}</span>
              </div>
            )}
            <button
              onClick={handleRefresh}
              disabled={loading}
              className="p-2 text-theme-secondary hover:text-theme-primary transition-colors duration-200"
              title="Refresh metrics"
            >
              <Activity className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
            </button>
          </div>
        </div>
      </div>

      {/* Key Metrics Grid */}
      <div className="p-6">
        <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-4 mb-6">
          {/* MRR */}
          <div className="bg-theme-background rounded-lg p-4">
            <div className="flex items-center gap-2 mb-2">
              <DollarSign className="w-4 h-4 text-theme-success" />
              <span className="text-xs font-medium text-theme-secondary uppercase tracking-wider">MRR</span>
            </div>
            <div className="text-xl font-bold text-theme-primary">
              {formatCurrency(metrics.current_metrics.mrr)}
            </div>
          </div>

          {/* ARR */}
          <div className="bg-theme-background rounded-lg p-4">
            <div className="flex items-center gap-2 mb-2">
              <DollarSign className="w-4 h-4 text-theme-interactive-primary" />
              <span className="text-xs font-medium text-theme-secondary uppercase tracking-wider">ARR</span>
            </div>
            <div className="text-xl font-bold text-theme-primary">
              {formatCurrency(metrics.current_metrics.arr)}
            </div>
          </div>

          {/* Active Customers */}
          <div className="bg-theme-background rounded-lg p-4">
            <div className="flex items-center gap-2 mb-2">
              <Users className="w-4 h-4 text-theme-interactive-primary" />
              <span className="text-xs font-medium text-theme-secondary uppercase tracking-wider">Customers</span>
            </div>
            <div className="text-xl font-bold text-theme-primary">
              {metrics.current_metrics.active_customers.toLocaleString()}
            </div>
          </div>

          {/* Growth Rate */}
          <div className="bg-theme-background rounded-lg p-4">
            <div className="flex items-center gap-2 mb-2">
              {metrics.current_metrics.growth_rate >= 0 ? (
                <TrendingUp className="w-4 h-4 text-theme-success" />
              ) : (
                <TrendingDown className="w-4 h-4 text-theme-error" />
              )}
              <span className="text-xs font-medium text-theme-secondary uppercase tracking-wider">Growth</span>
            </div>
            <div className={`text-xl font-bold ${
              metrics.current_metrics.growth_rate >= 0 ? 'text-theme-success' : 'text-theme-error'
            }`}>
              {formatPercentage(metrics.current_metrics.growth_rate)}
            </div>
          </div>

          {/* ARPU */}
          <div className="bg-theme-background rounded-lg p-4">
            <div className="flex items-center gap-2 mb-2">
              <DollarSign className="w-4 h-4 text-theme-warning" />
              <span className="text-xs font-medium text-theme-secondary uppercase tracking-wider">ARPU</span>
            </div>
            <div className="text-xl font-bold text-theme-primary">
              {formatCurrency(metrics.current_metrics.arpu)}
            </div>
          </div>

          {/* Churn Rate */}
          <div className="bg-theme-background rounded-lg p-4">
            <div className="flex items-center gap-2 mb-2">
              <TrendingDown className="w-4 h-4 text-theme-error" />
              <span className="text-xs font-medium text-theme-secondary uppercase tracking-wider">Churn</span>
            </div>
            <div className="text-xl font-bold text-theme-error">
              {metrics.current_metrics.churn_rate.toFixed(1)}%
            </div>
          </div>
        </div>

        {/* Today's Activity */}
        {showTodayActivity && (
          <div className="mb-6">
            <h4 className="text-md font-semibold text-theme-primary mb-3">Today's Activity</h4>
            <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
              <div className="bg-theme-background rounded p-3">
                <div className="text-sm text-theme-secondary">New Subscriptions</div>
                <div className="text-lg font-semibold text-theme-success">
                  {metrics.today_activity.new_subscriptions}
                </div>
              </div>
              <div className="bg-theme-background rounded p-3">
                <div className="text-sm text-theme-secondary">Cancellations</div>
                <div className="text-lg font-semibold text-theme-error">
                  {metrics.today_activity.cancelled_subscriptions}
                </div>
              </div>
              <div className="bg-theme-background rounded p-3">
                <div className="text-sm text-theme-secondary">Payments</div>
                <div className="text-lg font-semibold text-theme-success">
                  {metrics.today_activity.payments_processed}
                </div>
              </div>
              <div className="bg-theme-background rounded p-3">
                <div className="text-sm text-theme-secondary">Failed Payments</div>
                <div className="text-lg font-semibold text-theme-error">
                  {metrics.today_activity.failed_payments}
                </div>
              </div>
              <div className="bg-theme-background rounded p-3">
                <div className="text-sm text-theme-secondary">Revenue Today</div>
                <div className="text-lg font-semibold text-theme-primary">
                  {formatCurrency(metrics.today_activity.revenue_today)}
                </div>
              </div>
            </div>
          </div>
        )}

        {/* Weekly Trend */}
        {showWeeklyTrend && metrics.weekly_trend.length > 0 && (
          <div>
            <h4 className="text-md font-semibold text-theme-primary mb-3">7-Day Trend</h4>
            <div className="bg-theme-background rounded-lg p-4">
              <div className="grid grid-cols-7 gap-2">
                {metrics.weekly_trend.map((day, index) => (
                  <div key={index} className="text-center">
                    <div className="text-xs text-theme-secondary mb-1">
                      {new Date(day.date).toLocaleDateString('en-US', { weekday: 'short' })}
                    </div>
                    <div className="space-y-1">
                      <div className="text-sm font-semibold text-theme-primary">
                        {formatCurrency(day.revenue)}
                      </div>
                      <div className="text-xs text-theme-secondary">
                        {day.new_subscriptions} subs
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};