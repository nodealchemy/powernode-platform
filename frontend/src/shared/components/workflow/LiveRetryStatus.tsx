import React from 'react';
import { RefreshCw, CheckCircle, XCircle, Clock, AlertTriangle, TrendingUp } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { useRetryStatusUpdates } from '@/shared/hooks/useRetryStatusUpdates';

export interface LiveRetryStatusProps {
  workflowRunId: string;
  nodeId?: string;
  compact?: boolean;
  className?: string;
}

export const LiveRetryStatus: React.FC<LiveRetryStatusProps> = ({
  workflowRunId,
  nodeId,
  compact = false,
  className = ''
}) => {
  const {
    isConnected,
    retryUpdates,
    latestUpdate,
    retryStats,
    getNodeRetryStatus
  } = useRetryStatusUpdates({
    workflowRunId,
    enabled: true
  });

  // Filter updates for specific node if provided
  const relevantUpdates = nodeId
    ? retryUpdates.filter(update => update.node_id === nodeId)
    : retryUpdates;

  const nodeStatus = nodeId ? getNodeRetryStatus(nodeId) : latestUpdate;

  const getStatusIcon = (type: string) => {
    switch (type) {
      case 'node_retry_scheduled':
        return <Clock className="h-4 w-4 text-theme-info" />;
      case 'node_retry_started':
        return <RefreshCw className="h-4 w-4 text-theme-info animate-spin" />;
      case 'node_retry_completed':
        return <CheckCircle className="h-4 w-4 text-theme-success" />;
      case 'node_retry_failed':
        return <XCircle className="h-4 w-4 text-theme-danger" />;
      case 'retries_exhausted':
        return <AlertTriangle className="h-4 w-4 text-theme-warning" />;
      default:
        return <RefreshCw className="h-4 w-4 text-theme-secondary" />;
    }
  };

  const getStatusLabel = (type: string) => {
    switch (type) {
      case 'node_retry_scheduled':
        return 'Retry Scheduled';
      case 'node_retry_started':
        return 'Retrying...';
      case 'node_retry_completed':
        return 'Retry Successful';
      case 'node_retry_failed':
        return 'Retry Failed';
      case 'retries_exhausted':
        return 'Retries Exhausted';
      default:
        return 'Unknown Status';
    }
  };

  const formatDelay = (ms: number) => {
    if (ms < 1000) return `${ms}ms`;
    if (ms < 60000) return `${(ms / 1000).toFixed(1)}s`;
    return `${(ms / 60000).toFixed(1)}m`;
  };

  const formatTimeAgo = (timestamp: string) => {
    const seconds = Math.floor((Date.now() - new Date(timestamp).getTime()) / 1000);
    if (seconds < 60) return `${seconds}s ago`;
    if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
    return `${Math.floor(seconds / 3600)}h ago`;
  };

  if (compact && nodeStatus) {
    return (
      <div className={`flex items-center gap-2 ${className}`}>
        {getStatusIcon(nodeStatus.type)}
        <div className="flex-1">
          <div className="text-xs font-medium text-theme-primary">
            {getStatusLabel(nodeStatus.type)}
          </div>
          {nodeStatus.retry_stats && (
            <div className="text-xs text-theme-muted">
              Attempt {nodeStatus.retry_stats.current_attempt}/{nodeStatus.retry_attempt + nodeStatus.retry_stats.retries_remaining}
            </div>
          )}
        </div>
        {!isConnected && (
          <div className="h-2 w-2 rounded-full bg-theme-warning" title="Disconnected" />
        )}
        {isConnected && (
          <div className="h-2 w-2 rounded-full bg-theme-success animate-pulse" title="Connected" />
        )}
      </div>
    );
  }

  return (
    <Card className={`p-4 ${className}`}>
      {/* Header */}
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-2">
          <RefreshCw className="h-5 w-5 text-theme-interactive-primary" />
          <h3 className="text-lg font-semibold text-theme-primary">Live Retry Status</h3>
        </div>
        <div className="flex items-center gap-2">
          <div className={`h-2 w-2 rounded-full ${isConnected ? 'bg-theme-success animate-pulse' : 'bg-theme-warning'}`} />
          <span className="text-xs text-theme-secondary">
            {isConnected ? 'Connected' : 'Disconnected'}
          </span>
        </div>
      </div>

      {/* Statistics */}
      <div className="grid grid-cols-4 gap-3 mb-4">
        <div className="p-3 bg-theme-background rounded-lg">
          <div className="flex items-center gap-2 mb-1">
            <TrendingUp className="h-4 w-4 text-theme-secondary" />
            <span className="text-xs text-theme-muted">Total</span>
          </div>
          <div className="text-2xl font-bold text-theme-primary">{retryStats.total_retries}</div>
        </div>

        <div className="p-3 bg-theme-success/10 rounded-lg">
          <div className="flex items-center gap-2 mb-1">
            <CheckCircle className="h-4 w-4 text-theme-success" />
            <span className="text-xs text-theme-success">Success</span>
          </div>
          <div className="text-2xl font-bold text-theme-success">{retryStats.successful_retries}</div>
        </div>

        <div className="p-3 bg-theme-danger/10 rounded-lg">
          <div className="flex items-center gap-2 mb-1">
            <XCircle className="h-4 w-4 text-theme-danger" />
            <span className="text-xs text-theme-danger">Failed</span>
          </div>
          <div className="text-2xl font-bold text-theme-danger">{retryStats.failed_retries}</div>
        </div>

        <div className="p-3 bg-theme-info/10 rounded-lg">
          <div className="flex items-center gap-2 mb-1">
            <RefreshCw className="h-4 w-4 text-theme-info" />
            <span className="text-xs text-theme-info">Active</span>
          </div>
          <div className="text-2xl font-bold text-theme-info">{retryStats.active_retries}</div>
        </div>
      </div>

      {/* Recent updates */}
      {relevantUpdates.length > 0 ? (
        <div className="space-y-2 max-h-64 overflow-y-auto">
          <h4 className="text-sm font-medium text-theme-secondary mb-2">Recent Activity</h4>
          {relevantUpdates.slice(-10).reverse().map((update, index) => (
            <div
              key={`${update.node_execution_id}-${index}`}
              className="p-3 bg-theme-background rounded-lg"
            >
              <div className="flex items-start gap-3">
                {getStatusIcon(update.type)}
                <div className="flex-1">
                  <div className="flex items-center justify-between mb-1">
                    <div className="text-sm font-medium text-theme-primary">
                      {getStatusLabel(update.type)}
                    </div>
                    <div className="text-xs text-theme-muted">
                      {formatTimeAgo(update.timestamp)}
                    </div>
                  </div>

                  <div className="text-xs text-theme-secondary mb-1">
                    Node: {update.node_id}
                  </div>

                  <div className="flex items-center gap-3 text-xs text-theme-muted">
                    {update.retry_attempt !== undefined && (
                      <span>Attempt: {update.retry_attempt}/{update.max_retries}</span>
                    )}
                    {update.delay_ms !== undefined && (
                      <span>Delay: {formatDelay(update.delay_ms)}</span>
                    )}
                    {update.error_type && (
                      <span className="px-2 py-0.5 bg-theme-danger/10 text-theme-danger rounded">
                        {update.error_type}
                      </span>
                    )}
                  </div>

                  {update.retry_stats && (
                    <div className="mt-2 p-2 bg-theme-surface rounded text-xs">
                      <div className="flex items-center justify-between">
                        <span className="text-theme-muted">Retries Remaining:</span>
                        <span className="text-theme-primary font-medium">
                          {update.retry_stats.retries_remaining}
                        </span>
                      </div>
                      {update.retry_stats.next_retry_delay_ms !== undefined && (
                        <div className="flex items-center justify-between mt-1">
                          <span className="text-theme-muted">Next Delay:</span>
                          <span className="text-theme-primary font-medium">
                            {formatDelay(update.retry_stats.next_retry_delay_ms)}
                          </span>
                        </div>
                      )}
                    </div>
                  )}
                </div>
              </div>
            </div>
          ))}
        </div>
      ) : (
        <div className="text-center py-8">
          <RefreshCw className="h-12 w-12 text-theme-secondary mx-auto mb-3 opacity-50" />
          <p className="text-sm text-theme-secondary">No retry activity yet</p>
          <p className="text-xs text-theme-muted mt-1">
            Retry events will appear here in real-time
          </p>
        </div>
      )}

      {/* Exhausted retries warning */}
      {retryStats.exhausted_retries > 0 && (
        <div className="mt-4 p-3 bg-theme-warning/10 border border-theme-warning/20 rounded-lg">
          <div className="flex items-start gap-2">
            <AlertTriangle className="h-4 w-4 text-theme-warning mt-0.5 flex-shrink-0" />
            <div className="text-sm text-theme-warning">
              {retryStats.exhausted_retries} node{retryStats.exhausted_retries > 1 ? 's have' : ' has'} exhausted all retry attempts
            </div>
          </div>
        </div>
      )}
    </Card>
  );
};
