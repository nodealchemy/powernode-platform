// Team Execution Monitor - Real-time execution status display with per-agent progress
import React, { useState, useEffect, useRef } from 'react';
import { Clock, CheckCircle, XCircle, Loader, User, BookOpen, Shield, GitFork } from 'lucide-react';
import { useTeamExecutionWebSocket, TeamExecutionUpdate } from '../hooks/useTeamExecutionWebSocket';

interface TeamExecutionMonitorProps {
  teamId: string;
  onExecutionComplete?: () => void;
  onViewTrajectory?: (trajectoryId: string) => void;
  onDismiss?: () => void;
}

interface MemberResult {
  name: string;
  role?: string;
  status: 'pending' | 'running' | 'completed' | 'failed';
  duration_ms?: number;
}

interface ExecutionState {
  status: 'idle' | 'running' | 'completed' | 'failed';
  jobId?: string;
  executionId?: string;
  progress: number;
  currentMember?: string;
  startTime?: Date;
  endTime?: Date;
  result?: Record<string, unknown>;
  error?: string;
  updates: TeamExecutionUpdate[];
  trajectoryId?: string;
  reviewsActive?: number;
  worktreeCount?: number;
  sessionId?: string;
  memberResults: MemberResult[];
  tasksTotal: number;
  tasksCompleted: number;
  tasksFailed: number;
}

