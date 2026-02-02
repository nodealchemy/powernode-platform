import React, { useState, useEffect } from 'react';
import {
  Clock,
  CheckCircle,
  XCircle,
  AlertCircle,
  Loader2,
  RefreshCw,
  StopCircle,
  Send,
  FileText,
  Code,
} from 'lucide-react';
import { Card, CardHeader, CardContent } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Loading } from '@/shared/components/ui/Loading';
import { a2aTasksApiService } from '@/shared/services/ai';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { cn } from '@/shared/utils/cn';
import type { A2aTask, A2aArtifact } from '@/shared/services/ai/types/a2a-types';

interface TaskDetailProps {
  taskId: string;
  onClose?: () => void;
  className?: string;
}

const statusConfig: Record<
  string,
  { icon: React.FC<{ className?: string }>; variant: 'success' | 'danger' | 'warning' | 'info' | 'outline'; label: string; color: string }
> = {
  pending: { icon: Clock, variant: 'outline', label: 'Pending', color: 'text-theme-muted' },
  active: { icon: Loader2, variant: 'info', label: 'Active', color: 'text-theme-info' },
  completed: { icon: CheckCircle, variant: 'success', label: 'Completed', color: 'text-theme-success' },
  failed: { icon: XCircle, variant: 'danger', label: 'Failed', color: 'text-theme-danger' },
  cancelled: { icon: AlertCircle, variant: 'warning', label: 'Cancelled', color: 'text-theme-warning' },
  input_required: { icon: AlertCircle, variant: 'warning', label: 'Input Required', color: 'text-theme-warning' },
};

