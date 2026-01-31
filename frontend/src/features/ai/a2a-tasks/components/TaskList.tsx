import React, { useState, useEffect, useCallback } from 'react';
import {
  Activity,
  Clock,
  CheckCircle,
  XCircle,
  AlertCircle,
  Loader2,
  Search,
  Filter,
  RefreshCw,
  ArrowRight,
} from 'lucide-react';
import { Card, CardHeader, CardContent } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';
import { Loading } from '@/shared/components/ui/Loading';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { a2aTasksApiService } from '@/shared/services/ai';
import { cn } from '@/shared/utils/cn';
import type { A2aTask, A2aTaskFilters } from '@/shared/services/ai/types/a2a-types';

interface TaskListProps {
  onSelectTask?: (task: A2aTask) => void;
  className?: string;
}

const statusConfig: Record<
  string,
  { icon: React.FC<{ className?: string }>; variant: 'success' | 'danger' | 'warning' | 'info' | 'outline'; label: string }
> = {
  pending: { icon: Clock, variant: 'outline', label: 'Pending' },
  active: { icon: Loader2, variant: 'info', label: 'Active' },
  completed: { icon: CheckCircle, variant: 'success', label: 'Completed' },
  failed: { icon: XCircle, variant: 'danger', label: 'Failed' },
  cancelled: { icon: AlertCircle, variant: 'warning', label: 'Cancelled' },
  input_required: { icon: AlertCircle, variant: 'warning', label: 'Input Required' },
};

