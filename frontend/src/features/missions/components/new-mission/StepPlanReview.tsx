import React, { useEffect, useState } from 'react';
import { Loader2, RefreshCw } from 'lucide-react';
import { missionsApi } from '../../api/missionsApi';
import { MissionTaskGraph } from '../task-graph/MissionTaskGraph';
import { Button } from '@/shared/components/ui/Button';
import type { TaskGraph } from '../../types/mission';
import { logger } from '@/shared/utils/logger';

interface StepPlanReviewProps {
  missionId: string;
  onPlanReady: (plan: TaskGraph) => void;
}

export const StepPlanReview: React.FC<StepPlanReviewProps> = ({
  missionId,
  onPlanReady,
}) => {
  const [plan, setPlan] = useState<TaskGraph | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const composePlan = async () => {
    setLoading(true);
    setError(null);
    try {
      const response = await missionsApi.composePlan(missionId);
      const composedPlan = response.data.plan;
      setPlan(composedPlan);
      onPlanReady(composedPlan);
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to compose plan';
      setError(message);
      logger.error('Failed to compose plan', { missionId, error: message });
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    composePlan();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [missionId]);

  if (loading) {
    return (
      <div className="flex flex-col items-center justify-center py-8 gap-3">
        <Loader2 className="w-6 h-6 animate-spin text-theme-accent" />
        <p className="text-sm text-theme-secondary">Composing task plan from skills...</p>
      </div>
    );
  }

  if (error) {
    return (
      <div className="space-y-4">
        <div className="text-center py-4">
          <p className="text-sm text-theme-error">{error}</p>
        </div>
        <div className="flex justify-center">
          <Button variant="ghost" onClick={composePlan}>
            <RefreshCw className="w-4 h-4 mr-1.5" />
            Retry
          </Button>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h4 className="text-sm font-medium text-theme-primary">Proposed Task Plan</h4>
          <p className="text-xs text-theme-secondary mt-0.5">
            {plan?.nodes.length ?? 0} tasks composed from available skills
          </p>
        </div>
        <Button variant="ghost" size="sm" onClick={composePlan}>
          <RefreshCw className="w-4 h-4 mr-1.5" />
          Regenerate
        </Button>
      </div>
      <MissionTaskGraph taskGraph={plan} loading={false} />
    </div>
  );
};
