import React, { useMemo } from 'react';
import type { ParallelWorktree } from '../types';

interface DependencyGraphProps {
  worktrees: ParallelWorktree[];
}

const NODE_WIDTH = 120;
const NODE_HEIGHT = 40;
const NODE_MARGIN_X = 40;
const NODE_MARGIN_Y = 20;
const STATUS_COLORS: Record<string, string> = {
  pending: '#94a3b8',
  creating: '#60a5fa',
  ready: '#38bdf8',
  in_use: '#fbbf24',
  completed: '#4ade80',
  merged: '#22d3ee',
  cleaned_up: '#a1a1aa',
  failed: '#f87171',
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
      <div className="text-center p-8 text-theme-text-secondary">
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
          const color = STATUS_COLORS[node.worktree.status] || '#94a3b8';
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
                className="text-theme-text-primary"
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