export const TaskDetail: React.FC<TaskDetailProps> = ({ taskId, onClose, className }) => {
  const [task, setTask] = useState<A2aTask | null>(null);
  const [artifacts, setArtifacts] = useState<A2aArtifact[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [actionLoading, setActionLoading] = useState<string | null>(null);
  const [inputValue, setInputValue] = useState('');
  const [showInput, setShowInput] = useState(false);
  const [showOutput, setShowOutput] = useState(false);

  const { addNotification } = useNotifications();

  useEffect(() => {
    loadTask();
  }, [taskId]);

  const loadTask = async () => {
    try {
      setLoading(true);
      setError(null);

      const [taskResponse, artifactsResponse] = await Promise.all([
        a2aTasksApiService.getTaskDetails(taskId),
        a2aTasksApiService.getArtifacts(taskId).catch(() => ({ artifacts: [] })),
      ]);

      setTask(taskResponse.task);
      setArtifacts(artifactsResponse.artifacts || []);
    } catch {
      setError(err instanceof Error ? err.message : 'Failed to load task');
    } finally {
      setLoading(false);
    }
  };

  const handleCancel = async () => {
    try {
      setActionLoading('cancel');
      await a2aTasksApiService.cancelTask(taskId, 'Cancelled by user');
      addNotification({ type: 'success', title: 'Cancelled', message: 'Task has been cancelled' });
      await loadTask(); // Reload to get updated task state
    } catch {
      addNotification({ type: 'error', title: 'Error', message: 'Failed to cancel task' });
    } finally {
      setActionLoading(null);
    }
  };

  const handleProvideInput = async () => {
    if (!inputValue.trim()) return;
    try {
      setActionLoading('input');
      let parsedInput: unknown;
      try {
        parsedInput = JSON.parse(inputValue);
      } catch {
        parsedInput = inputValue;
      }
      await a2aTasksApiService.provideInput(taskId, parsedInput);
      setInputValue('');
      addNotification({ type: 'success', title: 'Input Sent', message: 'Input provided to task' });
      await loadTask(); // Reload to get updated task state
    } catch {
      addNotification({ type: 'error', title: 'Error', message: 'Failed to provide input' });
    } finally {
      setActionLoading(null);
    }
  };

  const formatDate = (dateStr?: string) => {
    if (!dateStr) return 'N/A';
    return new Date(dateStr).toLocaleString();
  };

  const formatDuration = (startedAt?: string, completedAt?: string) => {
    if (!startedAt) return 'N/A';
    const start = new Date(startedAt).getTime();
    const end = completedAt ? new Date(completedAt).getTime() : Date.now();
    const duration = end - start;

    if (duration < 1000) return `${duration}ms`;
    if (duration < 60000) return `${(duration / 1000).toFixed(1)}s`;
    return `${(duration / 60000).toFixed(1)}m`;
  };

  if (loading) {
    return (
      <Card className={className}>
        <CardContent className="flex items-center justify-center py-12">
          <Loading size="lg" message="Loading task details..." />
        </CardContent>
      </Card>
    );
  }

  if (error || !task) {
    return (
      <Card className={className}>
        <CardContent className="py-12 text-center">
          <AlertCircle className="h-12 w-12 text-theme-danger mx-auto mb-4" />
          <p className="text-theme-danger">{error || 'Task not found'}</p>
          <Button variant="outline" size="sm" onClick={onClose} className="mt-4">
            Go Back
          </Button>
        </CardContent>
      </Card>
    );
  }

  const config = statusConfig[task.status] || statusConfig.pending;
  const StatusIcon = config.icon;
  const canCancel = ['pending', 'active', 'input_required'].includes(task.status);
  const needsInput = task.status === 'input_required';

  return (
    <div className={cn('space-y-6', className)}>
      {/* Header */}
      <Card>
        <CardContent className="p-6">
          <div className="flex items-start justify-between">
            <div className="flex items-start gap-4">
              <div
                className={cn(
                  'p-3 rounded-xl',
                  task.status === 'completed' && 'bg-theme-success/10',
                  task.status === 'failed' && 'bg-theme-danger/10',
                  task.status === 'active' && 'bg-theme-info/10',
                  ['pending', 'cancelled', 'input_required'].includes(task.status) &&
                    'bg-theme-muted/10'
                )}
              >
                <StatusIcon
                  className={cn(
                    'h-6 w-6',
                    config.color,
                    task.status === 'active' && 'animate-spin'
                  )}
                />
              </div>
              <div>
                <div className="flex items-center gap-3 mb-1">
                  <h1 className="text-lg font-bold text-theme-primary font-mono">
                    {task.id.substring(0, 16)}...
                  </h1>
                  <Badge variant={config.variant} size="sm">
                    {config.label}
                  </Badge>
                </div>
                <p className="text-sm text-theme-muted">Task ID: {task.id}</p>
              </div>
            </div>

            <div className="flex items-center gap-2">
              <Button variant="outline" size="sm" onClick={loadTask} disabled={loading}>
                <RefreshCw className={cn('h-4 w-4 mr-2', loading && 'animate-spin')} />
                Refresh
              </Button>
              {canCancel && (
                <Button
                  variant="danger"
                  size="sm"
                  onClick={handleCancel}
                  disabled={actionLoading === 'cancel'}
                >
                  <StopCircle className="h-4 w-4 mr-2" />
                  Cancel
                </Button>
              )}
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Input required prompt */}
      {needsInput && (
        <Card className="border-theme-warning">
          <CardHeader
            title="Input Required"
            icon={<AlertCircle className="h-5 w-5 text-theme-warning" />}
          />
          <CardContent className="space-y-4">
            <p className="text-sm text-theme-secondary">
              This task is waiting for additional input to continue.
            </p>
            <div className="flex gap-2">
              <Input
                value={inputValue}
                onChange={(e) => setInputValue(e.target.value)}
                placeholder='Enter input (text or JSON)...'
                className="flex-1"
              />
              <Button
                variant="primary"
                onClick={handleProvideInput}
                disabled={!inputValue.trim() || actionLoading === 'input'}
              >
                <Send className="h-4 w-4 mr-2" />
                Send
              </Button>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Error message */}
      {task.status === 'failed' && (
        <Card className="border-theme-danger">
          <CardHeader
            title="Error"
            icon={<XCircle className="h-5 w-5 text-theme-danger" />}
          />
          <CardContent>
            <p className="text-sm text-theme-danger whitespace-pre-wrap">
              {task.error_message || 'Unknown error'}
            </p>
          </CardContent>
        </Card>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Main content */}
        <div className="lg:col-span-2 space-y-6">
          {/* Input */}
          <Card>
            <CardHeader
              title="Input"
              icon={<Code className="h-5 w-5" />}
              action={
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => setShowInput(!showInput)}
                >
                  {showInput ? 'Hide' : 'Show'}
                </Button>
              }
            />
            {showInput && (
              <CardContent>
                <pre className="bg-theme-surface-dark p-4 rounded-lg text-xs overflow-x-auto max-h-64">
                  <code className="text-theme-primary">
                    {JSON.stringify(task.input, null, 2) || 'null'}
                  </code>
                </pre>
              </CardContent>
            )}
          </Card>

          {/* Output */}
          {task.output && Object.keys(task.output).length > 0 && (
            <Card>
              <CardHeader
                title="Output"
                icon={<Code className="h-5 w-5" />}
                action={
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => setShowOutput(!showOutput)}
                  >
                    {showOutput ? 'Hide' : 'Show'}
                  </Button>
                }
              />
              {showOutput && (
                <CardContent>
                  <pre className="bg-theme-surface-dark p-4 rounded-lg text-xs overflow-x-auto max-h-64">
                    <code className="text-theme-primary">
                      {JSON.stringify(task.output, null, 2)}
                    </code>
                  </pre>
                </CardContent>
              )}
            </Card>
          )}

          {/* Artifacts */}
          {artifacts.length > 0 && (
            <Card>
              <CardHeader
                title={`Artifacts (${artifacts.length})`}
                icon={<FileText className="h-5 w-5" />}
              />
              <CardContent>
                <div className="space-y-2">
                  {artifacts.map((artifact, idx) => (
                    <div
                      key={artifact.id || idx}
                      className="p-3 bg-theme-surface rounded-lg flex items-center justify-between"
                    >
                      <div className="flex items-center gap-3">
                        <FileText className="h-5 w-5 text-theme-muted" />
                        <div>
                          <div className="font-medium text-theme-primary">
                            {artifact.name || `Artifact ${idx + 1}`}
                          </div>
                          {artifact.mimeType && (
                            <div className="text-xs text-theme-muted">{artifact.mimeType}</div>
                          )}
                        </div>
                      </div>
                      <Badge variant="outline" size="sm">
                        {artifact.id?.substring(0, 8) || 'N/A'}
                      </Badge>
                    </div>
                  ))}
                </div>
              </CardContent>
            </Card>
          )}
        </div>

        {/* Sidebar */}
        <div className="space-y-6">
          {/* Timeline */}
          <Card>
            <CardHeader title="Timeline" icon={<Clock className="h-5 w-5" />} />
            <CardContent className="space-y-3 text-sm">
              <div className="flex justify-between">
                <span className="text-theme-secondary">Created</span>
                <span className="text-theme-primary">
                  {formatDate(task.created_at)}
                </span>
              </div>
              {task.started_at && (
                <div className="flex justify-between">
                  <span className="text-theme-secondary">Started</span>
                  <span className="text-theme-primary">
                    {formatDate(task.started_at)}
                  </span>
                </div>
              )}
              {task.completed_at && (
                <div className="flex justify-between">
                  <span className="text-theme-secondary">Completed</span>
                  <span className="text-theme-primary">
                    {formatDate(task.completed_at)}
                  </span>
                </div>
              )}
              <div className="flex justify-between pt-2 border-t border-theme">
                <span className="text-theme-secondary">Duration</span>
                <span className="text-theme-primary font-medium">
                  {formatDuration(task.started_at, task.completed_at)}
                </span>
              </div>
            </CardContent>
          </Card>

          {/* Details */}
          <Card>
            <CardHeader title="Details" />
            <CardContent className="space-y-3 text-sm">
              {task.sequence_number !== undefined && (
                <div className="flex justify-between">
                  <span className="text-theme-secondary">Sequence #</span>
                  <span className="text-theme-primary">
                    {task.sequence_number}
                  </span>
                </div>
              )}
              {task.workflow_run_id && (
                <div className="flex justify-between">
                  <span className="text-theme-secondary">Workflow Run</span>
                  <span className="text-theme-primary font-mono text-xs">
                    {task.workflow_run_id.substring(0, 8)}...
                  </span>
                </div>
              )}
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
};

export default TaskDetail;
