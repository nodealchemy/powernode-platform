// Team Execution Monitor - Real-time execution status display
import React, { useState } from 'react';
import { Clock, CheckCircle, XCircle, Loader, User } from 'lucide-react';
import { useTeamExecutionWebSocket, TeamExecutionUpdate } from '../hooks/useTeamExecutionWebSocket';

interface TeamExecutionMonitorProps {
  teamId: string;
  onExecutionComplete?: () => void;
}

interface ExecutionState {
  status: 'idle' | 'running' | 'completed' | 'failed';
  jobId?: string;
  progress: number;
  currentMember?: string;
  startTime?: Date;
  endTime?: Date;
   
  result?: any;
  error?: string;
  updates: TeamExecutionUpdate[];
}

export const TeamExecutionMonitor: React.FC<TeamExecutionMonitorProps> = ({
  teamId,
  onExecutionComplete
}) => {
  const [executionState, setExecutionState] = useState<ExecutionState>({
    status: 'idle',
    progress: 0,
    updates: []
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
            newState.startTime = new Date(update.timestamp);
            newState.progress = 0;
            break;

          case 'execution_progress':
            newState.progress = update.progress || 0;
            newState.currentMember = update.current_member;
            break;

          case 'execution_completed':
            newState.status = 'completed';
            newState.progress = 100;
            newState.endTime = new Date(update.timestamp);
            newState.result = update.result;
            if (onExecutionComplete) {
              onExecutionComplete();
            }
            break;

          case 'execution_failed':
            newState.status = 'failed';
            newState.endTime = new Date(update.timestamp);
            newState.error = update.error;
            break;
        }

        newState.updates = [...prev.updates, update];
        return newState;
      });
    }
  });

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
            {executionState.jobId && (
              <p className="text-xs text-theme-secondary">Job ID: {executionState.jobId}</p>
            )}
          </div>
        </div>

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
      </div>

      {/* Progress Bar */}
      {executionState.status === 'running' && (
        <div className="mb-4">
          <div className="flex items-center justify-between text-sm text-theme-secondary mb-2">
            <span>Progress</span>
            <span>{executionState.progress}%</span>
          </div>
          <div className="w-full bg-theme-accent rounded-full h-2">
            <div
              className="bg-theme-info h-2 rounded-full transition-all duration-300"
              style={{ width: `${executionState.progress}%` }}
            />
          </div>
        </div>
      )}

      {/* Current Member */}
      {executionState.currentMember && executionState.status === 'running' && (
        <div className="flex items-center gap-2 text-sm text-theme-secondary mb-4 p-2 bg-theme-accent rounded-md">
          <User size={16} />
          <span>Current member: <span className="font-medium text-theme-primary">{executionState.currentMember}</span></span>
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
              </div>
            ))}
          </div>
        </details>
      )}
    </div>
  );
};

