import React, { useState, useEffect, useCallback } from 'react';
import { RefreshCw, ArrowUpRight, Lightbulb } from 'lucide-react';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useRefreshAction } from '@/shared/hooks/useRefreshAction';
import { promoteCrossTeam } from '@/features/ai/learning/services/compoundLearningApi';
import { CompoundMetricsDashboard } from '@/features/ai/learning/components/CompoundMetricsDashboard';
import { LearningsList } from '@/features/ai/learning/components/LearningsList';

type TabType = 'metrics' | 'learnings';

interface CompoundLearningContentProps {
  onActionsReady?: (actions: PageAction[]) => void;
}

// Extracted content component (everything inside PageContainer) for embedding in tabbed pages
export const CompoundLearningContent: React.FC<CompoundLearningContentProps> = ({ onActionsReady }) => {
  const [activeTab, setActiveTab] = useState<TabType>('metrics');
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

  const tabs = [
    { id: 'metrics' as const, label: 'Metrics' },
    { id: 'learnings' as const, label: 'All Learnings' },
  ];

  return (
    <>
      <div className="rounded-lg border border-theme-border bg-theme-surface/50 p-4 mb-6">
        <div className="flex items-start gap-3">
          <Lightbulb className="w-5 h-5 text-theme-warning shrink-0 mt-0.5" />
          <div className="text-sm text-theme-secondary">
            <p className="font-medium text-theme-primary mb-1">Knowledge that compounds over time</p>
            <p>
              As agents execute tasks, they discover patterns, best practices, and failure modes.
              These findings are tracked as compound learnings — their effectiveness is measured
              across executions, and the most valuable ones are promoted for cross-team use.
            </p>
          </div>
        </div>
      </div>
      <div className="flex gap-1 mb-6 border-b border-theme-border">
        {tabs.map((tab) => (
          <button
            key={tab.id}
            onClick={() => setActiveTab(tab.id)}
            className={`px-4 py-2 text-sm font-medium border-b-2 transition-colors ${
              activeTab === tab.id
                ? 'border-theme-primary text-theme-primary'
                : 'border-transparent text-theme-muted hover:text-theme-secondary'
            }`}
          >
            {tab.label}
          </button>
        ))}
      </div>
      <div key={refreshKey}>
        {activeTab === 'metrics' && <CompoundMetricsDashboard />}
        {activeTab === 'learnings' && <LearningsList />}
      </div>
    </>
  );
};

const CompoundLearningPage: React.FC = () => {
  const [activeTab, setActiveTab] = useState<TabType>('metrics');
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
    {
      label: 'Refresh',
      onClick: () => setRefreshKey((k) => k + 1),
      icon: RefreshCw,
      variant: 'secondary' as const,
    },
  ];

  const tabs = [
    { id: 'metrics' as const, label: 'Metrics' },
    { id: 'learnings' as const, label: 'All Learnings' },
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
      {/* Tab navigation */}
      <div className="flex gap-1 mb-6 border-b border-theme-border">
        {tabs.map((tab) => (
          <button
            key={tab.id}
            onClick={() => setActiveTab(tab.id)}
            className={`px-4 py-2 text-sm font-medium border-b-2 transition-colors ${
              activeTab === tab.id
                ? 'border-theme-primary text-theme-primary'
                : 'border-transparent text-theme-muted hover:text-theme-secondary'
            }`}
          >
            {tab.label}
          </button>
        ))}
      </div>

      {/* Tab content */}
      <div key={refreshKey}>
        {activeTab === 'metrics' && <CompoundMetricsDashboard />}
        {activeTab === 'learnings' && <LearningsList />}
      </div>
    </PageContainer>
  );
};

export default CompoundLearningPage;
