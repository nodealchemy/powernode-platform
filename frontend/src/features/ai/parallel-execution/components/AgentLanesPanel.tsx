import React from 'react';
import { AgentLane } from './AgentLane';
import type { ParallelWorktree } from '../types';

interface AgentLanesPanelProps {
  worktrees: ParallelWorktree[];
}

export const AgentLanesPanel: React.FC<AgentLanesPanelProps> = ({ worktrees }) => {
  if (worktrees.length === 0) {
    return (
      <div className="text-center p-8 text-theme-text-secondary">
        No worktrees provisioned yet.
      </div>
    );
  }

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
      {worktrees.map((wt) => (
        <AgentLane key={wt.id} worktree={wt} />
      ))}
    </div>
  );
};
