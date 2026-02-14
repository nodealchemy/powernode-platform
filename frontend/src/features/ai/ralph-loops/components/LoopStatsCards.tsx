import React from 'react';
import { Card, CardContent } from '@/shared/components/ui/Card';

interface LoopStatsCardsProps {
  currentIteration: number;
  maxIterations: number;
  completedTaskCount: number;
  taskCount: number;
  progressPercentage: number;
  defaultAgentName: string | null | undefined;
}

export const LoopStatsCards: React.FC<LoopStatsCardsProps> = ({
  currentIteration,
  maxIterations,
  completedTaskCount,
  taskCount,
  progressPercentage,
  defaultAgentName,
}) => {
  return (
    <div className="grid grid-cols-4 gap-4">
      <Card>
        <CardContent className="p-4">
          <div className="text-2xl font-bold text-theme-text-primary">
            {currentIteration}/{maxIterations}
          </div>
          <div className="text-sm text-theme-text-secondary">Iterations</div>
        </CardContent>
      </Card>
      <Card>
        <CardContent className="p-4">
          <div className="text-2xl font-bold text-theme-text-primary">
            {completedTaskCount}/{taskCount}
          </div>
          <div className="text-sm text-theme-text-secondary">Tasks Completed</div>
        </CardContent>
      </Card>
      <Card>
        <CardContent className="p-4">
          <div className="text-2xl font-bold text-theme-text-primary">
            {progressPercentage}%
          </div>
          <div className="text-sm text-theme-text-secondary">Progress</div>
        </CardContent>
      </Card>
      <Card>
        <CardContent className="p-4">
          <div className="text-2xl font-bold text-theme-text-primary truncate">
            {defaultAgentName || 'No Agent'}
          </div>
          <div className="text-sm text-theme-text-secondary">Default Agent</div>
        </CardContent>
      </Card>
    </div>
  );
};
