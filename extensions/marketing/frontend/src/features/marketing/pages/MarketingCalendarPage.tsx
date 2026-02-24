import React from 'react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { ContentCalendar } from '../components/ContentCalendar';

export const MarketingCalendarPage: React.FC = () => {
  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'Marketing', href: '/app/marketing/campaigns' },
    { label: 'Calendar' },
  ];

  return (
    <PageContainer
      title="Content Calendar"
      description="Schedule and plan your marketing content across all channels."
      breadcrumbs={breadcrumbs}
    >
      <ContentCalendar />
    </PageContainer>
  );
};
