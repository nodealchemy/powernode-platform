import React, { useState, useEffect, useCallback } from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useAppWebhook } from '../../hooks/useWebhooks';
import { AppWebhook } from '../../types';
import { X, RefreshCw, TrendingUp, Clock, AlertTriangle, CheckCircle } from 'lucide-react';

interface WebhookAnalyticsModalProps {
  isOpen: boolean;
  onClose: () => void;
  appId: string;
  webhook: AppWebhook;
}

interface WebhookAnalytics {
  total_deliveries: number;
  deliveries_by_day: Record<string, number>;
  deliveries_by_status: Record<string, number>;
  success_rate: number;
  failure_rate: number;
  average_response_time: number;
  pending_deliveries: number;
  failed_deliveries: number;
  retry_stats: {
    total_retries: number;
    max_attempts: number;
    avg_attempts: number;
  };
}

export const WebhookAnalyticsModal: React.FC<WebhookAnalyticsModalProps> = ({
WebhookAnalyticsModal.displayName = 'WebhookAnalyticsModal';
  isOpen,
  onClose,
  appId,
  webhook
}) => {
  const [analytics, setAnalytics] = useState<WebhookAnalytics | null>(null);
  const [loading, setLoading] = useState(true);
  const [dayRange, setDayRange] = useState(30);

  const { getAnalytics } = useAppWebhook(appId, webhook.id);

  const loadAnalytics = useCallback(async () => {
    setLoading(true);
    try {
      const data = await getAnalytics(dayRange);
      if (data) {
        setAnalytics(data);
      }
    } catch (error) {
      console.error('Failed to load analytics:', error);
    } finally {
      setLoading(false);
    }
  }, [getAnalytics, dayRange]);

  useEffect(() => {
    if (isOpen) {
      loadAnalytics();
    }
  }, [isOpen, dayRange, loadAnalytics]);

  const formatResponseTime = (ms: number) => {
    if (ms < 1000) return `${ms.toFixed(0)}ms`;
    return `${(ms / 1000).toFixed(2)}s`;
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'delivered':
      case 'success':
        return 'text-theme-success';
      case 'pending':
        return 'text-theme-warning';
      case 'failed':
        return 'text-theme-error';
      default:
        return 'text-theme-secondary';
    }
  };

  const renderChart = () => {
    if (!analytics) return null;

    const days = Object.entries(analytics.deliveries_by_day)
      .sort(([a], [b]) => new Date(a).getTime() - new Date(b).getTime())
      .slice(-7); // Show last 7 days

    const maxValue = Math.max(...days.map(([, count]) => count), 1);

    return (
      <div className="space-y-4">
        <h3 className="font-medium text-theme-primary">Delivery Trends (Last 7 days)</h3>
        <div className="flex items-end justify-between h-32 space-x-2">
          {days.map(([date, count]) => (
            <div key={date} className="flex flex-col items-center space-y-2 flex-1">
              <div className="text-xs text-theme-tertiary">
                {count}
              </div>
              <div
                className="bg-theme-interactive-primary w-full rounded-t"
                style={{ height: `${(count / maxValue) * 80}px` }}
                title={`${count} deliveries on ${new Date(date).toLocaleDateString()}`}
              />
              <div className="text-xs text-theme-secondary">
                {new Date(date).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}
              </div>
            </div>
          ))}
        </div>
      </div>
    );
  };

  return (
    <Modal 
      isOpen={isOpen} 
      onClose={onClose} 
      title="Webhook Analytics"
      subtitle={webhook.name}
      maxWidth="4xl"
      showCloseButton={false}
    >
      <div className="flex flex-col h-full max-h-[calc(90vh-120px)]">
        <div className="flex items-center justify-between p-4 border-b border-theme">
          <div className="flex items-center space-x-2">
            <select
              value={dayRange}
              onChange={(e) => setDayRange(parseInt(e.target.value))}
              className="input-theme text-sm"
            >
              <option value={7}>Last 7 days</option>
              <option value={30}>Last 30 days</option>
              <option value={90}>Last 90 days</option>
            </select>
            <Button variant="outline" size="sm" onClick={loadAnalytics}>
              <RefreshCw className="w-4 h-4" />
            </Button>
          </div>
          <Button variant="outline" size="sm" onClick={onClose}>
            <X className="w-4 h-4" />
          </Button>
        </div>

        <div className="p-6 max-h-[calc(90vh-200px)] overflow-y-auto space-y-6">
          {loading ? (
            <div className="flex justify-center py-12">
              <LoadingSpinner />
            </div>
          ) : !analytics ? (
            <div className="text-center py-12">
              <div className="text-theme-error mb-4">⚠️ Failed to load analytics</div>
              <Button onClick={loadAnalytics} variant="primary">
                Try Again
              </Button>
            </div>
          ) : (
            <>
              {/* Overview Stats */}
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
                <div className="bg-theme-background rounded-lg p-4">
                  <div className="flex items-center space-x-2 mb-2">
                    <CheckCircle className="w-5 h-5 text-theme-success" />
                    <span className="text-sm font-medium text-theme-primary">Total Deliveries</span>
                  </div>
                  <div className="text-2xl font-bold text-theme-primary">
                    {analytics.total_deliveries.toLocaleString()}
                  </div>
                  <div className="text-sm text-theme-secondary">
                    Last {dayRange} days
                  </div>
                </div>

                <div className="bg-theme-background rounded-lg p-4">
                  <div className="flex items-center space-x-2 mb-2">
                    <TrendingUp className="w-5 h-5 text-theme-success" />
                    <span className="text-sm font-medium text-theme-primary">Success Rate</span>
                  </div>
                  <div className="text-2xl font-bold text-theme-success">
                    {analytics.success_rate.toFixed(1)}%
                  </div>
                  <div className="text-sm text-theme-secondary">
                    {Math.round((analytics.success_rate / 100) * analytics.total_deliveries)} successful
                  </div>
                </div>

                <div className="bg-theme-background rounded-lg p-4">
                  <div className="flex items-center space-x-2 mb-2">
                    <Clock className="w-5 h-5 text-theme-info" />
                    <span className="text-sm font-medium text-theme-primary">Avg Response</span>
                  </div>
                  <div className="text-2xl font-bold text-theme-primary">
                    {formatResponseTime(analytics.average_response_time)}
                  </div>
                  <div className="text-sm text-theme-secondary">
                    Response time
                  </div>
                </div>

                <div className="bg-theme-background rounded-lg p-4">
                  <div className="flex items-center space-x-2 mb-2">
                    <AlertTriangle className="w-5 h-5 text-theme-error" />
                    <span className="text-sm font-medium text-theme-primary">Failed</span>
                  </div>
                  <div className="text-2xl font-bold text-theme-error">
                    {analytics.failed_deliveries}
                  </div>
                  <div className="text-sm text-theme-secondary">
                    {analytics.failure_rate.toFixed(1)}% failure rate
                  </div>
                </div>
              </div>

              {/* Delivery Chart */}
              <div className="bg-theme-background rounded-lg p-6">
                {renderChart()}
              </div>

              {/* Status Breakdown */}
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div className="bg-theme-background rounded-lg p-6">
                  <h3 className="font-medium text-theme-primary mb-4">Delivery Status</h3>
                  <div className="space-y-3">
                    {Object.entries(analytics.deliveries_by_status).map(([status, count]) => {
                      const percentage = analytics.total_deliveries > 0 
                        ? (count / analytics.total_deliveries) * 100 
                        : 0;
                      
                      return (
                        <div key={status} className="flex items-center justify-between">
                          <div className="flex items-center space-x-3">
                            <Badge variant="outline" className={getStatusColor(status)}>
                              {status.charAt(0).toUpperCase() + status.slice(1)}
                            </Badge>
                            <span className="text-theme-secondary text-sm">
                              {count.toLocaleString()} deliveries
                            </span>
                          </div>
                          <span className="text-theme-tertiary text-sm">
                            {percentage.toFixed(1)}%
                          </span>
                        </div>
                      );
                    })}
                  </div>
                </div>

                <div className="bg-theme-background rounded-lg p-6">
                  <h3 className="font-medium text-theme-primary mb-4">Retry Statistics</h3>
                  <div className="space-y-3">
                    <div className="flex items-center justify-between">
                      <span className="text-theme-secondary">Total Retries</span>
                      <span className="font-semibold text-theme-primary">
                        {analytics.retry_stats.total_retries}
                      </span>
                    </div>
                    <div className="flex items-center justify-between">
                      <span className="text-theme-secondary">Max Attempts</span>
                      <span className="font-semibold text-theme-primary">
                        {analytics.retry_stats.max_attempts}
                      </span>
                    </div>
                    <div className="flex items-center justify-between">
                      <span className="text-theme-secondary">Avg Attempts</span>
                      <span className="font-semibold text-theme-primary">
                        {analytics.retry_stats.avg_attempts.toFixed(1)}
                      </span>
                    </div>
                    <div className="flex items-center justify-between">
                      <span className="text-theme-secondary">Pending Deliveries</span>
                      <span className="font-semibold text-theme-warning">
                        {analytics.pending_deliveries}
                      </span>
                    </div>
                  </div>
                </div>
              </div>

              {/* Performance Insights */}
              <div className="bg-theme-background rounded-lg p-6">
                <h3 className="font-medium text-theme-primary mb-4">Performance Insights</h3>
                <div className="grid grid-cols-1 md:grid-cols-3 gap-6 text-sm">
                  <div className="text-center">
                    <div className="text-2xl mb-2">
                      {analytics.success_rate >= 95 ? '🟢' : 
                       analytics.success_rate >= 85 ? '🟡' : '🔴'}
                    </div>
                    <div className="font-medium text-theme-primary">Reliability</div>
                    <div className="text-theme-secondary">
                      {analytics.success_rate >= 95 ? 'Excellent' :
                       analytics.success_rate >= 85 ? 'Good' : 'Needs attention'}
                    </div>
                  </div>

                  <div className="text-center">
                    <div className="text-2xl mb-2">
                      {analytics.average_response_time < 1000 ? '🟢' : 
                       analytics.average_response_time < 5000 ? '🟡' : '🔴'}
                    </div>
                    <div className="font-medium text-theme-primary">Response Time</div>
                    <div className="text-theme-secondary">
                      {analytics.average_response_time < 1000 ? 'Fast' :
                       analytics.average_response_time < 5000 ? 'Moderate' : 'Slow'}
                    </div>
                  </div>

                  <div className="text-center">
                    <div className="text-2xl mb-2">
                      {analytics.retry_stats.avg_attempts < 1.5 ? '🟢' : 
                       analytics.retry_stats.avg_attempts < 2.5 ? '🟡' : '🔴'}
                    </div>
                    <div className="font-medium text-theme-primary">Retry Rate</div>
                    <div className="text-theme-secondary">
                      {analytics.retry_stats.avg_attempts < 1.5 ? 'Low' :
                       analytics.retry_stats.avg_attempts < 2.5 ? 'Moderate' : 'High'}
                    </div>
                  </div>
                </div>
              </div>

              {/* Recommendations */}
              {(analytics.success_rate < 90 || analytics.average_response_time > 5000) && (
                <div className="bg-theme-warning bg-opacity-10 border border-theme-warning border-opacity-20 rounded-lg p-6">
                  <h3 className="font-medium text-theme-primary mb-3 flex items-center">
                    <AlertTriangle className="w-5 h-5 text-theme-warning mr-2" />
                    Performance Recommendations
                  </h3>
                  <ul className="space-y-2 text-sm text-theme-secondary">
                    {analytics.success_rate < 90 && (
                      <li className="flex items-start space-x-2">
                        <span className="text-theme-warning">•</span>
                        <span>
                          Your webhook has a {analytics.success_rate.toFixed(1)}% success rate. 
                          Consider checking your endpoint for errors and implementing proper error handling.
                        </span>
                      </li>
                    )}
                    {analytics.average_response_time > 5000 && (
                      <li className="flex items-start space-x-2">
                        <span className="text-theme-warning">•</span>
                        <span>
                          Response time is {formatResponseTime(analytics.average_response_time)}. 
                          Consider optimizing your webhook endpoint for better performance.
                        </span>
                      </li>
                    )}
                    {analytics.retry_stats.avg_attempts > 2 && (
                      <li className="flex items-start space-x-2">
                        <span className="text-theme-warning">•</span>
                        <span>
                          High retry rate ({analytics.retry_stats.avg_attempts.toFixed(1)} avg attempts). 
                          Check your endpoint reliability and error responses.
                        </span>
                      </li>
                    )}
                  </ul>
                </div>
              )}
            </>
          )}
        </div>

        <div className="border-t border-theme p-6">
          <div className="flex items-center justify-between">
            <div className="text-sm text-theme-secondary">
              Analytics updated every hour. Last updated: {new Date().toLocaleString()}
            </div>
            <Button variant="primary" onClick={onClose}>
              Close
            </Button>
          </div>
        </div>
      </div>
    </Modal>
  );
};