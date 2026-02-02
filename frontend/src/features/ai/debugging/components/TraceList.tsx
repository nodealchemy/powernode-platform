import React, { useState, useEffect } from 'react';
import {
  Clock,
  DollarSign,
  Hash,
  AlertCircle,
  CheckCircle,
  XCircle,
  Loader2,
  RefreshCw,
  Filter,
  Layers
} from 'lucide-react';
import { Card, CardHeader, CardContent } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { Select } from '@/shared/components/ui/Select';
import { Loading } from '@/shared/components/ui/Loading';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { cn } from '@/shared/utils/cn';

// Types
interface TraceSummary {
  trace_id: string;
  name: string;
  type: string;
  status: 'pending' | 'running' | 'completed' | 'failed' | 'cancelled';
  started_at: string | null;
  completed_at: string | null;
  duration_ms: number | null;
  span_count: number;
  total_tokens: number;
  total_cost: number;
  error: boolean;
}

interface TraceListProps {
  onSelectTrace: (traceId: string) => void;
  className?: string;
}

// Status configuration
const statusConfig: Record<string, { icon: React.FC<{ className?: string }>; variant: 'success' | 'danger' | 'warning' | 'info' | 'outline' }> = {
  pending: { icon: Clock, variant: 'outline' },
  running: { icon: Loader2, variant: 'info' },
  completed: { icon: CheckCircle, variant: 'success' },
  failed: { icon: XCircle, variant: 'danger' },
  cancelled: { icon: AlertCircle, variant: 'warning' },
};

// Trace type options
const traceTypeOptions = [
  { value: '', label: 'All Types' },
  { value: 'agent', label: 'Agent' },
  { value: 'workflow', label: 'Workflow' },
  { value: 'conversation', label: 'Conversation' },
  { value: 'tool', label: 'Tool' },
  { value: 'mcp', label: 'MCP' },
  { value: 'batch', label: 'Batch' },
];

// Status options
const statusOptions = [
  { value: '', label: 'All Statuses' },
  { value: 'running', label: 'Running' },
  { value: 'completed', label: 'Completed' },
  { value: 'failed', label: 'Failed' },
  { value: 'cancelled', label: 'Cancelled' },
];

/**
 * TraceList - Lists recent execution traces with filtering
 */
