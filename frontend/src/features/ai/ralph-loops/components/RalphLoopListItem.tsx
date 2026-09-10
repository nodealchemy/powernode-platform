import React from 'react';
import { formatRelativeTimeCompact } from '@/shared/utils/formatters';
import type { RalphLoopSummary, RalphLoopStatus } from '@/shared/services/ai/types/ralph-types';

const STATUS_STYLES: Record<RalphLoopStatus, { dot: string; pulse?: boolean }> = {
  pending: { dot: 'bg-theme-surface' },
  running: { dot: 'bg-theme-info-bg', pulse: true },
  paused: { dot: 'bg-theme-warning-bg' },
  completed: { dot: 'bg-theme-success-bg' },
  failed: { dot: 'bg-theme-error-bg' },
  cancelled: { dot: 'bg-theme-background-secondary' },
};

interface RalphLoopListItemProps {
  loop: RalphLoopSummary;
  isSelected: boolean;
  onClick: () => void;
}

export const RalphLoopListItem: React.FC<RalphLoopListItemProps> = ({ loop, isSelected, onClick }) => {
  const statusStyle = STATUS_STYLES[loop.status] || STATUS_STYLES.pending;
  const isRunning = loop.status === 'running';
  const timestamp = loop.started_at || loop.completed_at;
  const progressPct = loop.task_count > 0
    ? Math.round((loop.completed_task_count / loop.task_count) * 100)
    : 0;

  return (
    <button
      onClick={onClick}
      data-list-item
      className={`w-full text-left px-3 py-2.5 border-l-2 transition-colors hover:bg-theme-surface-hover ${
        isSelected
          ? 'border-l-theme-accent bg-theme-surface-hover'
          : 'border-l-transparent'
      }`}
    >
      <div className="flex items-center justify-between gap-2 min-w-0">
        <div className="flex items-center gap-2 min-w-0 flex-1">
          {/* Status dot */}
          <span className="relative flex-shrink-0">
            <span className={`block w-2 h-2 rounded-full ${statusStyle.dot}`} />
            {statusStyle.pulse && (
              <span className={`absolute inset-0 w-2 h-2 rounded-full ${statusStyle.dot} animate-ping opacity-40`} />
            )}
          </span>
          {/* Name */}
          <span className="text-sm font-medium text-theme-primary truncate">{loop.name}</span>
        </div>
        {timestamp && (
          <span className="text-[10px] text-theme-tertiary whitespace-nowrap flex-shrink-0">
            {formatRelativeTimeCompact(timestamp)}
          </span>
        )}
      </div>

      {/* Second row: agent + mini progress bar when running */}
      {isRunning && (
        <div className="flex items-center gap-2 mt-1 pl-4">
          {loop.default_agent_name && (
            <span className="text-[10px] text-theme-secondary whitespace-nowrap truncate max-w-[100px]">
              {loop.default_agent_name}
            </span>
          )}
          <div className="flex-1 h-1 bg-theme-surface rounded-full overflow-hidden max-w-[80px]">
            <div
              className="h-full bg-theme-info-bg rounded-full transition-all"
              style={{ width: `${progressPct}%` }}
            />
          </div>
          <span className="text-[10px] text-theme-tertiary">
            {loop.completed_task_count}/{loop.task_count}
          </span>
        </div>
      )}
    </button>
  );
};
