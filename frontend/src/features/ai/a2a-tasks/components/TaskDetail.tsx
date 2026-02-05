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
import type { A2aTaskJson, A2aArtifact } from '@/shared/services/ai/types/a2a-types';

interface TaskDetailProps {
  taskId: string;
  onClose?: () => void;
  className?: string;
}

// Map A2A protocol status states to UI config
const statusConfig: Record<
  string,
  { icon: React.FC<{ className?: string }>; variant: 'success' | 'danger' | 'warning' | 'info' | 'outline'; label: string; color: string }
> = {
  submitted: { icon: Clock, variant: 'outline', label: 'Submitted', color: 'text-theme-muted' },
  working: { icon: Loader2, variant: 'info', label: 'Working', color: 'text-theme-info' },
  completed: { icon: CheckCircle, variant: 'success', label: 'Completed', color: 'text-theme-success' },
  failed: { icon: XCircle, variant: 'danger', label: 'Failed', color: 'text-theme-danger' },
  canceled: { icon: AlertCircle, variant: 'warning', label: 'Cancelled', color: 'text-theme-warning' },
  'input-required': { icon: AlertCircle, variant: 'warning', label: 'Input Required', color: 'text-theme-warning' },
};

export const TaskDetail: React.FC<TaskDetailProps> = ({ taskId, onClose, className }) => {
  const [task, setTask] = useState<A2aTaskJson | null>(null);
  const [artifacts, setArtifacts] = useState<A2aArtifact[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [actionLoading, setActionLoading] = useState<string | null>(null);
  const [inputValue, setInputValue] = useState('');
  const [showInput, setShowInput] = useState(true);
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

      setTask(taskResponse.task as unknown as A2aTaskJson);
      setArtifacts(artifactsResponse.artifacts || []);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load task');
    } finally {
      setLoading(false);
    }
  };

  // Helper to get status state from A2A format
  const getStatusState = (): string => {
    if (!task) return 'submitted';
    return task.status?.state || 'submitted';
  };

  // Helper to extract timestamps from metadata
  const getTimestamp = (key: string): string | undefined => {
    return task?.metadata?.[key] as string | undefined;
  };

  // Helper to extract text content from message
  const getMessageText = (): string | null => {
    if (!task?.message?.parts) return null;
    const textPart = task.message.parts.find(p => p.type === 'text');
    return textPart && 'text' in textPart ? textPart.text : null;
  };

  // Helper to extract data from message
  const getMessageData = (): Record<string, unknown> | null => {
    if (!task?.message?.parts) return null;
    const dataPart = task.message.parts.find(p => p.type === 'data');
    return dataPart && 'data' in dataPart ? dataPart.data as Record<string, unknown> : null;
  };

  const handleCancel = async () => {
    try {
      setActionLoading('cancel');
      await a2aTasksApiService.cancelTask(taskId, 'Cancelled by user');
      addNotification({ type: 'success', title: 'Cancelled', message: 'Task has been cancelled' });
      await loadTask(); // Reload to get updated task state
    } catch (err) {
      console.error('[TaskDetail] Failed to cancel task:', err);
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
    } catch (err) {
      console.error('[TaskDetail] Failed to provide input:', err);
      addNotification({ type: 'error', title: 'Error', message: 'Failed to provide input' });
    } finally {
      setActionLoading(null);
    }
  };

  const formatDate = (dateStr?: string) => {
    if (!dateStr) return 'N/A';
    return new Date(dateStr).toLocaleString();
  };

  const formatDuration = (startedAt?: string, completedAt?: string, submittedAt?: string) => {
    // Use startedAt if available, otherwise fall back to submittedAt
    const startTime = startedAt || submittedAt;
    if (!startTime) return 'N/A';

    const start = new Date(startTime).getTime();
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

  const statusState = getStatusState();
  const config = statusConfig[statusState] || statusConfig.submitted;
  const StatusIcon = config.icon;
  const canCancel = ['submitted', 'working', 'input-required'].includes(statusState);
  const needsInput = statusState === 'input-required';

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
                  statusState === 'completed' && 'bg-theme-success/10',
                  statusState === 'failed' && 'bg-theme-danger/10',
                  statusState === 'working' && 'bg-theme-info/10',
                  ['submitted', 'canceled', 'input-required'].includes(statusState) &&
                    'bg-theme-muted/10'
                )}
              >
                <StatusIcon
                  className={cn(
                    'h-6 w-6',
                    config.color,
                    statusState === 'working' && 'animate-spin'
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
      {statusState === 'failed' && task.error && (
        <Card className="border-theme-danger">
          <CardHeader
            title="Error"
            icon={<XCircle className="h-5 w-5 text-theme-danger" />}
          />
          <CardContent>
            <p className="text-sm text-theme-danger whitespace-pre-wrap">
              {task.error.message || 'Unknown error'}
            </p>
            {task.error.code && (
              <p className="text-xs text-theme-muted mt-1">Code: {task.error.code}</p>
            )}
          </CardContent>
        </Card>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Main content */}
        <div className="lg:col-span-2 space-y-6">
          {/* Message Content */}
          <Card>
            <CardHeader
              title="Message"
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
              <CardContent className="space-y-4">
                {getMessageText() && (
                  <div>
                    <p className="text-xs text-theme-muted mb-2">Text:</p>
                    <p className="text-sm text-theme-primary whitespace-pre-wrap">
                      {getMessageText()}
                    </p>
                  </div>
                )}
                {getMessageData() && (
                  <div>
                    <p className="text-xs text-theme-muted mb-2">Data:</p>
                    <pre className="bg-theme-surface-dark p-4 rounded-lg text-xs overflow-x-auto max-h-64">
                      <code className="text-theme-primary">
                        {JSON.stringify(getMessageData(), null, 2)}
                      </code>
                    </pre>
                  </div>
                )}
                {!getMessageText() && !getMessageData() && (
                  <p className="text-sm text-theme-muted">No message content</p>
                )}
              </CardContent>
            )}
          </Card>

          {/* History */}
          {task.history && task.history.length > 0 && (
            <Card>
              <CardHeader
                title={`History (${task.history.length})`}
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
                      {JSON.stringify(task.history, null, 2)}
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
                <span className="text-theme-secondary">Submitted</span>
                <span className="text-theme-primary">
                  {formatDate(getTimestamp('submitted_at'))}
                </span>
              </div>
              {getTimestamp('started_at') && (
                <div className="flex justify-between">
                  <span className="text-theme-secondary">Started</span>
                  <span className="text-theme-primary">
                    {formatDate(getTimestamp('started_at'))}
                  </span>
                </div>
              )}
              {getTimestamp('completed_at') && (
                <div className="flex justify-between">
                  <span className="text-theme-secondary">Completed</span>
                  <span className="text-theme-primary">
                    {formatDate(getTimestamp('completed_at'))}
                  </span>
                </div>
              )}
              <div className="flex justify-between pt-2 border-t border-theme">
                <span className="text-theme-secondary">Duration</span>
                <span className="text-theme-primary font-medium">
                  {formatDuration(getTimestamp('started_at'), getTimestamp('completed_at'), getTimestamp('submitted_at'))}
                </span>
              </div>
            </CardContent>
          </Card>

          {/* Metadata */}
          <Card>
            <CardHeader title="Details" />
            <CardContent className="space-y-3 text-sm">
              {task.sessionId && (
                <div className="flex justify-between">
                  <span className="text-theme-secondary">Session</span>
                  <span className="text-theme-primary font-mono text-xs">
                    {task.sessionId.length > 16 ? `${task.sessionId.substring(0, 16)}...` : task.sessionId}
                  </span>
                </div>
              )}
              {Boolean(task.metadata?.role) && (
                <div className="flex justify-between">
                  <span className="text-theme-secondary">Role</span>
                  <span className="text-theme-primary">
                    {String(task.metadata?.role)}
                  </span>
                </div>
              )}
              {Boolean(task.metadata?.team_id) && (
                <div className="flex justify-between">
                  <span className="text-theme-secondary">Team</span>
                  <span className="text-theme-primary font-mono text-xs">
                    {String(task.metadata?.team_id).substring(0, 8)}...
                  </span>
                </div>
              )}
              {Boolean(task.metadata?.workflow_run_id) && (
                <div className="flex justify-between">
                  <span className="text-theme-secondary">Workflow Run</span>
                  <span className="text-theme-primary font-mono text-xs">
                    {String(task.metadata?.workflow_run_id).substring(0, 16)}...
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