export const TraceList: React.FC<TraceListProps> = ({ onSelectTrace, className }) => {
  const [traces, setTraces] = useState<TraceSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [typeFilter, setTypeFilter] = useState('');
  const [statusFilter, setStatusFilter] = useState('');

  const loadTraces = async () => {
    try {
      setLoading(true);
      setError(null);

      const params = new URLSearchParams();
      if (typeFilter) params.append('type', typeFilter);
      if (statusFilter) params.append('status', statusFilter);
      params.append('limit', '50');

      const response = await fetch(`/api/v1/ai/execution_traces?${params}`, {
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        credentials: 'include',
      });

      if (!response.ok) {
        throw new Error('Failed to load traces');
      }

      const data = await response.json();
      setTraces(data.data || []);
    } catch {
      setError(err instanceof Error ? err.message : 'Failed to load traces');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadTraces();
  }, [typeFilter, statusFilter]);

  const formatDuration = (ms: number | null) => {
    if (ms === null) return '-';
    if (ms < 1000) return `${ms}ms`;
    if (ms < 60000) return `${(ms / 1000).toFixed(1)}s`;
    return `${(ms / 60000).toFixed(1)}m`;
  };

  const formatCost = (cost: number) => {
    return `$${cost.toFixed(4)}`;
  };

  const formatTime = (timestamp: string | null) => {
    if (!timestamp) return '-';
    const date = new Date(timestamp);
    const now = new Date();
    const diff = now.getTime() - date.getTime();

    if (diff < 60000) return 'Just now';
    if (diff < 3600000) return `${Math.floor(diff / 60000)}m ago`;
    if (diff < 86400000) return `${Math.floor(diff / 3600000)}h ago`;
    return date.toLocaleDateString();
  };

  if (loading && traces.length === 0) {
    return (
      <Card className={className}>
        <CardContent className="flex items-center justify-center py-12">
          <Loading size="lg" message="Loading traces..." />
        </CardContent>
      </Card>
    );
  }

  return (
    <Card className={className}>
      <CardHeader
        title="Execution Traces"
        icon={<Layers className="h-5 w-5" />}
        action={
          <Button
            variant="outline"
            size="sm"
            onClick={loadTraces}
            disabled={loading}
          >
            <RefreshCw className={cn('h-4 w-4 mr-2', loading && 'animate-spin')} />
            Refresh
          </Button>
        }
      />

      <CardContent className="space-y-4">
        {/* Filters */}
        <div className="flex items-center gap-4">
          <div className="flex items-center gap-2">
            <Filter className="h-4 w-4 text-theme-muted" />
            <Select
              value={typeFilter}
              onChange={(value) => setTypeFilter(value)}
              className="w-36"
            >
              {traceTypeOptions.map(opt => (
                <option key={opt.value} value={opt.value}>{opt.label}</option>
              ))}
            </Select>
          </div>
          <Select
            value={statusFilter}
            onChange={(value) => setStatusFilter(value)}
            className="w-36"
          >
            {statusOptions.map(opt => (
              <option key={opt.value} value={opt.value}>{opt.label}</option>
            ))}
          </Select>
        </div>

        {/* Error state */}
        {error && (
          <div className="p-4 bg-theme-danger/10 border border-theme-danger/30 rounded">
            <div className="flex items-center gap-2 text-theme-danger">
              <AlertCircle className="h-4 w-4" />
              <span>{error}</span>
            </div>
          </div>
        )}

        {/* Empty state */}
        {!loading && traces.length === 0 && (
          <EmptyState
            icon={Layers}
            title="No traces found"
            description="Execution traces will appear here when AI operations run"
          />
        )}

        {/* Trace list */}
        <div className="space-y-2">
          {traces.map(trace => {
            const StatusIcon = statusConfig[trace.status]?.icon || AlertCircle;
            const statusVariant = statusConfig[trace.status]?.variant || 'outline';

            return (
              <div
                key={trace.trace_id}
                className="p-3 border border-theme rounded-lg hover:bg-theme-surface cursor-pointer transition-colors"
                onClick={() => onSelectTrace(trace.trace_id)}
              >
                <div className="flex items-center justify-between mb-2">
                  <div className="flex items-center gap-2">
                    <StatusIcon
                      className={cn(
                        'h-4 w-4',
                        trace.status === 'running' && 'animate-spin text-theme-info',
                        trace.status === 'completed' && 'text-theme-success',
                        trace.status === 'failed' && 'text-theme-danger',
                        trace.status === 'cancelled' && 'text-theme-warning'
                      )}
                    />
                    <span className="font-medium text-theme-primary">{trace.name}</span>
                  </div>
                  <div className="flex items-center gap-2">
                    <Badge variant="outline" size="sm">{trace.type}</Badge>
                    <Badge variant={statusVariant} size="sm">{trace.status}</Badge>
                  </div>
                </div>

                <div className="grid grid-cols-5 gap-4 text-xs text-theme-muted">
                  <div className="flex items-center gap-1">
                    <Clock className="h-3 w-3" />
                    {formatTime(trace.started_at)}
                  </div>
                  <div className="flex items-center gap-1">
                    <Layers className="h-3 w-3" />
                    {trace.span_count} spans
                  </div>
                  <div className="flex items-center gap-1">
                    <Clock className="h-3 w-3" />
                    {formatDuration(trace.duration_ms)}
                  </div>
                  <div className="flex items-center gap-1">
                    <Hash className="h-3 w-3" />
                    {trace.total_tokens.toLocaleString()} tok
                  </div>
                  <div className="flex items-center gap-1">
                    <DollarSign className="h-3 w-3" />
                    {formatCost(trace.total_cost)}
                  </div>
                </div>

                {trace.error && (
                  <div className="mt-2 flex items-center gap-1 text-xs text-theme-danger">
                    <AlertCircle className="h-3 w-3" />
                    <span>Has errors</span>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      </CardContent>
    </Card>
  );
};

export default TraceList;
