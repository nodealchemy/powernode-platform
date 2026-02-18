import React from 'react';
import type { ParallelSession, ParallelSessionStatus, MergeStrategy } from '../types';

const STATUS_STYLES: Record<ParallelSessionStatus, { dot: string; pulse?: boolean }> = {
  active: { dot: 'bg-theme-info', pulse: true },
  provisioning: { dot: 'bg-theme-warning', pulse: true },
  merging: { dot: 'bg-theme-warning' },
  completed: { dot: 'bg-theme-success' },
  failed: { dot: 'bg-theme-error' },
  pending: { dot: 'bg-theme-secondary' },
  cancelled: { dot: 'bg-theme-tertiary' },
};

const STRATEGY_LABELS: Record<MergeStrategy, string> = {
  sequential: 'Sequential',
  integration_branch: 'Integration',
  manual: 'Manual',
};

function timeAgo(dateStr: string): string {
  const diff = Date.now() - new Date(dateStr).getTime();
  const minutes = Math.floor(diff / 60000);
  if (minutes < 1) return 'just now';
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  return `${days}d ago`;
}

interface ParallelSessionListItemProps {
  session: ParallelSession;
  isSelected: boolean;
  onClick: () => void;
}

export const ParallelSessionListItem: React.FC<ParallelSessionListItemProps> = ({
  session,
  isSelected,
  onClick,
}) => {
  const statusStyle = STATUS_STYLES[session.status] || STATUS_STYLES.pending;
  const timestamp = session.started_at || session.created_at;
  const worktreeProgress = `${session.completed_worktrees}/${session.total_worktrees}`;

  return (
    <button
      onClick={onClick}
      className={`w-full text-left px-3 py-2.5 border-l-2 transition-colors hover:bg-theme-surface-hover ${
        isSelected
          ? 'border-l-theme-accent bg-theme-surface-hover'
          : 'border-l-transparent'
      }`}
    >
      <div className="flex items-center justify-between gap-2 min-w-0">
        <div className="flex items-center gap-2 min-w-0 flex-1">
          <span className="relative flex-shrink-0">
            <span className={`block w-2 h-2 rounded-full ${statusStyle.dot}`} />
            {statusStyle.pulse && (
              <span className={`absolute inset-0 w-2 h-2 rounded-full ${statusStyle.dot} animate-ping opacity-40`} />
            )}
          </span>
          <span className="text-sm font-medium text-theme-primary truncate">
            {session.base_branch}
          </span>
        </div>
        <span className="text-[10px] text-theme-tertiary whitespace-nowrap flex-shrink-0">
          {timeAgo(timestamp)}
        </span>
      </div>

      <div className="flex items-center gap-2 mt-1 pl-4">
        <span className="text-[10px] text-theme-secondary whitespace-nowrap">
          {STRATEGY_LABELS[session.merge_strategy]}
        </span>
        <span className="text-[10px] text-theme-tertiary whitespace-nowrap">
          {worktreeProgress}
        </span>
        <div className="flex-1 h-1 bg-theme-surface rounded-full overflow-hidden max-w-[80px]">
          <div
            className="h-full bg-theme-accent rounded-full transition-all"
            style={{ width: `${session.progress_percentage}%` }}
          />
        </div>
      </div>
    </button>
  );
};
