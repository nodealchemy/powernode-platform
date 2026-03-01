import React, { useRef, useState, useCallback } from 'react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { EnhancedAIOverview, EnhancedAIOverviewHandle } from '@/features/ai/orchestration/components/EnhancedAIOverview';
import { Radio } from 'lucide-react';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import { useRefreshAction } from '@/shared/hooks/useRefreshAction';

export const AIOverviewPage: React.FC = () => {
  const overviewRef = useRef<EnhancedAIOverviewHandle>(null);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [isLiveUpdates, setIsLiveUpdates] = useState(false);

  // WebSocket for real-time updates
  usePageWebSocket({
    pageType: 'ai',
    onDataUpdate: () => {
      // Trigger data refresh if needed
    }
  });

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

  const { refreshAction } = useRefreshAction({
    onRefresh: handleRefresh,
    loading: isRefreshing,
  });

  return (
    <PageContainer
      title="AI Dashboard"
      description="Command center for AI agents, missions, and workflows"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'AI' }
      ]}
      actions={[
        refreshAction,
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
