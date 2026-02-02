import React, { useState, useCallback } from 'react';
import { Plus } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { AiAgentDashboard } from '@/features/ai/agents/components/AiAgentDashboard';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useAiOrchestrationWebSocket } from '@/shared/hooks/useAiOrchestrationWebSocket';
import { useRefreshAction } from '@/shared/hooks/useRefreshAction';

export const AIAgentsPage: React.FC = () => {
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [refreshKey, setRefreshKey] = useState(0);
  const { hasPermission } = usePermissions();

  // WebSocket for real-time agent updates
  useAiOrchestrationWebSocket({
    onAgentEvent: (event) => {
      // Refresh agent list when agents are created, updated, or deleted
      if (['agent_created', 'agent_updated', 'agent_deleted', 'agent_execution_completed'].includes(event.type)) {
        setRefreshKey(prev => prev + 1);
      }
    },
  });

  const handleRefresh = useCallback(async () => {
    setIsLoading(true);
    setRefreshKey(prev => prev + 1);
    setIsLoading(false);
  }, []);

  const { refreshAction } = useRefreshAction({
    onRefresh: handleRefresh,
    loading: isLoading,
  });

  const canCreateAgents = hasPermission('ai.agents.create');

  const pageActions = [
    refreshAction,
    ...(canCreateAgents ? [{
      id: 'create-agent',
      label: 'Create Agent',
      onClick: () => setShowCreateModal(true),
      variant: 'primary' as const,
      icon: Plus
    }] : [])
  ];

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
        key={refreshKey}
        showCreateModal={showCreateModal}
        onShowCreateModalChange={setShowCreateModal}
      />
    </PageContainer>
  );
};

export default AIAgentsPage;
