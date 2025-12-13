import React, { useMemo } from 'react';
import {
  CheckCircle2,
  XCircle,
  Loader2,
  Clock,
  TrendingUp,
  AlertTriangle,
  Pause,
  Play
} from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { Progress } from '@/shared/components/ui/Progress';

export interface BatchWorkflowStatus {
  workflow_id: string;
  workflow_name: string;
  status: 'pending' | 'running' | 'completed' | 'failed' | 'cancelled';
  run_id?: string;
  started_at?: string;
  completed_at?: string;
  duration_ms?: number;
  error_message?: string;
  progress?: number; // 0-100 for running workflows
}

export interface BatchExecutionStatus {
  batch_id: string;
  status: 'initializing' | 'running' | 'paused' | 'completed' | 'failed' | 'cancelled';
  total_workflows: number;
  completed_workflows: number;
  successful_workflows: number;
  failed_workflows: number;
  running_workflows: number;
  pending_workflows: number;
  started_at: string;
  completed_at?: string;
  estimated_completion_at?: string;
  workflows: BatchWorkflowStatus[];
  configuration: {
    concurrency: number;
    execution_mode: 'parallel' | 'sequential';
    stop_on_error: boolean;
  };
}

interface BatchProgressPanelProps {
  batchStatus: BatchExecutionStatus;
  onPause?: () => void;
  onResume?: () => void;
  onCancel?: () => void;
  allowControls?: boolean;
}

