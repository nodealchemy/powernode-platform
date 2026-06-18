import React from 'react';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { EntityLink } from '@/shared/components/entity';

interface LoopStatsCardsProps {
  currentIteration: number;
  maxIterations: number;
  completedTaskCount: number;
  taskCount: number;
  progressPercentage: number;
  defaultAgentName: string | null | undefined;
  defaultAgentId?: string | null;
}

export const LoopStatsCards: React.FC<LoopStatsCardsProps> = ({
  currentIteration,
  maxIterations,
  completedTaskCount,
  taskCount,
  progressPercentage,
  defaultAgentName,
  defaultAgentId,
}) => {
  return (
    <div className="grid grid-cols-4 gap-4">
      <Card>
        <CardContent className="p-4">
          <div className="text-2xl font-bold text-theme-primary">
            {currentIteration}/{maxIterations}
          </div>
          <div className="text-sm text-theme-secondary">Iterations</div>
        </CardContent>
      </Card>
      <Card>
        <CardContent className="p-4">
          <div className="text-2xl font-bold text-theme-primary">
            {completedTaskCount}/{taskCount}
          </div>
          <div className="text-sm text-theme-secondary">Tasks Completed</div>
        </CardContent>
      </Card>
      <Card>
        <CardContent className="p-4">
          <div className="text-2xl font-bold text-theme-primary">
            {progressPercentage}%
          </div>
          <div className="text-sm text-theme-secondary">Progress</div>
        </CardContent>
      </Card>
      <Card>
        <CardContent className="p-4">
          <div className="text-2xl font-bold text-theme-primary truncate">
            {defaultAgentName ? (
              <EntityLink type="agent" id={defaultAgentId} label={defaultAgentName} className="text-2xl font-bold" />
            ) : (
              'No Agent'
            )}
          </div>
          <div className="text-sm text-theme-secondary">Default Agent</div>
        </CardContent>
      </Card>
    </div>
  );
};
