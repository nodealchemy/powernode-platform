import React, { useMemo } from 'react';
import type { ParallelWorktree } from '../types';

interface TimelineViewProps {
  worktrees: ParallelWorktree[];
}

const STATUS_COLORS: Record<string, string> = {
  pending: 'var(--color-text-tertiary, #94a3b8)',
  creating: 'var(--color-info, #60a5fa)',
  ready: 'var(--color-info, #38bdf8)',
  in_use: 'var(--color-warning, #fbbf24)',
  completed: 'var(--color-success, #4ade80)',
  merged: 'var(--color-info, #22d3ee)',
  cleaned_up: 'var(--color-text-tertiary, #a1a1aa)',
  failed: 'var(--color-error, #f87171)',
};

export const TimelineView: React.FC<TimelineViewProps> = ({ worktrees }) => {
  const { timeRange, rows } = useMemo(() => {
    const timestamps = worktrees
      .flatMap((wt) => [wt.created_at, wt.ready_at, wt.completed_at].filter(Boolean))
      .map((t) => new Date(t!).getTime());

    if (timestamps.length === 0) return { timeRange: { start: 0, end: 1 }, rows: [] };

    const start = Math.min(...timestamps);
    const end = Math.max(...timestamps, start + 1000);

    const rows = worktrees.map((wt) => {
      const created = new Date(wt.created_at).getTime();
      const ready = wt.ready_at ? new Date(wt.ready_at).getTime() : created;
      const completed = wt.completed_at ? new Date(wt.completed_at).getTime() : end;

      return {
        worktree: wt,
        segments: [
          { start: created, end: ready, status: 'creating' },
          { start: ready, end: completed, status: wt.status === 'failed' ? 'failed' : 'in_use' },
        ],
      };
    });

    return { timeRange: { start, end }, rows };
  }, [worktrees]);

  if (worktrees.length === 0) {
    return (
      <div className="text-center p-8 text-theme-text-secondary">
        No timeline data available.
      </div>
    );
  }

  const chartWidth = 800;
  const rowHeight = 32;
  const labelWidth = 160;
  const padding = 8;
  const totalHeight = rows.length * rowHeight + padding * 2;
  const duration = timeRange.end - timeRange.start;

  const toX = (time: number) => {
    return labelWidth + ((time - timeRange.start) / duration) * (chartWidth - labelWidth - padding);
  };

  return (
    <div className="overflow-x-auto">
      <svg width={chartWidth} height={totalHeight} className="text-theme-text-secondary">
        {/* Time axis */}
        <line
          x1={labelWidth}
          y1={0}
          x2={labelWidth}
          y2={totalHeight}
          stroke="currentColor"
          strokeOpacity={0.2}
        />

        {/* Rows */}
        {rows.map((row, index) => {
          const y = index * rowHeight + padding;
          const label = row.worktree.agent_name || row.worktree.branch_name.split('/').pop() || '';

          return (
            <g key={row.worktree.id}>
              {/* Row background */}
              {index % 2 === 0 && (
                <rect x={0} y={y} width={chartWidth} height={rowHeight} fill="currentColor" fillOpacity={0.02} />
              )}

              {/* Label */}
              <text x={8} y={y + rowHeight / 2 + 4} fontSize={11} fill="currentColor" fillOpacity={0.7}>
                {label.length > 18 ? label.substring(0, 18) + '...' : label}
              </text>

              {/* Task bars */}
              {row.segments.map((seg, segIndex) => {
                const x = toX(seg.start);
                const w = Math.max(toX(seg.end) - x, 2);
                const barHeight = rowHeight - 10;
                const barY = y + 5;

                return (
                  <rect
                    key={segIndex}
                    x={x}
                    y={barY}
                    width={w}
                    height={barHeight}
                    rx={3}
                    fill={STATUS_COLORS[seg.status] || '#94a3b8'}
                    opacity={0.8}
                  />
                );
              })}
            </g>
          );
        })}

        {/* Duration label */}
        <text
          x={chartWidth - padding}
          y={totalHeight - 2}
          fontSize={10}
          fill="currentColor"
          fillOpacity={0.5}
          textAnchor="end"
        >
          {(duration / 1000).toFixed(1)}s total
        </text>
      </svg>
    </div>
  );
};
