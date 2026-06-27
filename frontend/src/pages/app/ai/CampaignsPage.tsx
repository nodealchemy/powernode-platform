import React, { useState, useMemo, useCallback } from 'react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import type { PageAction, BreadcrumbItem } from '@/shared/components/layout/PageContainer';
import { CampaignsContent } from '@/features/campaigns/pages/CampaignsPage';

export const CampaignsPageWrapper: React.FC = () => {
  const [actions, setActions] = useState<PageAction[]>([]);

  const breadcrumbs = useMemo<BreadcrumbItem[]>(() => [
    { label: 'Dashboard', href: '/app' },
    { label: 'AI', href: '/app/ai' },
    { label: 'Campaigns' },
  ], []);

  const handleActionsReady = useCallback((newActions: PageAction[]) => {
    setActions(newActions);
  }, []);

  return (
    <PageContainer
      title="Improvement Campaigns"
      description="Autonomous, repeatable improvement runs — an agent drives a backlog to verified, committed outcomes."
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      <CampaignsContent onActionsReady={handleActionsReady} />
    </PageContainer>
  );
};

export default CampaignsPageWrapper;
