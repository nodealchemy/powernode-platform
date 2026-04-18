import React from 'react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { DailySummariesPanel } from '@/features/content/pages/components/DailySummariesPanel';

export const DailySummariesPage: React.FC = () => {
  return (
    <PageContainer
      title="Daily Summaries"
      description="Auto-generated operational summaries for your account"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'Content', href: '/app/content/pages' },
        { label: 'Daily Summaries' },
      ]}
    >
      <DailySummariesPanel />
    </PageContainer>
  );
};

export default DailySummariesPage;
