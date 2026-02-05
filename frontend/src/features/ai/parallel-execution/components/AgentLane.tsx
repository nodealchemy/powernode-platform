import React from 'react';
import { GitBranch, GitCommit, Clock, AlertCircle, Container, Timer, DollarSign, TestTube } from 'lucide-react';
import { WorktreeStatusBadge } from './WorktreeStatusBadge';
import type { ParallelWorktree } from '../types';

interface AgentLaneProps {
  worktree: ParallelWorktree;
}

export const AgentLane: React.FC<AgentLaneProps> = ({ worktree }) => {
  const isActive = ['creating', 'ready', 'in_use'].includes(worktree.status);
  const progress = worktree.status === 'completed' || worktree.status === 'merged' ? 100
    : worktree.status === 'in_use' ? 60
    : worktree.status === 'ready' ? 30
    : worktree.status === 'creating' ? 10
    : 0;

  return (
    <div className="bg-theme-bg-primary border border-theme rounded-lg p-4 flex flex-col h-full">
      {/* Header */}
      <div className="flex items-center justify-between mb-3">
        <div className="flex items-center gap-2 min-w-0">
          <div className={`w-2 h-2 rounded-full flex-shrink-0 ${isActive ? 'bg-theme-status-info animate-pulse' : worktree.status === 'failed' ? 'bg-theme-status-error' : 'bg-theme-status-success'}`} />
          <span className="text-sm font-medium text-theme-text-primary truncate">
            {worktree.agent_name || worktree.branch_name.split('/').pop()}
          </span>
        </div>
        <WorktreeStatusBadge status={worktree.status} type="worktree" size="sm" />
      </div>

      {/* Branch info */}
      <div className="flex items-center gap-1 text-xs text-theme-text-secondary mb-2">
        <GitBranch className="w-3 h-3 flex-shrink-0" />
        <span className="truncate">{worktree.branch_name}</span>
      </div>

      {/* Progress bar */}
      <div className="h-1 bg-theme-bg-secondary rounded-full overflow-hidden mb-3">
        <div
          className="h-full bg-theme-status-info rounded-full transition-all duration-500"
          style={{ width: `${progress}%` }}
        />
      </div>

      {/* Stats */}
      <div className="flex-1 space-y-1 text-xs text-theme-text-secondary">
        {worktree.head_commit_sha && (
          <div className="flex items-center gap-1">
            <GitCommit className="w-3 h-3" />
            <span className="font-mono">{worktree.head_commit_sha.substring(0, 8)}</span>
          </div>
        )}

        {worktree.commit_count > 0 && (
          <div>{worktree.commit_count} commit{worktree.commit_count !== 1 ? 's' : ''}</div>
        )}

        {(worktree.files_changed > 0 || worktree.lines_added > 0 || worktree.lines_removed > 0) && (
          <div className="flex items-center gap-2">
            <span>{worktree.files_changed} files</span>
            <span className="text-theme-status-success">+{worktree.lines_added}</span>
            <span className="text-theme-status-error">-{worktree.lines_removed}</span>
          </div>
        )}

        {worktree.duration_ms && (
          <div className="flex items-center gap-1">
            <Clock className="w-3 h-3" />
            {(worktree.duration_ms / 1000).toFixed(1)}s
          </div>
        )}

        {(worktree.tokens_used && worktree.tokens_used > 0) && (
          <div className="flex items-center gap-1">
            <DollarSign className="w-3 h-3" />
            <span>{worktree.tokens_used.toLocaleString()} tokens</span>
            {worktree.estimated_cost_cents ? (
              <span className="text-theme-text-tertiary">(${(worktree.estimated_cost_cents / 100).toFixed(2)})</span>
            ) : null}
          </div>
        )}

        {worktree.test_status && (
          <div className={`flex items-center gap-1 ${
            worktree.test_status === 'passed' ? 'text-theme-status-success' :
            worktree.test_status === 'failed' ? 'text-theme-status-error' :
            'text-theme-text-secondary'
          }`}>
            <TestTube className="w-3 h-3" />
            <span>Tests: {worktree.test_status}</span>
          </div>
        )}
      </div>

      {/* Timeout warning */}
      {worktree.timeout_at && new Date(worktree.timeout_at) < new Date() && worktree.status !== 'failed' && (
        <div className="mt-2 flex items-center gap-1 text-xs text-theme-status-warning">
          <Timer className="w-3 h-3" />
          <span>Timed out</span>
        </div>
      )}

      {/* Error */}
      {worktree.error_message && (
        <div className="mt-2 flex items-start gap-1 text-xs text-theme-status-error">
          <AlertCircle className="w-3 h-3 flex-shrink-0 mt-0.5" />
          <span className="line-clamp-2">{worktree.error_message}</span>
        </div>
      )}

      {/* Container indicator */}
      {worktree.container_instance_id && (
        <div className="mt-2 flex items-center gap-1 text-xs text-theme-text-secondary">
          <Container className="w-3 h-3 text-theme-status-info" />
          <span>Container: {worktree.container_instance_id.substring(0, 8)}</span>
        </div>
      )}

      {/* Health indicator */}
      {!worktree.healthy && worktree.status !== 'failed' && (
        <div className="mt-2 text-xs text-theme-status-warning">Unhealthy</div>
      )}
    </div>
  );
};
