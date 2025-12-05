import React from 'react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { EnhancedAIOverview } from '@/features/ai-orchestration/components/EnhancedAIOverview';

export const AIOverviewPage: React.FC = () => {
  return (
    <PageContainer
      title="AI Overview"
      description="AI system dashboard and quick actions"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'AI' }
      ]}
    >
      <EnhancedAIOverview />
    </PageContainer>
  );
};
