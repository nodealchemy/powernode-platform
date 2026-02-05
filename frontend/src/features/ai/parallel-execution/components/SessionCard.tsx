import React from 'react';
import { GitBranch, Clock, GitMerge } from 'lucide-react';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { WorktreeStatusBadge } from './WorktreeStatusBadge';
import type { ParallelSession } from '../types';

interface SessionCardProps {
  session: ParallelSession;
  onClick: (session: ParallelSession) => void;
}

export const SessionCard: React.FC<SessionCardProps> = ({ session, onClick }) => {
  const progress = session.progress_percentage;

  return (
    <Card
      className="cursor-pointer hover:border-theme-brand-primary/50 transition-colors"
      onClick={() => onClick(session)}
    >
      <CardContent className="p-4">
        <div className="flex items-center justify-between mb-3">
          <div className="flex items-center gap-2">
            <GitBranch className="w-4 h-4 text-theme-text-secondary" />
            <span className="font-medium text-theme-text-primary truncate max-w-[200px]">
              {session.base_branch}
            </span>
          </div>
          <WorktreeStatusBadge status={session.status} type="session" size="sm" />
        </div>

        <div className="text-xs text-theme-text-secondary mb-3 truncate">
          {session.repository_path}
        </div>

        {/* Progress bar */}
        <div className="h-1.5 bg-theme-bg-secondary rounded-full overflow-hidden mb-3">
          <div
            className="h-full bg-theme-status-info rounded-full transition-all duration-300"
            style={{ width: `${progress}%` }}
          />
        </div>

        <div className="flex items-center justify-between text-xs text-theme-text-secondary">
          <div className="flex items-center gap-3">
            <span className="flex items-center gap-1">
              <GitBranch className="w-3 h-3" />
              {session.completed_worktrees}/{session.total_worktrees}
            </span>
            <span className="flex items-center gap-1">
              <GitMerge className="w-3 h-3" />
              {session.merge_strategy}
            </span>
          </div>
          {session.duration_ms && (
            <span className="flex items-center gap-1">
              <Clock className="w-3 h-3" />
              {(session.duration_ms / 1000).toFixed(1)}s
            </span>
          )}
        </div>

        {session.source_type && (
          <div className="mt-2 text-xs text-theme-text-tertiary">
            Source: {session.source_type.replace('Ai::', '')}
          </div>
        )}
      </CardContent>
    </Card>
  );
};
