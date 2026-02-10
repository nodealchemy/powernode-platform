import { useState, useEffect, useCallback, useRef } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { Button } from '@/shared/components/ui/Button';
import { 
  DollarSign, 
  Users, 
  TrendingUp, 
  TrendingDown, 
  Activity,
  Clock,
  AlertCircle,
  Wifi,
  WifiOff,
  Lock
} from 'lucide-react';
import { useAnalyticsWebSocket } from '@/shared/hooks/useAnalyticsWebSocket';
import { analyticsService } from '@enterprise/features/business/analytics/services/analyticsService';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { hasPermissions } from '@/shared/utils/permissionUtils';

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
  const { user } = useSelector((state: RootState) => state.auth);
  const [metrics, setMetrics] = useState<LiveMetrics | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null);
  const [isLive, setIsLive] = useState(false);
  const [isReconnecting, setIsReconnecting] = useState(false);
  const lastUpdateTimeRef = useRef<number>(0);
  
  // Check permissions before loading analytics
  const canViewAnalytics = hasPermissions(user, ['analytics.read']);

  // Stable callbacks to prevent WebSocket reconnections
  const handleAnalyticsUpdate = useCallback((data: unknown) => {
    const analyticsData = data as {
      current_metrics?: {
        mrr: number;
        arr: number;
        active_customers: number;
        churn_rate: number;
        arpu: number;
        growth_rate: number;
      };
      today_activity?: {
        new_subscriptions: number;
        cancelled_subscriptions: number;
        payments_processed: number;
        failed_payments: number;
        revenue_today: number;
      };
      weekly_trend?: Array<{
        date: string;
        new_subscriptions: number;
        revenue: number;
        payments_count: number;
      }>;
      timestamp?: string;
      account_id?: string
    };
    if (analyticsData.current_metrics) {
      // Throttle updates to prevent excessive re-renders
      const now = Date.now();
      if (now - lastUpdateTimeRef.current < 5000) { // Minimum 5 second gap between updates
        return;
      }
      lastUpdateTimeRef.current = now;
      
      // Always clear errors when we receive valid data
      setError(null);
      setLastUpdated(new Date());
      setIsLive(true);
      setIsReconnecting(false); // Clear reconnecting state
      
      setMetrics(prevMetrics => {
        // If we don't have initial metrics, create them from the WebSocket data
        if (!prevMetrics) {
          return {
            current_metrics: analyticsData.current_metrics || { mrr: 0, arr: 0, active_customers: 0, churn_rate: 0, arpu: 0, growth_rate: 0 },
            today_activity: analyticsData.today_activity || {
              new_subscriptions: 0,
              cancelled_subscriptions: 0,
              payments_processed: 0,
              failed_payments: 0,
              revenue_today: 0
            },
            weekly_trend: analyticsData.weekly_trend || [],
            last_updated: analyticsData.timestamp || new Date().toISOString(),
            account_id: analyticsData.account_id
          };
        }
        
        // Update existing metrics
        return {
          ...prevMetrics,
          current_metrics: {
            ...prevMetrics.current_metrics,
            ...analyticsData.current_metrics
          },
          today_activity: analyticsData.today_activity || prevMetrics.today_activity,
          weekly_trend: analyticsData.weekly_trend || prevMetrics.weekly_trend,
          last_updated: analyticsData.timestamp || new Date().toISOString(),
          account_id: analyticsData.account_id || prevMetrics.account_id
        };
      });
    }
  }, []);

  const handleWebSocketError = useCallback((errorMessage: string) => {
    // Provide more user-friendly error messages
    let userFriendlyError = errorMessage;
    if (errorMessage.includes('unauthorized') || errorMessage.includes('Unauthorized')) {
      userFriendlyError = 'Authentication required. Please refresh the page and log in again.';
    } else if (errorMessage.includes('network') || errorMessage.includes('connection')) {
      userFriendlyError = 'Network connection error. Please check your internet connection.';
    } else if (errorMessage.includes('rate limit')) {
      userFriendlyError = 'Too many requests. Please wait a moment before retrying.';
    } else if (errorMessage.includes('Failed to fetch')) {
      userFriendlyError = 'Unable to connect to server. Please check if the backend is running.';
    }
    
    // Set reconnecting state if the message indicates reconnection
    if (errorMessage.includes('Attempting to reconnect')) {
      setIsReconnecting(true);
      
      // Clear reconnecting state after 30 seconds if no connection
      setTimeout(() => {
        setIsReconnecting(false);
      }, 30000);
    }
    
    setError(userFriendlyError);
    setIsLive(false);
  }, []);

  // WebSocket connection for real-time updates
  const { requestAnalyticsUpdate, isConnected } = useAnalyticsWebSocket({
    accountId,
    onAnalyticsUpdate: handleAnalyticsUpdate,
    onError: handleWebSocketError
  });

  // Monitor WebSocket connection status
  useEffect(() => {
    if (!isConnected) {
      setIsLive(false);
    }
  }, [isConnected]);

  // Auto-request analytics updates when connected - but only if we have metrics already
  useEffect(() => {
    if (!isConnected || !metrics) return;

    // Temporarily disable auto-refresh to debug page refresh issues
    // const interval = setInterval(() => {
    //   requestAnalyticsUpdate();
    // }, updateInterval);

    // Auto-refresh disabled for debugging
    // const interval = null; // Placeholder to avoid breaking the cleanup

    // return () => clearInterval(interval); // Commented out with the interval
  }, [isConnected, requestAnalyticsUpdate, updateInterval, metrics]); // Removed 'metrics' dependency to prevent restart when data changes

  // Initial data load - only run once on mount and only if user has permission
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
          const errorMsg = response.error || 'Failed to load live metrics';
          setError(errorMsg);
        }
      } catch (err) {
        // Provide more specific error messages for API failures
        let userError = 'Failed to load live metrics';
        if (err instanceof Error) {
          if (err.message.includes('401') || err.message.includes('unauthorized')) {
            userError = 'Authentication required. Please refresh the page and log in again.';
          } else if (err.message.includes('403')) {
            userError = 'Access denied. You may not have permission to view analytics.';
          } else if (err.message.includes('404')) {
            userError = 'Analytics service not found. Please contact support.';
          } else if (err.message.includes('500')) {
            userError = 'Server error occurred. Please try again later.';
          } else if (err.message.includes('NetworkError') || err.message.includes('fetch')) {
            userError = 'Network error. Please check your connection and try again.';
          }
        }

        setError(userError);
      } finally {
        setLoading(false);
      }
    };

    // Only load if user has permission and we don't have metrics data
    if (canViewAnalytics && !metrics) {
      loadInitialData();
    } else if (!canViewAnalytics) {
      // If no permission, set loading to false immediately
      setLoading(false);
    }
     
  }, [accountId, canViewAnalytics]); // Add permission dependency

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
        .catch(_err => {
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

  // Show access denied if user doesn't have permission
  if (!canViewAnalytics) {
    return (
      <div className={`bg-theme-surface rounded-lg border border-theme p-6 ${className}`}>
        <div className="flex items-center justify-center gap-3 text-theme-secondary">
          <Lock className="w-5 h-5" />
          <span>Analytics access requires proper permissions</span>
        </div>
      </div>
    );
  }

  if (loading) {
    return (
      <div className={`bg-theme-surface rounded-lg border border-theme p-6 ${className}`}>
        <div className="flex justify-center">
          <LoadingSpinner size="lg" />
        </div>
      </div>
    );
  }

  // Prioritize data display over error state
  if (!metrics) {
    // Only show error if we have no metrics data at all
    if (error) {
      return (
        <div className={`bg-theme-surface rounded-lg border border-theme p-6 ${className}`}>
          <div className="flex items-center gap-3 text-theme-error">
            <AlertCircle className="w-5 h-5" />
            <span>{error}</span>
            {isReconnecting && (
              <div className="flex items-center gap-2 ml-4">
                <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-theme-warning"></div>
                <span className="text-sm text-theme-warning">Reconnecting...</span>
              </div>
            )}
            <Button onClick={handleRefresh} disabled={isReconnecting} variant="primary">
              {isReconnecting ? 'Connecting...' : 'Retry'}
            </Button>
          </div>
        </div>
      );
    }
    
    // No error and no data - show loading or no data message
    return (
      <div className={`bg-theme-surface rounded-lg border border-theme p-6 ${className}`}>
        <div className="text-center text-theme-secondary">
          {isReconnecting ? 'Connecting to live metrics...' : 'No live metrics data available'}
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
              {isConnected && isLive ? (
                <Wifi className="w-4 h-4 text-theme-success" />
              ) : isConnected ? (
                <Activity className="w-4 h-4 text-theme-warning animate-pulse" />
              ) : (
                <WifiOff className="w-4 h-4 text-theme-error" />
              )}
              <span className={`text-xs ${isConnected && isLive ? 'text-theme-success' : isConnected ? 'text-theme-warning' : 'text-theme-error'}`}>
                {isConnected && isLive ? 'Live' : isConnected ? 'Connected' : 'Disconnected'}
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
            <Button onClick={handleRefresh} disabled={loading} variant="outline">
              <Activity className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
            </Button>
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