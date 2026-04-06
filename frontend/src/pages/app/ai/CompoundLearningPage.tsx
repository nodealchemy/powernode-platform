import React, { useState, useEffect, useCallback } from 'react';
import { ArrowUpRight } from 'lucide-react';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useRefreshAction } from '@/shared/hooks/useRefreshAction';
import { promoteCrossTeam } from '@/features/ai/learning/services/compoundLearningApi';
import { CompoundMetricsDashboard } from '@/features/ai/learning/components/CompoundMetricsDashboard';
import { LearningsList } from '@/features/ai/learning/components/LearningsList';

interface CompoundLearningContentProps {
  onActionsReady?: (actions: PageAction[]) => void;
}

export const CompoundLearningContent: React.FC<CompoundLearningContentProps> = ({ onActionsReady }) => {
  const [refreshKey, setRefreshKey] = useState(0);
  const { addNotification } = useNotifications();

  const handlePromote = useCallback(async () => {
    try {
      const count = await promoteCrossTeam();
      addNotification({
        type: 'success',
        message: count > 0 ? `Promoted ${count} learnings to global scope` : 'No learnings eligible for promotion',
      });
      setRefreshKey((k) => k + 1);
    } catch (_error) {
      addNotification({ type: 'error', message: 'Failed to promote learnings' });
    }
  }, [addNotification]);

  const { refreshAction } = useRefreshAction({
    onRefresh: useCallback(() => {
      setRefreshKey((k) => k + 1);
    }, []),
  });

  useEffect(() => {
    onActionsReady?.([
      {
        label: 'Promote Cross-Team',
        onClick: handlePromote,
        icon: ArrowUpRight,
        variant: 'secondary' as const,
      },
      refreshAction,
    ]);
  }, [onActionsReady, refreshAction, handlePromote]);

  return (
    <div className="space-y-6">
      <CompoundMetricsDashboard key={`metrics-${refreshKey}`} />
      <LearningsList refreshKey={refreshKey} />
    </div>
  );
};

const CompoundLearningPage: React.FC = () => {
  const [refreshKey, setRefreshKey] = useState(0);
  const { addNotification } = useNotifications();

  const handlePromote = async () => {
    try {
      const count = await promoteCrossTeam();
      addNotification({
        type: 'success',
        message: count > 0 ? `Promoted ${count} learnings to global scope` : 'No learnings eligible for promotion',
      });
      setRefreshKey((k) => k + 1);
    } catch (_error) {
      addNotification({ type: 'error', message: 'Failed to promote learnings' });
    }
  };

  const actions: PageAction[] = [
    {
      label: 'Promote Cross-Team',
      onClick: handlePromote,
      icon: ArrowUpRight,
      variant: 'secondary' as const,
    },
  ];

  return (
    <PageContainer
      title="Compound Learning"
      description="Knowledge that compounds across executions - each run makes the next one better"
      actions={actions}
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'AI', href: '/app/ai' },
        { label: 'Compound Learning' },
      ]}
    >
      <div className="space-y-6">
        <CompoundMetricsDashboard key={`metrics-${refreshKey}`} />
        <LearningsList refreshKey={refreshKey} />
      </div>
    </PageContainer>
  );
};

export default CompoundLearningPage;
