import React from 'react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { AiAgentDashboard } from '@/features/ai-agents/components/AiAgentDashboard';

export const AIAgentsPage: React.FC = () => {
  return (
    <PageContainer
      title="AI Agents"
      description="Create and manage AI agents"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'AI', href: '/app/ai' },
        { label: 'Agents' }
      ]}
    >
      <AiAgentDashboard />
    </PageContainer>
  );
};

export default AIAgentsPage;
