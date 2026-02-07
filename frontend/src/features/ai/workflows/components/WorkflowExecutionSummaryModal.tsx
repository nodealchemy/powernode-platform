import React, { useState, useEffect } from 'react';
import {
  BarChart3,
  Clock,
  TrendingUp,
  TrendingDown,
  CheckCircle,
  XCircle,
  AlertCircle,
  Activity,
  Users
} from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { Button } from '@/shared/components/ui/Button';
import { Card, CardContent, CardTitle } from '@/shared/components/ui/Card';
import { workflowsApi } from '@/shared/services/ai';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { WorkflowExecutionStats } from '@/shared/types/workflow';

export interface WorkflowExecutionSummaryModalProps {
  isOpen: boolean;
  onClose: () => void;
  workflowId: string;
  workflowName: string;
}

export const WorkflowExecutionSummaryModal: React.FC<WorkflowExecutionSummaryModalProps> = ({
  isOpen,
  onClose,
  workflowId,
  workflowName
}) => {
  const { addNotification } = useNotifications();

  const [metrics, setMetrics] = useState<WorkflowExecutionStats | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [dateRange, setDateRange] = useState<'7d' | '30d' | '90d' | 'all'>('30d');

  // Load execution metrics
  const loadMetrics = async () => {
    if (!workflowId || !isOpen) return;

    try {
      setLoading(true);
      setError(null);

      // Calculate date range
      const endDate = new Date().toISOString().split('T')[0];
      let startDate: string | undefined;

      if (dateRange !== 'all') {
        const days = dateRange === '7d' ? 7 : dateRange === '30d' ? 30 : 90;
        const start = new Date();
        start.setDate(start.getDate() - days);
        startDate = start.toISOString().split('T')[0];
      }

      const response = await workflowsApi.getExecutionMetrics(startDate, endDate);
      setMetrics(response.metrics);
    } catch (_error) {
      setError('Failed to load execution summary. Please try again.');
      addNotification({
        type: 'error',
        title: 'Error',
        message: 'Failed to load execution summary'
      });
    } finally {
      setLoading(false);
    }
  };

  // Reset state and load when modal opens
  useEffect(() => {
    if (isOpen && workflowId) {
      // Reset state for fresh load
      setMetrics(null);
      setLoading(true);
      setError(null);
      loadMetrics();
    }
  }, [isOpen, workflowId, dateRange]);  

  // Format duration
  const formatDuration = (ms: number): string => {
    if (ms < 1000) return `${Math.round(ms)}ms`;
    if (ms < 60000) return `${(ms / 1000).toFixed(1)}s`;
    const minutes = Math.floor(ms / 60000);
    const seconds = Math.floor((ms % 60000) / 1000);
    return `${minutes}m ${seconds}s`;
  };

  // Format percentage
  const formatPercentage = (value: number): string => {
    return `${Math.round(value * 100)}%`;
  };

  // Date range labels
  const dateRangeLabels = {
    '7d': 'Last 7 days',
    '30d': 'Last 30 days',
    '90d': 'Last 90 days',
    'all': 'All time'
  };

  // Modal footer
  const footer = (
    <div className="flex gap-3">
      <Button variant="outline" onClick={onClose}>
        Close
      </Button>
      <Button variant="outline" onClick={loadMetrics} disabled={loading}>
        Refresh
      </Button>
    </div>
  );

  // Loading state
  if (loading) {
    return (
      <Modal
        isOpen={isOpen}
        onClose={onClose}
        title={`Execution Summary - ${workflowName}`}
        maxWidth="5xl"
        icon={<BarChart3 />}
        footer={footer}
      >
        <LoadingSpinner className="py-12" />
      </Modal>
    );
  }

  // Error state
  if (error) {
    return (
      <Modal
        isOpen={isOpen}
        onClose={onClose}
        title={`Execution Summary - ${workflowName}`}
        maxWidth="5xl"
        icon={<BarChart3 />}
        footer={footer}
      >
        <div className="text-center py-8">
          <p className="text-theme-error">{error}</p>
          <Button
            variant="outline"
            onClick={loadMetrics}
            className="mt-4"
          >
            Try Again
          </Button>
        </div>
      </Modal>
    );
  }

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={`Execution Summary - ${workflowName}`}
      maxWidth="5xl"
      icon={<BarChart3 />}
      footer={footer}
    >
      <div className="space-y-6">
        {/* Date Range Filter */}
        <div className="flex items-center justify-between">
          <h3 className="text-lg font-semibold text-theme-primary">Performance Overview</h3>
          <div className="flex gap-2">
            {(Object.keys(dateRangeLabels) as Array<keyof typeof dateRangeLabels>).map((range) => (
              <Button
                key={range}
                variant={dateRange === range ? "primary" : "outline"}
                size="sm"
                onClick={() => setDateRange(range)}
              >
                {dateRangeLabels[range]}
              </Button>
            ))}
          </div>
        </div>

        {metrics ? (
          <>
            {/* Key Metrics Cards */}
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
              <Card>
                <CardContent className="p-4">
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="text-sm text-theme-muted">Total Executions</p>
                      <p className="text-2xl font-bold text-theme-primary">
                        {metrics.totalExecutions.toLocaleString()}
                      </p>
                    </div>
                    <Activity className="h-8 w-8 text-theme-info" />
                  </div>
                </CardContent>
              </Card>

              <Card>
                <CardContent className="p-4">
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="text-sm text-theme-muted">Success Rate</p>
                      <div className="flex items-center gap-2">
                        <p className="text-2xl font-bold text-theme-primary">
                          {formatPercentage(metrics.successRate)}
                        </p>
                        {metrics.successRate >= 0.9 ? (
                          <TrendingUp className="h-4 w-4 text-theme-success" />
                        ) : metrics.successRate >= 0.7 ? (
                          <AlertCircle className="h-4 w-4 text-theme-warning" />
                        ) : (
                          <TrendingDown className="h-4 w-4 text-theme-error" />
                        )}
                      </div>
                    </div>
                    <CheckCircle className="h-8 w-8 text-theme-success" />
                  </div>
                </CardContent>
              </Card>

              <Card>
                <CardContent className="p-4">
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="text-sm text-theme-muted">Avg Execution Time</p>
                      <p className="text-2xl font-bold text-theme-primary">
                        {formatDuration(metrics.avgExecutionTime)}
                      </p>
                    </div>
                    <Clock className="h-8 w-8 text-theme-warning" />
                  </div>
                </CardContent>
              </Card>

              <Card>
                <CardContent className="p-4">
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="text-sm text-theme-muted">Active Executions</p>
                      <p className="text-2xl font-bold text-theme-primary">
                        {metrics.activeExecutions.toLocaleString()}
                      </p>
                    </div>
                    <Activity className="h-8 w-8 text-theme-info animate-pulse" />
                  </div>
                </CardContent>
              </Card>
            </div>

            {/* Detailed Statistics */}
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
              <Card>

                  <CardTitle>Execution Status Breakdown</CardTitle>

                <CardContent className="space-y-4">
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2">
                      <CheckCircle className="h-5 w-5 text-theme-success" />
                      <span className="text-theme-muted">Completed</span>
                    </div>
                    <div className="text-right">
                      <span className="text-lg font-semibold text-theme-primary">
                        {metrics.completedExecutions.toLocaleString()}
                      </span>
                      <span className="text-sm text-theme-muted ml-2">
                        ({formatPercentage(metrics.completedExecutions / metrics.totalExecutions)})
                      </span>
                    </div>
                  </div>

                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2">
                      <XCircle className="h-5 w-5 text-theme-error" />
                      <span className="text-theme-muted">Failed</span>
                    </div>
                    <div className="text-right">
                      <span className="text-lg font-semibold text-theme-primary">
                        {metrics.failedExecutions.toLocaleString()}
                      </span>
                      <span className="text-sm text-theme-muted ml-2">
                        ({formatPercentage(metrics.failedExecutions / metrics.totalExecutions)})
                      </span>
                    </div>
                  </div>

                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2">
                      <Activity className="h-5 w-5 text-theme-info" />
                      <span className="text-theme-muted">Currently Running</span>
                    </div>
                    <div className="text-right">
                      <span className="text-lg font-semibold text-theme-primary">
                        {metrics.activeExecutions.toLocaleString()}
                      </span>
                      <span className="text-sm text-theme-muted ml-2">
                        ({formatPercentage(metrics.activeExecutions / metrics.totalExecutions)})
                      </span>
                    </div>
                  </div>
                </CardContent>
              </Card>

              <Card>

                  <CardTitle>Performance Metrics</CardTitle>

                <CardContent className="space-y-4">
                  <div className="flex items-center justify-between">
                    <span className="text-theme-muted">Average Runtime:</span>
                    <span className="font-semibold text-theme-primary">
                      {formatDuration(metrics.avgExecutionTime)}
                    </span>
                  </div>

                  <div className="flex items-center justify-between">
                    <span className="text-theme-muted">Fastest Runtime:</span>
                    <span className="font-semibold text-theme-success">
                      {formatDuration(metrics.minExecutionTime)}
                    </span>
                  </div>

                  <div className="flex items-center justify-between">
                    <span className="text-theme-muted">Slowest Runtime:</span>
                    <span className="font-semibold text-theme-warning">
                      {formatDuration(metrics.maxExecutionTime)}
                    </span>
                  </div>

                  <div className="flex items-center justify-between">
                    <span className="text-theme-muted">Performance Consistency:</span>
                    <span className="font-semibold text-theme-primary">
                      {((metrics.minExecutionTime / metrics.maxExecutionTime) * 100).toFixed(1)}%
                    </span>
                  </div>
                </CardContent>
              </Card>
            </div>

            {/* Daily Activity Chart */}
            {metrics.dailyExecutions && Object.keys(metrics.dailyExecutions).length > 0 && (
              <Card>

                  <CardTitle>Daily Activity</CardTitle>

                <CardContent>
                  <div className="space-y-3">
                    {Object.entries(metrics.dailyExecutions)
                      .sort(([a], [b]) => new Date(a).getTime() - new Date(b).getTime())
                      .slice(-7) // Show last 7 days
                      .map(([date, count]) => {
                        const maxCount = Math.max(...Object.values(metrics.dailyExecutions));
                        const percentage = maxCount > 0 ? (count / maxCount) * 100 : 0;

                        return (
                          <div key={date} className="flex items-center gap-4">
                            <div className="w-20 text-sm text-theme-muted">
                              {new Date(date).toLocaleDateString('en-US', {
                                month: 'short',
                                day: 'numeric'
                              })}
                            </div>
                            <div className="flex-1 bg-theme-surface rounded-full h-2">
                              <div
                                className="bg-theme-interactive-primary h-2 rounded-full transition-all duration-300"
                                style={{ width: `${percentage}%` }}
                              />
                            </div>
                            <div className="w-12 text-sm font-medium text-theme-primary text-right">
                              {count}
                            </div>
                          </div>
                        );
                      })}
                  </div>
                </CardContent>
              </Card>
            )}

            {/* Most Active Users */}
            {metrics.mostActiveUsers && Object.keys(metrics.mostActiveUsers).length > 0 && (
              <Card>

                  <CardTitle>Most Active Users</CardTitle>

                <CardContent>
                  <div className="space-y-3">
                    {Object.entries(metrics.mostActiveUsers)
                      .sort(([,a], [,b]) => b - a)
                      .slice(0, 5) // Show top 5 users
                      .map(([userId, count]) => {
                        const maxCount = Math.max(...Object.values(metrics.mostActiveUsers));
                        const percentage = maxCount > 0 ? (count / maxCount) * 100 : 0;

                        return (
                          <div key={userId} className="flex items-center gap-4">
                            <div className="flex items-center gap-2">
                              <Users className="h-4 w-4 text-theme-muted" />
                              <span className="text-sm text-theme-primary font-medium">
                                User {userId.slice(-8)}
                              </span>
                            </div>
                            <div className="flex-1 bg-theme-surface rounded-full h-2">
                              <div
                                className="bg-theme-interactive-secondary h-2 rounded-full transition-all duration-300"
                                style={{ width: `${percentage}%` }}
                              />
                            </div>
                            <div className="w-12 text-sm font-medium text-theme-primary text-right">
                              {count}
                            </div>
                          </div>
                        );
                      })}
                  </div>
                </CardContent>
              </Card>
            )}
          </>
        ) : (
          <div className="text-center py-12">
            <BarChart3 className="h-16 w-16 text-theme-muted mx-auto mb-4" />
            <p className="text-theme-muted">No execution data available for this workflow.</p>
          </div>
        )}
      </div>
    </Modal>
  );
};