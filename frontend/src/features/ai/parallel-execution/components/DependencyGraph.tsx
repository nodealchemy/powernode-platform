import React, { useMemo } from 'react';
import type { ParallelWorktree } from '../types';

interface DependencyGraphProps {
  worktrees: ParallelWorktree[];
}

const NODE_WIDTH = 120;
const NODE_HEIGHT = 40;
const NODE_MARGIN_X = 40;
const NODE_MARGIN_Y = 20;
// Theme tokens with the original hex as fallback (rendered as SVG fill/stroke,
// where CSS vars resolve) — mirrors the sibling TimelineView so the graph is
// theme-adaptive instead of hardcoded.
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

export const DependencyGraph: React.FC<DependencyGraphProps> = ({ worktrees }) => {
  const layout = useMemo(() => {
    const cols = Math.ceil(Math.sqrt(worktrees.length));
    return worktrees.map((wt, index) => {
      const col = index % cols;
      const row = Math.floor(index / cols);
      return {
        worktree: wt,
        x: col * (NODE_WIDTH + NODE_MARGIN_X) + 20,
        y: row * (NODE_HEIGHT + NODE_MARGIN_Y) + 20,
      };
    });
  }, [worktrees]);

  if (worktrees.length === 0) {
    return (
      <div className="text-center p-8 text-theme-secondary">
        No worktrees to display.
      </div>
    );
  }

  const cols = Math.ceil(Math.sqrt(worktrees.length));
  const rows = Math.ceil(worktrees.length / cols);
  const svgWidth = cols * (NODE_WIDTH + NODE_MARGIN_X) + 40;
  const svgHeight = rows * (NODE_HEIGHT + NODE_MARGIN_Y) + 40;

  return (
    <div className="overflow-auto">
      <svg width={svgWidth} height={svgHeight}>
        {layout.map((node) => {
          const color = STATUS_COLORS[node.worktree.status] || 'var(--color-text-tertiary, #94a3b8)';
          const label = node.worktree.agent_name || node.worktree.branch_name.split('/').pop() || '';

          return (
            <g key={node.worktree.id}>
              <rect
                x={node.x}
                y={node.y}
                width={NODE_WIDTH}
                height={NODE_HEIGHT}
                rx={6}
                fill={color}
                fillOpacity={0.15}
                stroke={color}
                strokeWidth={1.5}
              />
              <text
                x={node.x + NODE_WIDTH / 2}
                y={node.y + NODE_HEIGHT / 2 + 4}
                textAnchor="middle"
                fontSize={10}
                fill="currentColor"
                className="text-theme-primary"
              >
                {label.length > 14 ? label.substring(0, 14) + '...' : label}
              </text>
            </g>
          );
        })}
      </svg>
    </div>
  );
};