export const TeamExecutionMonitor: React.FC<TeamExecutionMonitorProps> = ({
  teamId,
  onExecutionComplete,
  onViewTrajectory,
  onDismiss
}) => {
  const [executionState, setExecutionState] = useState<ExecutionState>({
    status: 'idle',
    progress: 0,
    updates: [],
    memberResults: [],
    tasksTotal: 0,
    tasksCompleted: 0,
    tasksFailed: 0
  });

  const { isConnected } = useTeamExecutionWebSocket({
    teamId,
    enabled: true,
    onUpdate: (update) => {
      setExecutionState(prev => {
        const newState = { ...prev };

        switch (update.type) {
          case 'execution_started':
            newState.status = 'running';
            newState.jobId = update.job_id;
            newState.executionId = update.execution_id;
            newState.startTime = new Date(update.timestamp);
            newState.progress = 0;
            newState.memberResults = [];
            newState.tasksTotal = update.tasks_total || 0;
            newState.tasksCompleted = 0;
            newState.tasksFailed = 0;
            break;

          case 'execution_progress':
            newState.currentMember = update.current_member;
            newState.tasksTotal = update.tasks_total || newState.tasksTotal;
            newState.tasksCompleted = update.tasks_completed || newState.tasksCompleted;
            newState.tasksFailed = update.tasks_failed || newState.tasksFailed;
            // Update progress based on task completion
            if (newState.tasksTotal > 0) {
              newState.progress = Math.round((newState.tasksCompleted / newState.tasksTotal) * 100);
            } else {
              newState.progress = update.progress || 0;
            }
            // Mark the current member as running in the grid
            if (update.current_member) {
              const existing = newState.memberResults.find(m => m.name === update.current_member);
              if (!existing) {
                newState.memberResults = [...newState.memberResults, {
                  name: update.current_member,
                  role: update.current_role,
                  status: 'running'
                }];
              } else if (existing.status === 'pending') {
                newState.memberResults = newState.memberResults.map(m =>
                  m.name === update.current_member ? { ...m, status: 'running' as const, role: update.current_role || m.role } : m
                );
              }
            }
            break;

          case 'member_completed':
            newState.tasksTotal = update.tasks_total || newState.tasksTotal;
            newState.tasksCompleted = update.tasks_completed || newState.tasksCompleted;
            newState.tasksFailed = update.tasks_failed || newState.tasksFailed;
            if (newState.tasksTotal > 0) {
              newState.progress = Math.round((newState.tasksCompleted / newState.tasksTotal) * 100);
            }
            if (update.member_name) {
              const memberExists = newState.memberResults.some(m => m.name === update.member_name);
              if (memberExists) {
                newState.memberResults = newState.memberResults.map(m =>
                  m.name === update.member_name ? {
                    ...m,
                    status: update.member_success ? 'completed' as const : 'failed' as const,
                    duration_ms: update.member_duration_ms
                  } : m
                );
              } else {
                newState.memberResults = [...newState.memberResults, {
                  name: update.member_name,
                  status: update.member_success ? 'completed' : 'failed',
                  duration_ms: update.member_duration_ms
                }];
              }
            }
            break;

          case 'execution_completed':
            newState.status = 'completed';
            newState.progress = 100;
            newState.endTime = new Date(update.timestamp);
            newState.result = update.result as Record<string, unknown>;
            newState.tasksTotal = update.tasks_total || newState.tasksTotal;
            newState.tasksCompleted = update.tasks_completed || newState.tasksCompleted;
            newState.tasksFailed = update.tasks_failed || newState.tasksFailed;
            break;

          case 'execution_failed':
            newState.status = 'failed';
            newState.endTime = new Date(update.timestamp);
            newState.error = update.error;
            newState.tasksTotal = update.tasks_total || newState.tasksTotal;
            newState.tasksCompleted = update.tasks_completed || newState.tasksCompleted;
            newState.tasksFailed = update.tasks_failed || newState.tasksFailed;
            break;
        }

        newState.updates = [...prev.updates, update];
        return newState;
      });
    }
  });

  // Trigger onExecutionComplete as a side effect, not during render
  const completeFiredRef = useRef(false);
  useEffect(() => {
    if (executionState.status === 'completed' && !completeFiredRef.current) {
      completeFiredRef.current = true;
      onExecutionComplete?.();
    }
  }, [executionState.status, onExecutionComplete]);

  const getStatusIcon = () => {
    switch (executionState.status) {
      case 'running':
        return <Loader className="animate-spin text-theme-info" size={20} />;
      case 'completed':
        return <CheckCircle className="text-theme-success" size={20} />;
      case 'failed':
        return <XCircle className="text-theme-danger" size={20} />;
      default:
        return <Clock className="text-theme-muted" size={20} />;
    }
  };

  const getStatusText = () => {
    switch (executionState.status) {
      case 'running':
        return 'Executing...';
      case 'completed':
        return 'Completed';
      case 'failed':
        return 'Failed';
      default:
        return 'Idle';
    }
  };

  const getElapsedTime = () => {
    if (!executionState.startTime) return null;

    const endTime = executionState.endTime || new Date();
    const elapsed = Math.floor((endTime.getTime() - executionState.startTime.getTime()) / 1000);

    const minutes = Math.floor(elapsed / 60);
    const seconds = elapsed % 60;

    return `${minutes}:${seconds.toString().padStart(2, '0')}`;
  };

  const formatDuration = (ms: number) => {
    if (ms < 1000) return `${ms}ms`;
    const seconds = (ms / 1000).toFixed(1);
    return `${seconds}s`;
  };

  const getMemberStatusIcon = (status: MemberResult['status']) => {
    switch (status) {
      case 'running':
        return <Loader className="animate-spin text-theme-info" size={14} />;
      case 'completed':
        return <CheckCircle className="text-theme-success" size={14} />;
      case 'failed':
        return <XCircle className="text-theme-danger" size={14} />;
      default:
        return <Clock className="text-theme-muted" size={14} />;
    }
  };

  // Hide monitor when idle
  if (executionState.status === 'idle') {
    return null;
  }

  return (
    <div className="bg-theme-surface border border-theme rounded-lg p-4 mb-6">
      {/* Header */}
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-3">
          {getStatusIcon()}
          <div>
            <h3 className="font-semibold text-theme-primary">{getStatusText()}</h3>
            {executionState.executionId && (
              <p className="text-xs text-theme-secondary">Execution: {executionState.executionId}</p>
            )}
          </div>
        </div>

        <div className="flex items-center gap-4">
          {getElapsedTime() && (
            <div className="flex items-center gap-2 text-sm text-theme-secondary">
              <Clock size={16} />
              {getElapsedTime()}
            </div>
          )}

          <div className="flex items-center gap-2">
            <div className={`w-2 h-2 rounded-full ${isConnected ? 'bg-theme-success-solid' : 'bg-theme-danger-solid'}`} />
            <span className="text-xs text-theme-secondary">
              {isConnected ? 'Live' : 'Disconnected'}
            </span>
          </div>

          {onDismiss && (executionState.status === 'completed' || executionState.status === 'failed') && (
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

      {/* Task Counter + Progress Bar */}
      {executionState.status === 'running' && (
        <div className="mb-4">
          <div className="flex items-center justify-between text-sm text-theme-secondary mb-2">
            <span>{executionState.tasksCompleted}/{executionState.tasksTotal} agents completed</span>
            <span>{executionState.progress}%</span>
          </div>
          <div className="w-full bg-theme-accent rounded-full h-2">
            <div
              className="bg-theme-info h-2 rounded-full transition-all duration-300"
              style={{ width: `${executionState.progress}%` }}
            />
          </div>
          {executionState.tasksFailed > 0 && (
            <p className="text-xs text-theme-danger mt-1">{executionState.tasksFailed} failed</p>
          )}
        </div>
      )}

      {/* Per-Member Progress Grid */}
      {executionState.memberResults.length > 0 && (
        <div className="mb-4">
          <h4 className="text-xs font-medium text-theme-secondary uppercase tracking-wide mb-2">Agent Progress</h4>
          <div className="space-y-1">
            {executionState.memberResults.map((member) => (
              <div
                key={member.name}
                className="flex items-center justify-between p-2 bg-theme-accent/50 rounded-md"
              >
                <div className="flex items-center gap-2">
                  {getMemberStatusIcon(member.status)}
                  <span className="text-sm font-medium text-theme-primary">{member.name}</span>
                  {member.role && (
                    <span className="text-xs text-theme-secondary">({member.role})</span>
                  )}
                </div>
                <div className="flex items-center gap-2">
                  {member.duration_ms !== undefined && (
                    <span className="text-xs text-theme-secondary">{formatDuration(member.duration_ms)}</span>
                  )}
                  <span className={`text-xs font-medium ${
                    member.status === 'completed' ? 'text-theme-success' :
                    member.status === 'failed' ? 'text-theme-danger' :
                    member.status === 'running' ? 'text-theme-info' :
                    'text-theme-secondary'
                  }`}>
                    {member.status}
                  </span>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Current Member (when no grid data yet) */}
      {executionState.currentMember && executionState.status === 'running' && executionState.memberResults.length === 0 && (
        <div className="flex items-center gap-2 text-sm text-theme-secondary mb-4 p-2 bg-theme-accent rounded-md">
          <User size={16} />
          <span>Current member: <span className="font-medium text-theme-primary">{executionState.currentMember}</span></span>
        </div>
      )}

      {/* Completed Summary */}
      {(executionState.status === 'completed' || executionState.status === 'failed') && executionState.tasksTotal > 0 && (
        <div className={`p-3 rounded-md mb-4 ${
          executionState.status === 'completed' ? 'bg-theme-success/10 border border-theme-success/30' : 'bg-theme-error/10 border border-theme-error/30'
        }`}>
          <div className="flex items-center gap-4 text-sm">
            <span className={executionState.status === 'completed' ? 'text-theme-success' : 'text-theme-danger'}>
              {executionState.tasksCompleted}/{executionState.tasksTotal} agents completed
            </span>
            {executionState.tasksFailed > 0 && (
              <span className="text-theme-danger">{executionState.tasksFailed} failed</span>
            )}
            {getElapsedTime() && (
              <span className="text-theme-secondary">Duration: {getElapsedTime()}</span>
            )}
          </div>
        </div>
      )}

      {/* Result/Error */}
      {executionState.status === 'completed' && executionState.result && (
        <div className="p-3 bg-theme-success/10 border border-theme-success/30 rounded-md">
          <p className="text-sm text-theme-success font-medium mb-2">Execution Result</p>
          <pre className="text-xs text-theme-success overflow-x-auto">
            {JSON.stringify(executionState.result, null, 2)}
          </pre>
        </div>
      )}

      {executionState.status === 'failed' && executionState.error && (
        <div className="p-3 bg-theme-error/10 border border-theme-error/30 rounded-md">
          <p className="text-sm text-theme-danger font-medium mb-2">Error</p>
          <p className="text-sm text-theme-danger">{executionState.error}</p>
        </div>
      )}

      {/* Trajectory Status */}
      {executionState.status === 'running' && (
        <div className="flex items-center gap-2 text-xs text-theme-secondary mt-4 p-2 bg-theme-accent/50 rounded-md">
          <BookOpen size={14} className="text-theme-info" />
          <span>Trajectory building in progress...</span>
        </div>
      )}

      {executionState.status === 'completed' && (
        <div className="flex items-center justify-between mt-4 p-3 bg-theme-info/5 border border-theme-info/20 rounded-md">
          <div className="flex items-center gap-2 text-sm text-theme-info">
            <BookOpen size={16} />
            <span>Trajectory captured</span>
          </div>
          {onViewTrajectory && executionState.trajectoryId && (
            <button
              type="button"
              onClick={() => onViewTrajectory(executionState.trajectoryId!)}
              className="text-xs text-theme-info hover:text-theme-primary underline"
            >
              View Trajectory
            </button>
          )}
        </div>
      )}

      {/* Worktree Indicator */}
      {executionState.worktreeCount !== undefined && executionState.worktreeCount > 0 && (
        <div className="flex items-center gap-2 text-xs text-theme-info mt-2 p-2 bg-theme-info/5 border border-theme-info/20 rounded-md">
          <GitFork size={14} />
          <span>{executionState.worktreeCount} worktree{executionState.worktreeCount > 1 ? 's' : ''} active</span>
        </div>
      )}

      {/* Review Status Indicators */}
      {executionState.reviewsActive !== undefined && executionState.reviewsActive > 0 && (
        <div className="flex items-center gap-2 text-xs text-theme-warning mt-2 p-2 bg-theme-warning/5 border border-theme-warning/20 rounded-md">
          <Shield size={14} />
          <span>{executionState.reviewsActive} review{executionState.reviewsActive > 1 ? 's' : ''} in progress</span>
        </div>
      )}

      {/* Activity Log */}
      {executionState.updates.length > 0 && (
        <details className="mt-4">
          <summary className="text-sm font-medium text-theme-primary cursor-pointer hover:text-theme-info">
            Activity Log ({executionState.updates.length} updates)
          </summary>
          <div className="mt-2 space-y-1 max-h-48 overflow-y-auto">
            {executionState.updates.map((update, index) => (
              <div
                key={index}
                className="text-xs text-theme-secondary p-2 bg-theme-accent rounded"
              >
                <span className="font-medium">{new Date(update.timestamp).toLocaleTimeString()}</span>
                {' - '}
                <span>{update.type.replace(/_/g, ' ')}</span>
                {update.current_member && ` - ${update.current_member}`}
                {update.member_name && ` - ${update.member_name}`}
                {update.member_success !== undefined && ` (${update.member_success ? 'success' : 'failed'})`}
              </div>
            ))}
          </div>
        </details>
      )}
    </div>
  );
};
