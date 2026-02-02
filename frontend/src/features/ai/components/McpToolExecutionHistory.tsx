import { useState, useEffect, useCallback } from 'react';
import {
  Clock,
  CheckCircle2,
  XCircle,
  Loader2,
  AlertCircle,
  ChevronDown,
  ChevronRight,
  RefreshCw,
  StopCircle,
  User,
  Timer
} from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { mcpApi } from '@/shared/services/ai/McpApiService';
import type { McpToolExecution, McpExecutionHistoryResponse } from '@/shared/services/ai/types/mcp-api-types';
import { useNotifications } from '@/shared/hooks/useNotifications';

interface McpToolExecutionHistoryProps {
  serverId: string;
  toolId: string;
  toolName: string;
  onExecutionSelect?: (execution: McpToolExecution) => void;
  refreshTrigger?: number;
}

export const McpToolExecutionHistory: React.FC<McpToolExecutionHistoryProps> = ({
  serverId,
  toolId,
  toolName,
  onExecutionSelect,
  refreshTrigger
}) => {
  const [data, setData] = useState<McpExecutionHistoryResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [expandedIds, setExpandedIds] = useState<Set<string>>(new Set());
  const [cancellingIds, setCancellingIds] = useState<Set<string>>(new Set());
  const { addNotification } = useNotifications();

  const loadHistory = useCallback(async () => {
    try {
      setLoading(true);
      const response = await mcpApi.getExecutionHistory(serverId, toolId, {
        per_page: 10
      });
      setData(response);
    } catch {
      addNotification({
        type: 'error',
        title: 'Load Failed',
        message: 'Failed to load execution history'
      });
    } finally {
      setLoading(false);
    }
  }, [serverId, toolId, addNotification]);

  useEffect(() => {
    loadHistory();
  }, [loadHistory, refreshTrigger]);

  const handleCancel = async (executionId: string) => {
    setCancellingIds(prev => new Set(prev).add(executionId));
    try {
      await mcpApi.cancelExecution(serverId, toolId, executionId);
      addNotification({
        type: 'success',
        title: 'Execution Cancelled',
        message: 'The execution has been cancelled'
      });
      loadHistory();
    } catch {
      addNotification({
        type: 'error',
        title: 'Cancel Failed',
        message: error instanceof Error ? error.message : 'Failed to cancel execution'
      });
    } finally {
      setCancellingIds(prev => {
        const next = new Set(prev);
        next.delete(executionId);
        return next;
      });
    }
  };

  const toggleExpanded = (id: string) => {
    setExpandedIds(prev => {
      const next = new Set(prev);
      if (next.has(id)) {
        next.delete(id);
      } else {
        next.add(id);
      }
      return next;
    });
  };

  const getStatusIcon = (status: McpToolExecution['status']) => {
    switch (status) {
      case 'completed':
        return <CheckCircle2 className="h-4 w-4 text-theme-success" />;
      case 'failed':
        return <XCircle className="h-4 w-4 text-theme-error" />;
      case 'running':
        return <Loader2 className="h-4 w-4 text-theme-info animate-spin" />;
      case 'pending':
        return <Clock className="h-4 w-4 text-theme-warning" />;
      case 'cancelled':
        return <StopCircle className="h-4 w-4 text-theme-tertiary" />;
      default:
        return <AlertCircle className="h-4 w-4 text-theme-tertiary" />;
    }
  };

  const getStatusBadge = (status: McpToolExecution['status']) => {
    const variants: Record<string, 'success' | 'danger' | 'warning' | 'info' | 'outline'> = {
      completed: 'success',
      failed: 'danger',
      running: 'info',
      pending: 'warning',
      cancelled: 'outline'
    };
    return (
      <Badge variant={variants[status] || 'outline'} size="sm">
        {status.charAt(0).toUpperCase() + status.slice(1)}
      </Badge>
    );
  };

  const formatDuration = (ms?: number) => {
    if (!ms) return '-';
    if (ms < 1000) return `${ms}ms`;
    if (ms < 60000) return `${(ms / 1000).toFixed(1)}s`;
    return `${(ms / 60000).toFixed(1)}m`;
  };

  const formatTime = (timestamp?: string) => {
    if (!timestamp) return '-';
    const date = new Date(timestamp);
    const now = new Date();
    const diff = now.getTime() - date.getTime();

    if (diff < 60000) return 'Just now';
    if (diff < 3600000) return `${Math.floor(diff / 60000)}m ago`;
    if (diff < 86400000) return `${Math.floor(diff / 3600000)}h ago`;
    return date.toLocaleDateString();
  };

  if (loading && !data) {
    return (
      <Card className="p-4">
        <div className="flex items-center justify-center gap-2 text-theme-tertiary">
          <RefreshCw className="h-4 w-4 animate-spin" />
          <span>Loading execution history...</span>
        </div>
      </Card>
    );
  }

  if (!data || data.executions.length === 0) {
    return (
      <Card className="p-4">
        <div className="text-center text-theme-tertiary">
          <Clock className="h-8 w-8 mx-auto mb-2 opacity-50" />
          <p>No execution history for {toolName}</p>
        </div>
      </Card>
    );
  }

  return (
    <div className="space-y-3">
      {/* Header with stats */}
      <div className="flex items-center justify-between">
        <h4 className="text-sm font-medium text-theme-secondary">
          Execution History
        </h4>
        <div className="flex items-center gap-2">
          <div className="flex items-center gap-1 text-xs text-theme-tertiary">
            <span className="text-theme-success">{data.meta.success_count} passed</span>
            <span>|</span>
            <span className="text-theme-error">{data.meta.failed_count} failed</span>
            {data.meta.running_count > 0 && (
              <>
                <span>|</span>
                <span className="text-theme-info">{data.meta.running_count} running</span>
              </>
            )}
          </div>
          <Button
            variant="ghost"
            size="sm"
            onClick={loadHistory}
            disabled={loading}
            title="Refresh history"
          >
            <RefreshCw className={`h-3 w-3 ${loading ? 'animate-spin' : ''}`} />
          </Button>
        </div>
      </div>

      {/* Execution list */}
      <div className="space-y-2">
        {data.executions.map((execution) => {
          const isExpanded = expandedIds.has(execution.id);
          const isCancelling = cancellingIds.has(execution.id);
          const canCancel = execution.status === 'pending' || execution.status === 'running';

          return (
            <Card key={execution.id} className="overflow-hidden">
              {/* Execution header */}
              <div
                className="flex items-center gap-3 p-3 cursor-pointer hover:bg-theme-surface transition-colors"
                onClick={() => toggleExpanded(execution.id)}
              >
                {isExpanded ? (
                  <ChevronDown className="h-4 w-4 text-theme-tertiary flex-shrink-0" />
                ) : (
                  <ChevronRight className="h-4 w-4 text-theme-tertiary flex-shrink-0" />
                )}

                {getStatusIcon(execution.status)}

                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    {getStatusBadge(execution.status)}
                    <span className="text-xs text-theme-tertiary">
                      {formatTime(execution.created_at)}
                    </span>
                  </div>
                </div>

                <div className="flex items-center gap-3 text-xs text-theme-tertiary">
                  {execution.duration_ms && (
                    <div className="flex items-center gap-1">
                      <Timer className="h-3 w-3" />
                      <span>{formatDuration(execution.duration_ms)}</span>
                    </div>
                  )}
                  {execution.user_name && (
                    <div className="flex items-center gap-1">
                      <User className="h-3 w-3" />
                      <span className="truncate max-w-[100px]">{execution.user_name}</span>
                    </div>
                  )}
                </div>

                {canCancel && (
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={(e) => {
                      e.stopPropagation();
                      handleCancel(execution.id);
                    }}
                    disabled={isCancelling}
                    className="text-theme-error hover:bg-theme-error hover:bg-opacity-10"
                  >
                    {isCancelling ? (
                      <Loader2 className="h-3 w-3 animate-spin" />
                    ) : (
                      <StopCircle className="h-3 w-3" />
                    )}
                  </Button>
                )}
              </div>

              {/* Expanded details */}
              {isExpanded && (
                <div className="border-t border-theme px-3 py-2 bg-theme-surface bg-opacity-50">
                  {/* Parameters */}
                  {execution.parameters && Object.keys(execution.parameters).length > 0 && (
                    <div className="mb-2">
                      <p className="text-xs font-medium text-theme-tertiary mb-1">Parameters:</p>
                      <pre className="text-xs bg-theme-bg p-2 rounded overflow-x-auto max-h-32 text-theme-secondary">
                        {JSON.stringify(execution.parameters, null, 2)}
                      </pre>
                    </div>
                  )}

                  {/* Result */}
                  {execution.status === 'completed' && execution.result && (
                    <div className="mb-2">
                      <p className="text-xs font-medium text-theme-tertiary mb-1">Result:</p>
                      <pre className="text-xs bg-theme-bg p-2 rounded overflow-x-auto max-h-32 text-theme-secondary">
                        {JSON.stringify(execution.result, null, 2)}
                      </pre>
                    </div>
                  )}

                  {/* Error message */}
                  {execution.status === 'failed' && execution.error_message && (
                    <div className="mb-2">
                      <p className="text-xs font-medium text-theme-error mb-1">Error:</p>
                      <p className="text-xs text-theme-error bg-theme-error bg-opacity-10 p-2 rounded">
                        {execution.error_message}
                      </p>
                    </div>
                  )}

                  {/* Timestamps */}
                  <div className="flex items-center gap-4 text-xs text-theme-tertiary">
                    <span>Created: {new Date(execution.created_at).toLocaleString()}</span>
                    {execution.started_at && (
                      <span>Started: {new Date(execution.started_at).toLocaleString()}</span>
                    )}
                    {execution.completed_at && (
                      <span>Completed: {new Date(execution.completed_at).toLocaleString()}</span>
                    )}
                  </div>

                  {/* View details button */}
                  {onExecutionSelect && (
                    <Button
                      variant="outline"
                      size="sm"
                      className="mt-2"
                      onClick={() => onExecutionSelect(execution)}
                    >
                      View Full Details
                    </Button>
                  )}
                </div>
              )}
            </Card>
          );
        })}
      </div>

      {/* Pagination info */}
      {data.pagination.total_pages > 1 && (
        <p className="text-xs text-center text-theme-tertiary">
          Showing {data.executions.length} of {data.pagination.total_count} executions
        </p>
      )}
    </div>
  );
};