export const BatchProgressPanel: React.FC<BatchProgressPanelProps> = ({
  batchStatus,
  onPause,
  onResume,
  onCancel,
  allowControls = true
}) => {
  const progressPercentage = useMemo(() => {
    if (batchStatus.total_workflows === 0) return 0;
    return Math.round((batchStatus.completed_workflows / batchStatus.total_workflows) * 100);
  }, [batchStatus.completed_workflows, batchStatus.total_workflows]);

  const successRate = useMemo(() => {
    if (batchStatus.completed_workflows === 0) return 0;
    return Math.round((batchStatus.successful_workflows / batchStatus.completed_workflows) * 100);
  }, [batchStatus.successful_workflows, batchStatus.completed_workflows]);

  const estimatedTimeRemaining = useMemo(() => {
    if (!batchStatus.estimated_completion_at) return null;
    const remaining = new Date(batchStatus.estimated_completion_at).getTime() - Date.now();
    if (remaining <= 0) return null;

    const minutes = Math.floor(remaining / 60000);
    const seconds = Math.floor((remaining % 60000) / 1000);
    return `${minutes}m ${seconds}s`;
  }, [batchStatus.estimated_completion_at]);

  const elapsedTime = useMemo(() => {
    const start = new Date(batchStatus.started_at).getTime();
    const end = batchStatus.completed_at
      ? new Date(batchStatus.completed_at).getTime()
      : Date.now();
    const elapsed = end - start;

    const minutes = Math.floor(elapsed / 60000);
    const seconds = Math.floor((elapsed % 60000) / 1000);
    return `${minutes}m ${seconds}s`;
  }, [batchStatus.started_at, batchStatus.completed_at]);

  const getStatusBadge = (status: BatchExecutionStatus['status']) => {
    switch (status) {
      case 'initializing':
        return <Badge variant="outline" size="sm">Initializing</Badge>;
      case 'running':
        return <Badge variant="info" size="sm" className="animate-pulse">Running</Badge>;
      case 'paused':
        return <Badge variant="warning" size="sm">Paused</Badge>;
      case 'completed':
        return <Badge variant="success" size="sm">Completed</Badge>;
      case 'failed':
        return <Badge variant="danger" size="sm">Failed</Badge>;
      case 'cancelled':
        return <Badge variant="outline" size="sm">Cancelled</Badge>;
      default:
        return <Badge variant="outline" size="sm">{status}</Badge>;
    }
  };

  const getWorkflowStatusIcon = (status: BatchWorkflowStatus['status']) => {
    switch (status) {
      case 'completed':
        return <CheckCircle2 className="h-4 w-4 text-theme-success" />;
      case 'failed':
        return <XCircle className="h-4 w-4 text-theme-error" />;
      case 'running':
        return <Loader2 className="h-4 w-4 text-theme-info animate-spin" />;
      case 'cancelled':
        return <XCircle className="h-4 w-4 text-theme-warning" />;
      case 'pending':
      default:
        return <Clock className="h-4 w-4 text-theme-tertiary" />;
    }
  };

  const formatDuration = (durationMs?: number) => {
    if (!durationMs) return '-';
    const seconds = Math.floor(durationMs / 1000);
    const minutes = Math.floor(seconds / 60);
    const remainingSeconds = seconds % 60;
    return minutes > 0 ? `${minutes}m ${remainingSeconds}s` : `${seconds}s`;
  };

  const canPause = batchStatus.status === 'running' && allowControls && onPause;
  const canResume = batchStatus.status === 'paused' && allowControls && onResume;
  const canCancel = ['running', 'paused'].includes(batchStatus.status) && allowControls && onCancel;

  return (
    <div className="space-y-4">
      {/* Overall Progress Card */}
      <Card className="p-6">
        <div className="space-y-4">
          {/* Header */}
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <h3 className="text-lg font-semibold text-theme-primary">
                Batch Execution Progress
              </h3>
              {getStatusBadge(batchStatus.status)}
            </div>
            {allowControls && (
              <div className="flex items-center gap-2">
                {canPause && (
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={onPause}
                    className="flex items-center gap-1"
                  >
                    <Pause className="h-4 w-4" />
                    Pause
                  </Button>
                )}
                {canResume && (
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={onResume}
                    className="flex items-center gap-1"
                  >
                    <Play className="h-4 w-4" />
                    Resume
                  </Button>
                )}
                {canCancel && (
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={onCancel}
                    className="flex items-center gap-1 text-theme-error hover:bg-theme-error hover:bg-opacity-10"
                  >
                    <XCircle className="h-4 w-4" />
                    Cancel
                  </Button>
                )}
              </div>
            )}
          </div>

          {/* Progress Bar */}
          <div className="space-y-2">
            <div className="flex items-center justify-between text-sm">
              <span className="text-theme-secondary">
                {batchStatus.completed_workflows} of {batchStatus.total_workflows} workflows completed
              </span>
              <span className="font-semibold text-theme-primary">{progressPercentage}%</span>
            </div>
            <Progress value={progressPercentage} className="h-2" />
          </div>

          {/* Statistics Grid */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4 pt-4 border-t border-theme">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 bg-theme-success bg-opacity-10 rounded-lg flex items-center justify-center">
                <CheckCircle2 className="h-5 w-5 text-theme-success" />
              </div>
              <div>
                <p className="text-2xl font-semibold text-theme-primary">
                  {batchStatus.successful_workflows}
                </p>
                <p className="text-xs text-theme-tertiary">Successful</p>
              </div>
            </div>

            <div className="flex items-center gap-3">
              <div className="w-10 h-10 bg-theme-error bg-opacity-10 rounded-lg flex items-center justify-center">
                <XCircle className="h-5 w-5 text-theme-error" />
              </div>
              <div>
                <p className="text-2xl font-semibold text-theme-primary">
                  {batchStatus.failed_workflows}
                </p>
                <p className="text-xs text-theme-tertiary">Failed</p>
              </div>
            </div>

            <div className="flex items-center gap-3">
              <div className="w-10 h-10 bg-theme-info bg-opacity-10 rounded-lg flex items-center justify-center">
                <Loader2 className="h-5 w-5 text-theme-info" />
              </div>
              <div>
                <p className="text-2xl font-semibold text-theme-primary">
                  {batchStatus.running_workflows}
                </p>
                <p className="text-xs text-theme-tertiary">Running</p>
              </div>
            </div>

            <div className="flex items-center gap-3">
              <div className="w-10 h-10 bg-theme-surface rounded-lg flex items-center justify-center">
                <Clock className="h-5 w-5 text-theme-tertiary" />
              </div>
              <div>
                <p className="text-2xl font-semibold text-theme-primary">
                  {batchStatus.pending_workflows}
                </p>
                <p className="text-xs text-theme-tertiary">Pending</p>
              </div>
            </div>
          </div>

          {/* Metadata Row */}
          <div className="flex items-center justify-between pt-4 border-t border-theme text-sm text-theme-secondary">
            <div className="flex items-center gap-6">
              <span>
                Mode: <span className="font-medium text-theme-primary">
                  {batchStatus.configuration.execution_mode === 'parallel'
                    ? `Parallel (${batchStatus.configuration.concurrency} concurrent)`
                    : 'Sequential'}
                </span>
              </span>
              <span>
                Elapsed: <span className="font-medium text-theme-primary">{elapsedTime}</span>
              </span>
              {estimatedTimeRemaining && (
                <span>
                  Remaining: <span className="font-medium text-theme-primary">{estimatedTimeRemaining}</span>
                </span>
              )}
            </div>
            {batchStatus.completed_workflows > 0 && (
              <div className="flex items-center gap-1">
                <TrendingUp className="h-4 w-4 text-theme-success" />
                <span className="font-medium text-theme-primary">{successRate}%</span>
                <span>success rate</span>
              </div>
            )}
          </div>
        </div>
      </Card>

      {/* Individual Workflow Status */}
      <Card className="p-6">
        <h4 className="text-sm font-semibold text-theme-primary mb-4">
          Workflow Status
        </h4>
        <div className="space-y-2 max-h-96 overflow-y-auto">
          {batchStatus.workflows.map((workflow) => (
            <div
              key={workflow.workflow_id}
              className="flex items-center gap-3 p-3 bg-theme-surface rounded-lg hover:bg-theme-surface-hover transition-colors"
            >
              <div className="flex-shrink-0">
                {getWorkflowStatusIcon(workflow.status)}
              </div>

              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2 mb-1">
                  <p className="font-medium text-theme-primary truncate">
                    {workflow.workflow_name}
                  </p>
                  {workflow.status === 'running' && workflow.progress !== undefined && (
                    <Badge variant="outline" size="sm">
                      {workflow.progress}%
                    </Badge>
                  )}
                </div>

                {workflow.error_message && (
                  <div className="flex items-center gap-1 text-xs text-theme-error mb-1">
                    <AlertTriangle className="h-3 w-3" />
                    <span className="truncate">{workflow.error_message}</span>
                  </div>
                )}

                <div className="flex items-center gap-4 text-xs text-theme-tertiary">
                  {workflow.run_id && (
                    <span className="truncate">Run: {workflow.run_id.slice(0, 8)}</span>
                  )}
                  {workflow.duration_ms && (
                    <span>Duration: {formatDuration(workflow.duration_ms)}</span>
                  )}
                  {workflow.started_at && !workflow.completed_at && (
                    <span>Started: {new Date(workflow.started_at).toLocaleTimeString()}</span>
                  )}
                </div>

                {/* Progress bar for running workflows */}
                {workflow.status === 'running' && workflow.progress !== undefined && (
                  <div className="mt-2">
                    <Progress value={workflow.progress} className="h-1" />
                  </div>
                )}
              </div>

              <div className="flex-shrink-0">
                <Badge
                  variant={
                    workflow.status === 'completed' ? 'success' :
                    workflow.status === 'failed' ? 'danger' :
                    workflow.status === 'running' ? 'info' :
                    'outline'
                  }
                  size="sm"
                >
                  {workflow.status}
                </Badge>
              </div>
            </div>
          ))}
        </div>
      </Card>
    </div>
  );
};
