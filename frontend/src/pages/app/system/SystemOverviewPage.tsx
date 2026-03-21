import React, { useRef, useState, useCallback } from 'react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { SystemOverview, SystemOverviewHandle } from '@/features/system/components/SystemOverview';
import { RefreshCw } from 'lucide-react';

export const SystemOverviewPage: React.FC = () => {
  const overviewRef = useRef<SystemOverviewHandle>(null);
  const [isRefreshing, setIsRefreshing] = useState(false);

  const handleRefresh = useCallback(async () => {
    if (overviewRef.current) {
      setIsRefreshing(true);
      await overviewRef.current.refresh();
      setIsRefreshing(false);
    }
  }, []);

  return (
    <PageContainer
      title="System Overview"
      description="Infrastructure management dashboard for nodes, providers, modules, and operations"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'System' }
      ]}
      actions={[
        {
          id: 'refresh',
          label: isRefreshing ? 'Refreshing...' : 'Refresh',
          onClick: handleRefresh,
          variant: 'outline',
          icon: RefreshCw,
          disabled: isRefreshing
        }
      ]}
    >
      <SystemOverview ref={overviewRef} />
    </PageContainer>
  );
};

export default SystemOverviewPage;
