import React from 'react';
import { Card, CardContent } from '@/shared/components/ui/Card';
import type { ParallelSessionDetail } from '../types';

interface SessionSummaryCardsProps {
  session: ParallelSessionDetail;
}

export const SessionSummaryCards: React.FC<SessionSummaryCardsProps> = ({ session }) => {
  const stats = [
    {
      label: 'Worktrees',
      value: `${session.completed_worktrees}/${session.total_worktrees}`,
    },
    {
      label: 'Failed',
      value: session.failed_worktrees,
    },
    {
      label: 'Progress',
      value: `${session.progress_percentage}%`,
    },
    {
      label: 'Duration',
      value: session.duration_ms ? `${(session.duration_ms / 1000).toFixed(1)}s` : '--',
    },
  ];

  return (
    <div className="grid grid-cols-4 gap-4">
      {stats.map((stat) => (
        <Card key={stat.label}>
          <CardContent className="p-4">
            <div className="text-2xl font-bold text-theme-text-primary">{stat.value}</div>
            <div className="text-sm text-theme-text-secondary">{stat.label}</div>
          </CardContent>
        </Card>
      ))}
    </div>
  );
};
