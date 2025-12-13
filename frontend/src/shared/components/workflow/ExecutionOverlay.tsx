import React from 'react';
import { CheckCircle, XCircle, Loader2, Clock, AlertCircle } from 'lucide-react';
import { NodeExecutionStatus } from '@/shared/types/workflow';

export type { NodeExecutionStatus };

export interface NodeExecutionState {
  nodeId: string;
  status: NodeExecutionStatus;
  startTime?: number;
  endTime?: number;
  duration?: number;
  error?: string;
  output?: unknown;
}

export interface ExecutionOverlayProps {
  executionState: Record<string, NodeExecutionState>;
  className?: string;
}

/**
 * Status badge component for individual nodes
 */
export const NodeStatusBadge: React.FC<{
  status: NodeExecutionStatus;
  duration?: number;
  error?: string;
}> = ({ status, duration, error }) => {
  const getStatusConfig = () => {
    switch (status) {
      case 'running':
        return {
          icon: <Loader2 className="h-3 w-3 animate-spin" />,
          color: 'bg-theme-info',
          textColor: 'text-white',
          label: 'Running'
        };
      case 'success':
        return {
          icon: <CheckCircle className="h-3 w-3" />,
          color: 'bg-theme-success',
          textColor: 'text-white',
          label: duration ? `${duration}ms` : 'Success'
        };
      case 'error':
        return {
          icon: <XCircle className="h-3 w-3" />,
          color: 'bg-theme-danger',
          textColor: 'text-white',
          label: 'Error'
        };
      case 'waiting':
        return {
          icon: <Clock className="h-3 w-3" />,
          color: 'bg-theme-warning',
          textColor: 'text-white',
          label: 'Waiting'
        };
      case 'skipped':
        return {
          icon: <AlertCircle className="h-3 w-3" />,
          color: 'bg-theme-muted',
          textColor: 'text-white',
          label: 'Skipped'
        };
      case 'pending':
      default:
        return {
          icon: <Clock className="h-3 w-3" />,
          color: 'bg-theme-surface',
          textColor: 'text-theme-secondary',
          label: 'Pending'
        };
    }
  };

  const config = getStatusConfig();

  return (
    <div
      className={`
        absolute -top-2 -right-2 z-10
        flex items-center gap-1
        px-2 py-1 rounded-full
        ${config.color} ${config.textColor}
        text-xs font-medium
        shadow-lg
        animate-in fade-in slide-in-from-top-1
      `}
      title={error || config.label}
    >
      {config.icon}
      <span>{config.label}</span>
    </div>
  );
};

/**
 * Execution path overlay showing data flow
 */
export const ExecutionPathOverlay: React.FC<{
  activeEdges: string[];
  completedEdges: string[];
}> = () => {
  return (
    <div className="pointer-events-none absolute inset-0">
      {/* Active edges get animated pulse */}
      <style>{`
        .execution-edge-active {
          stroke: #3b82f6 !important;
          stroke-width: 3 !important;
          animation: pulse-flow 1.5s ease-in-out infinite;
        }
        .execution-edge-completed {
          stroke: #10b981 !important;
          stroke-width: 2 !important;
        }
        @keyframes pulse-flow {
          0%, 100% { opacity: 0.6; }
          50% { opacity: 1; }
        }
      `}</style>
    </div>
  );
};

/**
 * Execution statistics panel
 */
export const ExecutionStats: React.FC<{
  totalNodes: number;
  completedNodes: number;
  failedNodes: number;
  totalDuration?: number;
  className?: string;
}> = ({ totalNodes, completedNodes, failedNodes, totalDuration, className = '' }) => {
  const progress = totalNodes > 0 ? (completedNodes / totalNodes) * 100 : 0;

  return (
    <div className={`bg-theme-surface border border-theme rounded-lg p-4 shadow-lg ${className}`}>
      <h3 className="text-sm font-medium text-theme-primary mb-3">Execution Progress</h3>

      {/* Progress Bar */}
      <div className="relative h-2 bg-theme-background rounded-full overflow-hidden mb-3">
        <div
          className="absolute top-0 left-0 h-full bg-theme-interactive-primary transition-all duration-300"
          style={{ width: `${progress}%` }}
        />
      </div>

      {/* Stats Grid */}
      <div className="grid grid-cols-2 gap-3 text-sm">
        <div>
          <div className="text-theme-secondary">Completed</div>
          <div className="text-theme-primary font-medium">{completedNodes}/{totalNodes}</div>
        </div>
        <div>
          <div className="text-theme-secondary">Failed</div>
          <div className="text-theme-danger font-medium">{failedNodes}</div>
        </div>
        {totalDuration !== undefined && (
          <div className="col-span-2">
            <div className="text-theme-secondary">Duration</div>
            <div className="text-theme-primary font-medium">{totalDuration}ms</div>
          </div>
        )}
      </div>
    </div>
  );
};
