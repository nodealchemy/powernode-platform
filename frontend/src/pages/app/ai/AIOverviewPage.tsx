import React, { useRef, useState, useCallback } from 'react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { EnhancedAIOverview, EnhancedAIOverviewHandle } from '@/features/ai/orchestration/components/EnhancedAIOverview';
import { useRefreshAction } from '@/shared/hooks/useRefreshAction';

export const AIOverviewPage: React.FC = () => {
  const overviewRef = useRef<EnhancedAIOverviewHandle>(null);
  const [isRefreshing, setIsRefreshing] = useState(false);

  const handleRefresh = useCallback(async () => {
    if (overviewRef.current) {
      setIsRefreshing(true);
      await overviewRef.current.refresh();
      setIsRefreshing(false);
    }
  }, []);

  const { refreshAction } = useRefreshAction({
    onRefresh: handleRefresh,
    loading: isRefreshing,
  });

  return (
    <PageContainer
      title="AI Dashboard"
      description="Command center for AI agents, missions, and teams"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'AI' }
      ]}
      actions={[refreshAction]}
    >
      <EnhancedAIOverview ref={overviewRef} />
    </PageContainer>
  );
};