export const TaskList: React.FC<TaskListProps> = ({ onSelectTask, className }) => {
  const [tasks, setTasks] = useState<A2aTask[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [statusFilter, setStatusFilter] = useState<string>('');
  const [searchQuery, setSearchQuery] = useState('');
  const [totalCount, setTotalCount] = useState(0);

  const loadTasks = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);

      const filters: A2aTaskFilters = { per_page: 50 };
      if (statusFilter) filters.status = statusFilter as A2aTaskFilters['status'];

      const response = await a2aTasksApiService.getTasks(filters);
      setTasks(response.items || []);
      setTotalCount(response.total || 0);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load tasks');
    } finally {
      setLoading(false);
    }
  }, [statusFilter]);

  useEffect(() => {
    loadTasks();
  }, [loadTasks]);

  // Filter tasks by search query locally
  const filteredTasks = searchQuery
    ? tasks.filter(
        (task) =>
          task.task_id.toLowerCase().includes(searchQuery.toLowerCase()) ||
          task.from_agent?.name?.toLowerCase().includes(searchQuery.toLowerCase()) ||
          task.to_agent?.name?.toLowerCase().includes(searchQuery.toLowerCase())
      )
    : tasks;

  const formatDuration = (startedAt?: string, completedAt?: string) => {
    if (!startedAt) return '-';
    const start = new Date(startedAt).getTime();
    const end = completedAt ? new Date(completedAt).getTime() : Date.now();
    const duration = end - start;

    if (duration < 1000) return `${duration}ms`;
    if (duration < 60000) return `${(duration / 1000).toFixed(1)}s`;
    return `${(duration / 60000).toFixed(1)}m`;
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

  if (loading && tasks.length === 0) {
    return (
      <Card className={className}>
        <CardContent className="flex items-center justify-center py-12">
          <Loading size="lg" message="Loading A2A tasks..." />
        </CardContent>
      </Card>
    );
  }

  return (
    <div className={cn('space-y-4', className)}>
      {/* Filters */}
      <Card>
        <CardContent className="p-4">
          <div className="flex flex-wrap items-center gap-4">
            <div className="flex-1 min-w-64">
              <div className="relative">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-theme-muted" />
                <Input
                  placeholder="Search by task ID or agent..."
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  className="pl-10"
                />
              </div>
            </div>

            <div className="flex items-center gap-2">
              <Filter className="h-4 w-4 text-theme-muted" />
              <Select
                value={statusFilter}
                onChange={(e) => setStatusFilter(e.target.value)}
                className="w-36"
              >
                <option value="">All Status</option>
                <option value="pending">Pending</option>
                <option value="active">Active</option>
                <option value="completed">Completed</option>
                <option value="failed">Failed</option>
                <option value="cancelled">Cancelled</option>
                <option value="input_required">Input Required</option>
              </Select>
            </div>

            <Button variant="outline" size="sm" onClick={loadTasks} disabled={loading}>
              <RefreshCw className={cn('h-4 w-4 mr-2', loading && 'animate-spin')} />
              Refresh
            </Button>
          </div>
        </CardContent>
      </Card>

      {/* Stats bar */}
      <div className="flex items-center justify-between text-sm text-theme-muted">
        <span>
          {filteredTasks.length} of {totalCount} task{totalCount !== 1 ? 's' : ''}
        </span>
      </div>

      {/* Error state */}
      {error && (
        <div className="p-4 bg-theme-danger/10 border border-theme-danger/30 rounded-lg">
          <div className="flex items-center gap-2 text-theme-danger">
            <AlertCircle className="h-4 w-4" />
            <span>{error}</span>
          </div>
        </div>
      )}

      {/* Empty state */}
      {!loading && filteredTasks.length === 0 && !error && (
        <EmptyState
          icon={Activity}
          title="No A2A tasks found"
          description="A2A tasks will appear here when agents communicate"
        />
      )}

      {/* Tasks list */}
      <div className="space-y-3">
        {filteredTasks.map((task) => {
          const config = statusConfig[task.status] || statusConfig.pending;
          const StatusIcon = config.icon;

          return (
            <Card
              key={task.id}
              className="cursor-pointer hover:border-theme-primary/50 transition-colors"
              onClick={() => onSelectTask?.(task)}
            >
              <CardContent className="p-4">
                <div className="flex items-start justify-between gap-4">
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-3 mb-2">
                      <StatusIcon
                        className={cn(
                          'h-5 w-5',
                          task.status === 'active' && 'animate-spin text-theme-info',
                          task.status === 'completed' && 'text-theme-success',
                          task.status === 'failed' && 'text-theme-danger',
                          task.status === 'cancelled' && 'text-theme-warning',
                          task.status === 'pending' && 'text-theme-muted',
                          task.status === 'input_required' && 'text-theme-warning'
                        )}
                      />
                      <span className="font-mono text-sm text-theme-primary">
                        {task.task_id.substring(0, 8)}...
                      </span>
                      <Badge variant={config.variant} size="sm">
                        {config.label}
                      </Badge>
                    </div>

                    {/* Agent flow */}
                    <div className="flex items-center gap-2 text-sm text-theme-secondary mb-2">
                      <span className="font-medium">
                        {task.from_agent?.name || 'Unknown Agent'}
                      </span>
                      <ArrowRight className="h-4 w-4 text-theme-muted" />
                      <span className="font-medium">
                        {task.to_agent?.name || 'Unknown Agent'}
                      </span>
                    </div>

                    {/* Error message */}
                    {task.error_message && (
                      <p className="text-sm text-theme-danger mb-2 line-clamp-1">
                        {task.error_message}
                      </p>
                    )}

                    {/* Metadata */}
                    <div className="flex items-center gap-4 text-xs text-theme-muted">
                      <span className="flex items-center gap-1">
                        <Clock className="h-3 w-3" />
                        {formatTime(task.created_at)}
                      </span>
                      {task.started_at && (
                        <span>Duration: {formatDuration(task.started_at, task.completed_at)}</span>
                      )}
                      {task.sequence_number !== undefined && (
                        <span>Seq #{task.sequence_number}</span>
                      )}
                    </div>
                  </div>

                  {/* Artifact count */}
                  {task.artifacts && task.artifacts.length > 0 && (
                    <Badge variant="outline" size="sm">
                      {task.artifacts.length} artifact{task.artifacts.length !== 1 ? 's' : ''}
                    </Badge>
                  )}
                </div>
              </CardContent>
            </Card>
          );
        })}
      </div>
    </div>
  );
};

export default TaskList;
