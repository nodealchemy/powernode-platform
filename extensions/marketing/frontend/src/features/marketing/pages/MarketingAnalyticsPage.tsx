import React from 'react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { CampaignAnalytics } from '../components/CampaignAnalytics';

export const MarketingAnalyticsPage: React.FC = () => {
  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'Marketing', href: '/app/marketing/campaigns' },
    { label: 'Analytics' },
  ];

  return (
    <PageContainer
      title="Marketing Analytics"
      description="Track campaign performance, channel metrics, and ROI."
      breadcrumbs={breadcrumbs}
    >
      <CampaignAnalytics />
    </PageContainer>
  );
};
