import React from 'react';
import { Play, Pause, Square } from 'lucide-react';
import { Team, TeamExecution } from '@/shared/services/ai/TeamsApiService';

interface ExecutionsTabProps {
  selectedTeam: Team | null;
  executions: TeamExecution[];
  onStartExecution: () => void;
  onExecutionAction: (executionId: string, action: 'pause' | 'resume' | 'cancel') => void;
  onLoadExecutionTasks: (execution: TeamExecution) => void;
  getStatusColor: (status: string) => string;
}

export const ExecutionsTab: React.FC<ExecutionsTabProps> = ({
  selectedTeam,
  executions,
  onStartExecution,
  onExecutionAction,
  onLoadExecutionTasks,
  getStatusColor,
}) => {
  if (!selectedTeam) {
    return (
      <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
        <p className="text-theme-secondary">Select a team to view executions</p>
      </div>
    );
  }

  if (executions.length === 0) {
    return (
      <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
        <Play size={48} className="mx-auto text-theme-secondary mb-4" />
        <h3 className="text-lg font-semibold text-theme-primary mb-2">No executions</h3>
        <p className="text-theme-secondary mb-6">Start a team execution to see results here</p>
        <button onClick={onStartExecution} className="btn-theme btn-theme-primary">
          Start Execution
        </button>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {executions.map(execution => (
        <div
          key={execution.id}
          className="bg-theme-surface border border-theme rounded-lg p-4 cursor-pointer hover:border-theme-accent/50 transition-colors"
          onClick={() => onLoadExecutionTasks(execution)}
        >
          <div className="flex items-center justify-between mb-2">
            <div className="flex items-center gap-3">
              <span className="font-mono text-sm text-theme-secondary">{execution.execution_id.slice(0, 8)}</span>
              <span className={`px-2 py-1 text-xs rounded ${getStatusColor(execution.status)}`}>{execution.status}</span>
            </div>
            <div className="flex gap-2" onClick={(e) => e.stopPropagation()}>
              {execution.status === 'running' && (
                <>
                  <button onClick={() => onExecutionAction(execution.id, 'pause')} className="btn-theme btn-theme-warning btn-theme-sm">
                    <Pause size={14} />
                  </button>
                  <button onClick={() => onExecutionAction(execution.id, 'cancel')} className="btn-theme btn-theme-danger btn-theme-sm">
                    <Square size={14} />
                  </button>
                </>
              )}
              {execution.status === 'paused' && (
                <button onClick={() => onExecutionAction(execution.id, 'resume')} className="btn-theme btn-theme-success btn-theme-sm">
                  <Play size={14} />
                </button>
              )}
            </div>
          </div>
          <p className="text-sm text-theme-primary mb-2">{execution.objective || 'No objective'}</p>
          <div className="w-full bg-theme-bg rounded-full h-2 mb-2">
            <div
              className="bg-theme-accent h-2 rounded-full transition-all"
              style={{ width: `${execution.progress_percentage}%` }}
            ></div>
          </div>
          <div className="flex gap-4 text-xs text-theme-secondary">
            <span>{execution.tasks_completed}/{execution.tasks_total} tasks</span>
            {execution.tasks_failed > 0 && <span className="text-theme-danger">{execution.tasks_failed} failed</span>}
            <span>{execution.messages_exchanged} messages</span>
            <span>{execution.total_tokens_used.toLocaleString()} tokens</span>
            {Number(execution.total_cost_usd) > 0 && <span>${Number(execution.total_cost_usd).toFixed(4)}</span>}
            {execution.duration_ms && <span>{(execution.duration_ms / 1000).toFixed(1)}s</span>}
          </div>
        </div>
      ))}
    </div>
  );
};
