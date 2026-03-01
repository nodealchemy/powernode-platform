import React from 'react';
import {
  Clock,
  CheckCircle,
  XCircle,
  Loader,
  Pause,
  Play,
  StopCircle,
} from 'lucide-react';
import type { DiagramExecutionState } from './executionDiagramTypes';

interface DiagramControlsProps {
  execState: DiagramExecutionState;
  isConnected: boolean;
  executionId?: string;
  onPause: () => void;
  onCancel: () => void;
  onResume: () => void;
  onDismiss?: () => void;
}

const getStatusIcon = (status: DiagramExecutionState['status']) => {
  switch (status) {
    case 'running': return <Loader className="animate-spin text-theme-info" size={18} />;
    case 'paused': return <Pause className="text-theme-warning" size={18} />;
    case 'completed': return <CheckCircle className="text-theme-success" size={18} />;
    case 'failed': return <XCircle className="text-theme-danger" size={18} />;
    case 'cancelled': return <StopCircle className="text-theme-secondary" size={18} />;
    default: return <Clock className="text-theme-muted" size={18} />;
  }
};

const getStatusText = (status: DiagramExecutionState['status']) => {
  switch (status) {
    case 'running': return 'Executing...';
    case 'paused': return 'Paused';
    case 'completed': return 'Completed';
    case 'failed': return 'Failed';
    case 'cancelled': return 'Cancelled';
    default: return 'Waiting for execution...';
  }
};

const getElapsedTime = (startTime?: Date, endTime?: Date) => {
  if (!startTime) return null;
  const end = endTime || new Date();
  const elapsed = Math.floor((end.getTime() - startTime.getTime()) / 1000);
  const minutes = Math.floor(elapsed / 60);
  const seconds = elapsed % 60;
  return `${minutes}:${seconds.toString().padStart(2, '0')}`;
};

export const DiagramControls: React.FC<DiagramControlsProps> = ({
  execState,
  isConnected,
  executionId,
  onPause,
  onCancel,
  onResume,
  onDismiss,
}) => {
  const elapsed = getElapsedTime(execState.startTime, execState.endTime);

  return (
    <>
      {/* Header */}
      <div className="flex items-center justify-between mb-3">
        <div className="flex items-center gap-2">
          {getStatusIcon(execState.status)}
          <div>
            <h3 className="font-semibold text-theme-primary text-sm">{getStatusText(execState.status)}</h3>
            {execState.executionId && (
              <p className="text-[10px] text-theme-secondary">Execution: {execState.executionId}</p>
            )}
          </div>
        </div>

        <div className="flex items-center gap-3">
          {execState.status === 'running' && executionId && (
            <div className="flex items-center gap-1">
              <button
                type="button"
                onClick={onPause}
                className="p-1 rounded text-theme-warning hover:bg-theme-warning/10 transition-colors"
                title="Pause execution"
              >
                <Pause size={14} />
              </button>
              <button
                type="button"
                onClick={onCancel}
                className="p-1 rounded text-theme-danger hover:bg-theme-error/10 transition-colors"
                title="Cancel execution"
              >
                <StopCircle size={14} />
              </button>
            </div>
          )}
          {execState.status === 'paused' && executionId && (
            <button
              type="button"
              onClick={onResume}
              className="flex items-center gap-1 px-2 py-1 text-xs rounded bg-theme-success/10 text-theme-success hover:bg-theme-success/20 transition-colors"
              title="Resume execution"
            >
              <Play size={12} /> Resume
            </button>
          )}
          {elapsed && (
            <div className="flex items-center gap-1.5 text-xs text-theme-secondary">
              <Clock size={14} />
              {elapsed}
            </div>
          )}
          <div className="flex items-center gap-1.5">
            <div className={`w-2 h-2 rounded-full ${isConnected ? 'bg-theme-success-solid' : 'bg-theme-danger-solid'}`} />
            <span className="text-[10px] text-theme-secondary">
              {isConnected ? 'Live' : 'Disconnected'}
            </span>
          </div>
          {onDismiss && ['completed', 'failed', 'cancelled'].includes(execState.status) && (
            <button
              type="button"
              onClick={onDismiss}
              className="text-xs text-theme-secondary hover:text-theme-primary"
            >
              Dismiss
            </button>
          )}
        </div>
      </div>

      {/* Progress counter */}
      {(execState.status === 'running' || execState.status === 'paused') && execState.tasksTotal > 0 && (
        <div className="flex items-center justify-between text-xs text-theme-secondary mb-3">
          <span>
            {execState.tasksCompleted}/{execState.tasksTotal} agents completed
            {execState.tasksFailed > 0 && (
              <span className="text-theme-danger ml-2">{execState.tasksFailed} failed</span>
            )}
          </span>
          <span>{execState.progress}%</span>
        </div>
      )}
    </>
  );
};
