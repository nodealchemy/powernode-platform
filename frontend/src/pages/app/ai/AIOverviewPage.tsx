import React, { useRef, useState, useCallback } from 'react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { EnhancedAIOverview, EnhancedAIOverviewHandle } from '@/features/ai-orchestration/components/EnhancedAIOverview';
import { RefreshCw, Radio } from 'lucide-react';

export const AIOverviewPage: React.FC = () => {
  const overviewRef = useRef<EnhancedAIOverviewHandle>(null);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [isLiveUpdates, setIsLiveUpdates] = useState(true);

  const handleRefresh = useCallback(async () => {
    if (overviewRef.current) {
      setIsRefreshing(true);
      await overviewRef.current.refresh();
      setIsRefreshing(false);
    }
  }, []);

  const handleToggleLiveUpdates = useCallback(() => {
    if (overviewRef.current) {
      overviewRef.current.toggleLiveUpdates();
      setIsLiveUpdates(prev => !prev);
    }
  }, []);

  return (
    <PageContainer
      title="AI Overview"
      description="AI system dashboard and quick actions"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'AI' }
      ]}
      actions={[
        {
          id: 'refresh',
          label: isRefreshing ? 'Refreshing...' : 'Refresh',
          onClick: handleRefresh,
          variant: 'outline',
          icon: RefreshCw,
          disabled: isRefreshing
        },
        {
          id: 'live-updates',
          label: isLiveUpdates ? 'Live' : 'Paused',
          onClick: handleToggleLiveUpdates,
          variant: isLiveUpdates ? 'success' : 'secondary',
          icon: Radio
        }
      ]}
    >
      <EnhancedAIOverview ref={overviewRef} />
    </PageContainer>
  );
};
