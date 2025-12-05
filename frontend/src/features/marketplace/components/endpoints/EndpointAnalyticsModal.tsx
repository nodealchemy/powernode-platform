import React, { useState, useEffect } from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { Badge } from '@/shared/components/ui/Badge';
import { AppEndpoint } from '../../types';
import { getHttpMethodThemeClass } from '../../utils/themeHelpers';
import { X, Calendar, TrendingUp, Activity, AlertCircle, CheckCircle, Clock, Users } from 'lucide-react';

interface EndpointAnalyticsModalProps {
  isOpen: boolean;
  onClose: () => void;
  endpoint: AppEndpoint | null;
}

interface AnalyticsData {
  total_calls: number;
  calls_by_day: Record<string, number>;
  calls_by_status: Record<string, number>;
  average_response_time: number;
  success_rate: number;
  error_rate: number;
  top_errors: Record<string, number>;
}


const formatNumber = (num: number): string => {
  if (num >= 1000000) return (num / 1000000).toFixed(1) + 'M';
  if (num >= 1000) return (num / 1000).toFixed(1) + 'K';
  return num.toString();
};

const formatDate = (dateStr: string): string => {
  const date = new Date(dateStr);
  return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
};

export const EndpointAnalyticsModal: React.FC<EndpointAnalyticsModalProps> = ({
  isOpen,
  onClose,
  endpoint
}) => {
  const [loading, setLoading] = useState(true);
  const [analytics, setAnalytics] = useState<AnalyticsData | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [timeRange, setTimeRange] = useState<7 | 30 | 90>(30);
  const [activeTab, setActiveTab] = useState<'overview' | 'performance' | 'errors'>('overview');

  // Mock analytics data for demo
  useEffect(() => {
    if (isOpen && endpoint) {
      setLoading(true);
      setError(null);
      
      // Simulate API call delay
      setTimeout(() => {
        // Generate mock data
        const mockAnalytics: AnalyticsData = {
          total_calls: Math.floor(Math.random() * 10000) + 1000,
          calls_by_day: generateDailyData(timeRange),
          calls_by_status: {
            '200': Math.floor(Math.random() * 800) + 200,
            '201': Math.floor(Math.random() * 100) + 50,
            '400': Math.floor(Math.random() * 50) + 10,
            '401': Math.floor(Math.random() * 20) + 5,
            '404': Math.floor(Math.random() * 30) + 10,
            '500': Math.floor(Math.random() * 15) + 2
          },
          average_response_time: Math.floor(Math.random() * 200) + 50,
          success_rate: 95 + Math.random() * 4,
          error_rate: Math.random() * 5,
          top_errors: {
            'Invalid request parameter': Math.floor(Math.random() * 20) + 5,
            'Authentication failed': Math.floor(Math.random() * 15) + 3,
            'Resource not found': Math.floor(Math.random() * 10) + 2,
            'Rate limit exceeded': Math.floor(Math.random() * 8) + 1
          }
        };

        setAnalytics(mockAnalytics);
        setLoading(false);
      }, 1000);
    }
  }, [isOpen, endpoint, timeRange]);

  const generateDailyData = (days: number): Record<string, number> => {
    const data: Record<string, number> = {};
    for (let i = days - 1; i >= 0; i--) {
      const date = new Date();
      date.setDate(date.getDate() - i);
      const dateStr = date.toISOString().split('T')[0];
      data[dateStr as keyof typeof data] = Math.floor(Math.random() * 100) + 10;
    }
    return data;
  };

  const tabs = [
    { id: 'overview', label: 'Overview', icon: '📊' },
    { id: 'performance', label: 'Performance', icon: '⚡' },
    { id: 'errors', label: 'Errors', icon: '🚨' }
  ] as const;

  const timeRanges = [
    { value: 7, label: '7 Days' },
    { value: 30, label: '30 Days' },
    { value: 90, label: '90 Days' }
  ];

  if (!endpoint) return null;

  return (
    <Modal isOpen={isOpen} onClose={onClose} title="Endpoint Analytics" maxWidth="xl">
      <div className="space-y-6">
        <div className="flex items-center justify-between pb-4 border-b border-theme">
          <div>
            <h2 className="text-xl font-semibold text-theme-primary">Endpoint Analytics</h2>
            <div className="flex items-center space-x-3 mt-2">
              <Badge className={getHttpMethodThemeClass(endpoint.http_method)}>
                {endpoint.http_method}
              </Badge>
              <span className="text-sm font-mono text-theme-secondary bg-theme-surface px-2 py-1 rounded">
                {endpoint.full_path}
              </span>
            </div>
          </div>
          <div className="flex items-center space-x-3">
            <select
              value={timeRange}
              onChange={(e) => setTimeRange(Number(e.target.value) as 7 | 30 | 90)}
              className="px-3 py-1 text-sm border border-theme rounded-lg bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
            >
              {timeRanges.map(range => (
                <option key={range.value} value={range.value}>{range.label}</option>
              ))}
            </select>
            <Button variant="ghost" size="sm" onClick={onClose}>
              <X className="w-4 h-4" />
            </Button>
          </div>
        </div>

        {/* Endpoint Info */}
        <div className="bg-theme-surface rounded-lg p-4">
          <h3 className="font-medium text-theme-primary mb-2">{endpoint.name}</h3>
          {endpoint.description && (
            <p className="text-sm text-theme-secondary">{endpoint.description}</p>
          )}
        </div>

        {/* Loading State */}
        {loading && (
          <div className="text-center py-12">
            <LoadingSpinner size="lg" />
            <p className="text-theme-secondary mt-4">Loading analytics data...</p>
          </div>
        )}

        {/* Error State */}
        {error && (
          <div className="bg-theme-error-background border border-theme-error-border rounded-lg p-6 text-center">
            <AlertCircle className="w-8 h-8 text-theme-error mx-auto mb-4" />
            <p className="text-theme-error mb-4">{error}</p>
            <Button variant="outline" onClick={() => setLoading(true)}>
              Retry
            </Button>
          </div>
        )}

        {/* Analytics Content */}
        {!loading && !error && analytics && (
          <>
            {/* Tabs */}
            <div className="border-b border-theme">
              <div className="flex space-x-8 -mb-px overflow-x-auto scrollbar-hide">
                {tabs.map((tab) => (
                  <button
                    key={tab.id}
                    type="button"
                    onClick={() => setActiveTab(tab.id)}
                    className={`flex items-center space-x-2 py-2 px-1 border-b-2 font-medium text-sm ${
                      activeTab === tab.id
                        ? 'border-theme-link text-theme-link'
                        : 'border-transparent text-theme-secondary hover:text-theme-primary'
                    }`}
                  >
                    <span className="text-base">{tab.icon}</span>
                    <span>{tab.label}</span>
                  </button>
                ))}
              </div>
            </div>

            {/* Overview Tab */}
            {activeTab === 'overview' && (
              <div className="space-y-6">
                {/* Key Metrics */}
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
                  <div className="bg-theme-surface rounded-lg p-6">
                    <div className="flex items-center space-x-3">
                      <div className="p-2 bg-theme-interactive-primary/10 rounded-lg">
                        <Activity className="w-5 h-5 text-theme-interactive-primary" />
                      </div>
                      <div>
                        <div className="text-sm text-theme-tertiary">Total Calls</div>
                        <div className="text-2xl font-bold text-theme-primary">
                          {formatNumber(analytics.total_calls)}
                        </div>
                      </div>
                    </div>
                  </div>

                  <div className="bg-theme-surface rounded-lg p-6">
                    <div className="flex items-center space-x-3">
                      <div className="p-2 bg-theme-success/10 rounded-lg">
                        <CheckCircle className="w-5 h-5 text-theme-success" />
                      </div>
                      <div>
                        <div className="text-sm text-theme-tertiary">Success Rate</div>
                        <div className="text-2xl font-bold text-theme-success">
                          {analytics.success_rate.toFixed(1)}%
                        </div>
                      </div>
                    </div>
                  </div>

                  <div className="bg-theme-surface rounded-lg p-6">
                    <div className="flex items-center space-x-3">
                      <div className="p-2 bg-theme-warning/10 rounded-lg">
                        <Clock className="w-5 h-5 text-theme-warning" />
                      </div>
                      <div>
                        <div className="text-sm text-theme-tertiary">Avg Response</div>
                        <div className="text-2xl font-bold text-theme-primary">
                          {analytics.average_response_time}ms
                        </div>
                      </div>
                    </div>
                  </div>

                  <div className="bg-theme-surface rounded-lg p-6">
                    <div className="flex items-center space-x-3">
                      <div className="p-2 bg-theme-error/10 rounded-lg">
                        <AlertCircle className="w-5 h-5 text-theme-error" />
                      </div>
                      <div>
                        <div className="text-sm text-theme-tertiary">Error Rate</div>
                        <div className="text-2xl font-bold text-theme-error">
                          {analytics.error_rate.toFixed(1)}%
                        </div>
                      </div>
                    </div>
                  </div>
                </div>

                {/* Daily Usage Chart */}
                <div className="bg-theme-surface rounded-lg p-6">
                  <h3 className="text-lg font-medium text-theme-primary mb-4">
                    Daily Usage ({timeRange} days)
                  </h3>
                  <div className="h-64 flex items-end space-x-2">
                    {Object.entries(analytics.calls_by_day).map(([date, calls]) => {
                      const maxCalls = Math.max(...Object.values(analytics.calls_by_day));
                      const height = (calls / maxCalls) * 100;
                      
                      return (
                        <div key={date} className="flex-1 flex flex-col items-center">
                          <div className="text-xs text-theme-tertiary mb-2">{calls}</div>
                          <div 
                            className="w-full bg-theme-interactive-primary/80 rounded-t hover:bg-theme-interactive-primary transition-colors"
                            style={{ height: `${height}%`, minHeight: '4px' }}
                          />
                          <div className="text-xs text-theme-tertiary mt-2 -rotate-45 origin-center">
                            {formatDate(date)}
                          </div>
                        </div>
                      );
                    })}
                  </div>
                </div>

                {/* Status Code Distribution */}
                <div className="bg-theme-surface rounded-lg p-6">
                  <h3 className="text-lg font-medium text-theme-primary mb-4">Status Code Distribution</h3>
                  <div className="space-y-3">
                    {Object.entries(analytics.calls_by_status).map(([status, count]) => {
                      const total = Object.values(analytics.calls_by_status).reduce((a, b) => a + b, 0);
                      const percentage = (count / total) * 100;
                      
                      const getStatusColor = (code: string) => {
                        if (code.startsWith('2')) return 'bg-theme-success';
                        if (code.startsWith('4')) return 'bg-theme-warning';
                        if (code.startsWith('5')) return 'bg-theme-error';
                        return 'bg-theme-secondary';
                      };

                      return (
                        <div key={status} className="flex items-center space-x-3">
                          <div className="w-12 text-sm font-mono text-theme-primary">{status}</div>
                          <div className="flex-1 bg-theme/20 rounded-full h-2">
                            <div 
                              className={`h-2 rounded-full ${getStatusColor(status)}`}
                              style={{ width: `${percentage}%` }}
                            />
                          </div>
                          <div className="w-16 text-right text-sm text-theme-secondary">
                            {formatNumber(count)} ({percentage.toFixed(1)}%)
                          </div>
                        </div>
                      );
                    })}
                  </div>
                </div>
              </div>
            )}

            {/* Performance Tab */}
            {activeTab === 'performance' && (
              <div className="space-y-6">
                {/* Performance Metrics */}
                <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                  <div className="bg-theme-surface rounded-lg p-6">
                    <div className="flex items-center space-x-3 mb-4">
                      <Clock className="w-5 h-5 text-theme-primary" />
                      <h3 className="font-medium text-theme-primary">Response Time</h3>
                    </div>
                    <div className="text-3xl font-bold text-theme-primary mb-2">
                      {analytics.average_response_time}ms
                    </div>
                    <div className="text-sm text-theme-success">
                      ↓ 15% from last period
                    </div>
                  </div>

                  <div className="bg-theme-surface rounded-lg p-6">
                    <div className="flex items-center space-x-3 mb-4">
                      <TrendingUp className="w-5 h-5 text-theme-primary" />
                      <h3 className="font-medium text-theme-primary">Throughput</h3>
                    </div>
                    <div className="text-3xl font-bold text-theme-primary mb-2">
                      {Math.round(analytics.total_calls / timeRange)}
                    </div>
                    <div className="text-sm text-theme-secondary">calls/day average</div>
                  </div>

                  <div className="bg-theme-surface rounded-lg p-6">
                    <div className="flex items-center space-x-3 mb-4">
                      <Users className="w-5 h-5 text-theme-primary" />
                      <h3 className="font-medium text-theme-primary">Peak Usage</h3>
                    </div>
                    <div className="text-3xl font-bold text-theme-primary mb-2">
                      {Math.max(...Object.values(analytics.calls_by_day))}
                    </div>
                    <div className="text-sm text-theme-secondary">calls in one day</div>
                  </div>
                </div>

                {/* Performance Tips */}
                <div className="bg-theme-info-background border border-theme-info-border rounded-lg p-6">
                  <h3 className="font-medium text-theme-primary mb-4">Performance Insights</h3>
                  <div className="space-y-3">
                    <div className="flex items-start space-x-3">
                      <span className="text-lg">💡</span>
                      <div>
                        <div className="font-medium text-theme-primary">Good Response Time</div>
                        <div className="text-sm text-theme-secondary">
                          Your average response time of {analytics.average_response_time}ms is excellent for this type of endpoint.
                        </div>
                      </div>
                    </div>
                    <div className="flex items-start space-x-3">
                      <span className="text-lg">🚀</span>
                      <div>
                        <div className="font-medium text-theme-primary">Usage Trend</div>
                        <div className="text-sm text-theme-secondary">
                          Your endpoint shows consistent usage with {analytics.success_rate.toFixed(1)}% success rate.
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            )}

            {/* Errors Tab */}
            {activeTab === 'errors' && (
              <div className="space-y-6">
                {/* Error Summary */}
                <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                  <div className="bg-theme-surface rounded-lg p-6">
                    <div className="flex items-center space-x-3 mb-4">
                      <AlertCircle className="w-5 h-5 text-theme-error" />
                      <h3 className="font-medium text-theme-primary">Error Rate</h3>
                    </div>
                    <div className="text-3xl font-bold text-theme-error mb-2">
                      {analytics.error_rate.toFixed(2)}%
                    </div>
                    <div className="text-sm text-theme-success">
                      ↓ 2.1% from last period
                    </div>
                  </div>

                  <div className="bg-theme-surface rounded-lg p-6">
                    <div className="flex items-center space-x-3 mb-4">
                      <span className="text-lg">🔥</span>
                      <h3 className="font-medium text-theme-primary">Total Errors</h3>
                    </div>
                    <div className="text-3xl font-bold text-theme-primary mb-2">
                      {Object.values(analytics.top_errors).reduce((a, b) => a + b, 0)}
                    </div>
                    <div className="text-sm text-theme-secondary">
                      in last {timeRange} days
                    </div>
                  </div>
                </div>

                {/* Top Errors */}
                <div className="bg-theme-surface rounded-lg p-6">
                  <h3 className="text-lg font-medium text-theme-primary mb-4">Most Common Errors</h3>
                  <div className="space-y-4">
                    {Object.entries(analytics.top_errors).map(([error, count]) => {
                      const totalErrors = Object.values(analytics.top_errors).reduce((a, b) => a + b, 0);
                      const percentage = totalErrors > 0 ? (count / totalErrors) * 100 : 0;
                      
                      return (
                        <div key={error} className="border border-theme rounded-lg p-4">
                          <div className="flex items-center justify-between mb-2">
                            <span className="font-medium text-theme-primary">{error}</span>
                            <Badge variant="secondary">{count} occurrences</Badge>
                          </div>
                          <div className="flex items-center space-x-3">
                            <div className="flex-1 bg-theme/20 rounded-full h-2">
                              <div 
                                className="h-2 rounded-full bg-theme-error"
                                style={{ width: `${percentage}%` }}
                              />
                            </div>
                            <div className="text-sm text-theme-secondary">
                              {percentage.toFixed(1)}%
                            </div>
                          </div>
                        </div>
                      );
                    })}
                  </div>
                </div>

                {/* Error Resolution Tips */}
                <div className="bg-theme-warning-background border border-theme-warning-border rounded-lg p-6">
                  <h3 className="font-medium text-theme-primary mb-4">Error Resolution Tips</h3>
                  <div className="space-y-3">
                    <div className="flex items-start space-x-3">
                      <span className="text-lg">🔍</span>
                      <div>
                        <div className="font-medium text-theme-primary">Invalid Request Parameter</div>
                        <div className="text-sm text-theme-secondary">
                          Add input validation and return clear error messages for invalid parameters.
                        </div>
                      </div>
                    </div>
                    <div className="flex items-start space-x-3">
                      <span className="text-lg">🔐</span>
                      <div>
                        <div className="font-medium text-theme-primary">Authentication Failed</div>
                        <div className="text-sm text-theme-secondary">
                          Ensure API documentation clearly explains authentication requirements.
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            )}
          </>
        )}

        {/* Modal Actions */}
        <div className="flex items-center justify-end space-x-3 pt-6 border-t border-theme">
          <Button variant="outline" onClick={onClose}>
            Close
          </Button>
          <Button disabled={!analytics}>
            <Calendar className="w-4 h-4 mr-2" />
            Export Report
          </Button>
        </div>
      </div>
    </Modal>
  );
};