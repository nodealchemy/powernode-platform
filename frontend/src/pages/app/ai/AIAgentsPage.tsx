import React, { useState } from 'react';
import { Plus } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { AiAgentDashboard } from '@/features/ai-agents/components/AiAgentDashboard';
import { usePermissions } from '@/shared/hooks/usePermissions';

export const AIAgentsPage: React.FC = () => {
  const [showCreateModal, setShowCreateModal] = useState(false);
  const { hasPermission } = usePermissions();

  const canCreateAgents = hasPermission('ai.agents.create');

  const pageActions = canCreateAgents ? [
    {
      id: 'create-agent',
      label: 'Create Agent',
      onClick: () => setShowCreateModal(true),
      variant: 'primary' as const,
      icon: Plus
    }
  ] : [];

  return (
    <PageContainer
      title="AI Agents"
      description="Create and manage AI agents"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'AI', href: '/app/ai' },
        { label: 'Agents' }
      ]}
      actions={pageActions}
    >
      <AiAgentDashboard
        showCreateModal={showCreateModal}
        onShowCreateModalChange={setShowCreateModal}
      />
    </PageContainer>
  );
};

export default AIAgentsPage;
