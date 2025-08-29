import React, { useMemo } from 'react';
import { 
  BarChart3,
  TrendingUp,
  TrendingDown,
  Activity,
  Globe,
  CheckCircle,
  AlertTriangle,
  Clock,
  RefreshCw,
  Zap,
  Target,
  Timer
} from 'lucide-react';
import { WebhookStats as WebhookStatsType, DetailedWebhookStats } from '@/features/webhooks/services/webhooksApi';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';

interface WebhookStatsProps {
  stats: WebhookStatsType | null;
  detailedStats: DetailedWebhookStats | null;
  loading: boolean;
}

const WebhookStats: React.FC<WebhookStatsProps> = ({
  stats,
  detailedStats,
  loading
}) => {
  // Fixed: Move useMemo to top to comply with Rules of Hooks (no hooks after early returns)
  const { totalDeliveries, successRate } = useMemo(() => {
    if (!stats) return { totalDeliveries: 0, successRate: 0 };
    const total = stats.successful_deliveries_today + stats.failed_deliveries_today;
    const rate = total === 0 ? 0 : Math.round((stats.successful_deliveries_today / total) * 100);
    return { totalDeliveries: total, successRate: rate };
  }, [stats?.successful_deliveries_today, stats?.failed_deliveries_today]);

  if (loading) {
    return (
      <div className="bg-theme-surface rounded-lg border border-theme p-8">
        <div className="flex justify-center">
          <LoadingSpinner size="lg" />
        </div>
      </div>
    );
  }

  if (!stats) {
    return (
      <div className="bg-theme-surface rounded-lg border border-theme p-8 text-center">
        <BarChart3 className="w-12 h-12 text-theme-tertiary mx-auto mb-4" />
        <h3 className="text-lg font-medium text-theme-primary mb-2">No statistics available</h3>
        <p className="text-theme-secondary">
          Statistics will appear here once you have webhook endpoints configured
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Main Stats Grid */}
      <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-4">
        <div className="bg-theme-surface rounded-lg p-4 border border-theme">
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-lg bg-theme-interactive-primary bg-opacity-10">
              <Globe className="w-5 h-5 text-theme-interactive-primary" />
            </div>
            <div>
              <p className="text-2xl font-bold text-theme-primary">{stats.total_endpoints}</p>
              <p className="text-sm text-theme-secondary">Total Endpoints</p>
            </div>
          </div>
        </div>

        <div className="bg-theme-surface rounded-lg p-4 border border-theme">
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-lg bg-theme-success bg-opacity-10">
              <CheckCircle className="w-5 h-5 text-theme-success" />
            </div>
            <div>
              <p className="text-2xl font-bold text-theme-primary">{stats.active_endpoints}</p>
              <p className="text-sm text-theme-secondary">Active</p>
            </div>
          </div>
        </div>

        <div className="bg-theme-surface rounded-lg p-4 border border-theme">
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-lg bg-theme-tertiary bg-opacity-10">
              <Clock className="w-5 h-5 text-theme-tertiary" />
            </div>
            <div>
              <p className="text-2xl font-bold text-theme-primary">{stats.inactive_endpoints}</p>
              <p className="text-sm text-theme-secondary">Inactive</p>
            </div>
          </div>
        </div>

        <div className="bg-theme-surface rounded-lg p-4 border border-theme">
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-lg bg-theme-interactive-primary bg-opacity-10">
              <Activity className="w-5 h-5 text-theme-interactive-primary" />
            </div>
            <div>
              <p className="text-2xl font-bold text-theme-primary">{stats.total_deliveries_today}</p>
              <p className="text-sm text-theme-secondary">Deliveries Today</p>
            </div>
          </div>
        </div>

        <div className="bg-theme-surface rounded-lg p-4 border border-theme">
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-lg bg-theme-success bg-opacity-10">
              <CheckCircle className="w-5 h-5 text-theme-success" />
            </div>
            <div>
              <p className="text-2xl font-bold text-theme-primary">{stats.successful_deliveries_today}</p>
              <p className="text-sm text-theme-secondary">Successful</p>
            </div>
          </div>
        </div>

        <div className="bg-theme-surface rounded-lg p-4 border border-theme">
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-lg bg-theme-error bg-opacity-10">
              <AlertTriangle className="w-5 h-5 text-theme-error" />
            </div>
            <div>
              <p className="text-2xl font-bold text-theme-primary">{stats.failed_deliveries_today}</p>
              <p className="text-sm text-theme-secondary">Failed</p>
            </div>
          </div>
        </div>
      </div>

      {/* Success Rate Card */}
      <div className="bg-theme-surface rounded-lg border border-theme p-6">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-semibold text-theme-primary flex items-center gap-2">
            <Target className="w-5 h-5" />
            Success Rate Today
          </h3>
          <div className={`flex items-center gap-2 text-sm font-medium ${
            successRate >= 95 ? 'text-theme-success' :
            successRate >= 80 ? 'text-theme-warning' : 'text-theme-error'
          }`}>
            {successRate >= 95 ? (
              <TrendingUp className="w-4 h-4" />
            ) : (
              <TrendingDown className="w-4 h-4" />
            )}
            {successRate}%
          </div>
        </div>
        
        <div className="relative">
          <div className="w-full bg-theme-background rounded-full h-3">
            <div 
              className={`h-3 rounded-full transition-all duration-300 ${
                successRate >= 95 ? 'bg-theme-success' :
                successRate >= 80 ? 'bg-theme-warning' : 'bg-theme-error'
              }`}
              style={{ width: `${successRate}%` }}
            />
          </div>
          <div className="flex justify-between mt-2 text-sm text-theme-secondary">
            <span>{stats.successful_deliveries_today} successful</span>
            <span>{stats.failed_deliveries_today} failed</span>
          </div>
        </div>
      </div>

      {/* Detailed Stats */}
      {detailedStats && (
        <>
          {/* Performance Metrics */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div className="bg-theme-surface rounded-lg border border-theme p-6">
              <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
                <Timer className="w-5 h-5" />
                Performance
              </h3>
              <div className="space-y-4">
                <div>
                  <div className="flex items-center justify-between mb-2">
                    <span className="text-theme-secondary">Average Response Time</span>
                    <span className="font-medium text-theme-primary">
                      {detailedStats.average_response_times 
                        ? `${Math.round(detailedStats.average_response_times)}ms`
                        : 'N/A'
                      }
                    </span>
                  </div>
                </div>
              </div>
            </div>

            <div className="bg-theme-surface rounded-lg border border-theme p-6">
              <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
                <RefreshCw className="w-5 h-5" />
                Retry Statistics
              </h3>
              <div className="space-y-4">
                <div className="flex items-center justify-between">
                  <span className="text-theme-secondary">Total Retries</span>
                  <span className="font-medium text-theme-primary">
                    {detailedStats.retry_statistics.total_retries}
                  </span>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-theme-secondary">Pending Retries</span>
                  <span className="font-medium text-theme-warning">
                    {detailedStats.retry_statistics.pending_retries}
                  </span>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-theme-secondary">Max Retries Reached</span>
                  <span className="font-medium text-theme-error">
                    {detailedStats.retry_statistics.max_retries_reached}
                  </span>
                </div>
              </div>
            </div>
          </div>

          {/* Most Active Endpoints */}
          <div className="bg-theme-surface rounded-lg border border-theme p-6">
            <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
              <Zap className="w-5 h-5" />
              Most Active Endpoints
            </h3>
            {Object.keys(detailedStats.most_active_endpoints).length === 0 ? (
              <p className="text-theme-secondary">No activity data available</p>
            ) : (
              <div className="space-y-3">
                {Object.entries(detailedStats.most_active_endpoints)
                  .sort(([,a], [,b]) => b - a)
                  .slice(0, 5)
                  .map(([url, count]) => (
                    <div key={url} className="flex items-center justify-between">
                      <div className="flex items-center gap-2 flex-1 min-w-0">
                        <Globe className="w-4 h-4 text-theme-tertiary flex-shrink-0" />
                        <span className="text-theme-primary truncate" title={url}>
                          {url.length > 50 ? url.substring(0, 47) + '...' : url}
                        </span>
                      </div>
                      <span className="bg-theme-interactive-primary bg-opacity-10 text-theme-interactive-primary px-2 py-1 rounded text-sm font-medium ml-2">
                        {count}
                      </span>
                    </div>
                  ))}
              </div>
            )}
          </div>

          {/* Event Type Distribution */}
          <div className="bg-theme-surface rounded-lg border border-theme p-6">
            <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
              <BarChart3 className="w-5 h-5" />
              Event Type Distribution (Last 7 Days)
            </h3>
            {Object.keys(detailedStats.event_type_distribution).length === 0 ? (
              <p className="text-theme-secondary">No event data available</p>
            ) : (
              <div className="space-y-3">
                {Object.entries(detailedStats.event_type_distribution)
                  .sort(([,a], [,b]) => b - a)
                  .map(([eventType, count]) => {
                    const maxCount = Math.max(...Object.values(detailedStats.event_type_distribution));
                    const percentage = maxCount === 0 ? 0 : (count / maxCount) * 100;
                    
                    return (
                      <div key={eventType} className="space-y-2">
                        <div className="flex items-center justify-between">
                          <span className="text-theme-primary font-medium">
                            {eventType.split('.').map(part => 
                              part.charAt(0).toUpperCase() + part.slice(1)
                            ).join(' → ')}
                          </span>
                          <span className="text-theme-secondary font-medium">{count}</span>
                        </div>
                        <div className="w-full bg-theme-background rounded-full h-2">
                          <div 
                            className="h-2 bg-theme-interactive-primary rounded-full transition-all duration-300"
                            style={{ width: `${percentage}%` }}
                          />
                        </div>
                      </div>
                    );
                  })}
              </div>
            )}
          </div>

          {/* Daily Delivery Trend */}
          <div className="bg-theme-surface rounded-lg border border-theme p-6">
            <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
              <Activity className="w-5 h-5" />
              Daily Delivery Trend (Last 7 Days)
            </h3>
            {Object.keys(detailedStats.daily_delivery_trend).length === 0 ? (
              <p className="text-theme-secondary">No delivery trend data available</p>
            ) : (
              <div className="space-y-3">
                {Object.entries(detailedStats.daily_delivery_trend)
                  .sort(([a], [b]) => new Date(a).getTime() - new Date(b).getTime())
                  .map(([date, count]) => {
                    const maxCount = Math.max(...Object.values(detailedStats.daily_delivery_trend));
                    const percentage = maxCount === 0 ? 0 : (count / maxCount) * 100;
                    
                    return (
                      <div key={date} className="space-y-2">
                        <div className="flex items-center justify-between">
                          <span className="text-theme-primary">
                            {new Date(date).toLocaleDateString()}
                          </span>
                          <span className="text-theme-secondary font-medium">{count} deliveries</span>
                        </div>
                        <div className="w-full bg-theme-background rounded-full h-2">
                          <div 
                            className="h-2 bg-theme-success rounded-full transition-all duration-300"
                            style={{ width: `${percentage}%` }}
                          />
                        </div>
                      </div>
                    );
                  })}
              </div>
            )}
          </div>
        </>
      )}

      {/* Health Summary */}
      <div className="bg-theme-interactive-primary bg-opacity-5 border border-theme-interactive-primary rounded-lg p-6">
        <h3 className="text-lg font-semibold text-theme-interactive-primary mb-4">
          Webhook Health Summary
        </h3>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4 text-sm">
          <div>
            <h4 className="font-medium text-theme-primary mb-2">Overall Status</h4>
            <ul className="space-y-1 text-theme-secondary">
              <li>
                • {stats.active_endpoints} active endpoint{stats.active_endpoints !== 1 ? 's' : ''} 
                {stats.inactive_endpoints > 0 && ` (${stats.inactive_endpoints} inactive)`}
              </li>
              <li>• {successRate}% success rate today</li>
              {detailedStats && detailedStats.retry_statistics.pending_retries > 0 && (
                <li className="text-theme-warning">
                  • {detailedStats.retry_statistics.pending_retries} pending retries
                </li>
              )}
            </ul>
          </div>
          <div>
            <h4 className="font-medium text-theme-primary mb-2">Recommendations</h4>
            <ul className="space-y-1 text-theme-secondary">
              {stats.failed_deliveries_today > 0 && (
                <li>• Review failed deliveries and endpoint availability</li>
              )}
              {stats.inactive_endpoints > 0 && (
                <li>• Consider activating inactive endpoints</li>
              )}
              {successRate < 95 && (
                <li>• Monitor webhook endpoint performance</li>
              )}
              {stats.total_deliveries_today === 0 && (
                <li>• Verify webhook events are being triggered</li>
              )}
            </ul>
          </div>
        </div>
      </div>
    </div>
  );
};

export default WebhookStats;