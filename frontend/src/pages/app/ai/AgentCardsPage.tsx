import React, { useState, useCallback } from 'react';
import { Plus } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { AgentCardList, AgentCardDetail, AgentCardEditor } from '@/features/ai/agent-cards';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import { useRefreshAction } from '@/shared/hooks/useRefreshAction';
import type { AgentCard } from '@/shared/services/ai/types/a2a-types';

type ViewMode = 'list' | 'detail' | 'create' | 'edit';

export const AgentCardsPage: React.FC = () => {
  const [viewMode, setViewMode] = useState<ViewMode>('list');
  const [selectedCard, setSelectedCard] = useState<AgentCard | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [listKey, setListKey] = useState(0);

  const { hasPermission } = usePermissions();

  // WebSocket for real-time updates
  usePageWebSocket({
    pageType: 'ai',
    onDataUpdate: () => {
      setListKey((k) => k + 1);
    },
  });

  const handleRefresh = useCallback(async () => {
    setIsLoading(true);
    try {
      setListKey((k) => k + 1);
    } finally {
      setIsLoading(false);
    }
  }, []);

  const { refreshAction } = useRefreshAction({
    onRefresh: handleRefresh,
    loading: isLoading,
  });

  const canCreateAgentCards = hasPermission('ai.agents.create');
  const canManageAgentCards = hasPermission('ai.agents.update');

  const handleSelectCard = (card: AgentCard) => {
    setSelectedCard(card);
    setViewMode('detail');
  };

  const handleEditCard = (card: AgentCard) => {
    setSelectedCard(card);
    setViewMode('edit');
  };

  const handleCreateCard = () => {
    setSelectedCard(null);
    setViewMode('create');
  };

  const handleSaveCard = (card: AgentCard) => {
    setSelectedCard(card);
    setViewMode('detail');
    setListKey((k) => k + 1);
  };

  const handleCancel = () => {
    if (viewMode === 'edit' && selectedCard) {
      setViewMode('detail');
    } else {
      setViewMode('list');
      setSelectedCard(null);
    }
  };

  const handleBackToList = () => {
    setViewMode('list');
    setSelectedCard(null);
  };

  // Build breadcrumbs based on current view
  const getBreadcrumbs = () => {
    const base = [
      { label: 'Dashboard', href: '/app' },
      { label: 'AI', href: '/app/ai' },
    ];

    switch (viewMode) {
      case 'list':
        return [...base, { label: 'Agent Cards' }];
      case 'detail':
        return [
          ...base,
          { label: 'Agent Cards', href: '/app/ai/agent-cards', onClick: handleBackToList },
          { label: selectedCard?.name || 'Details' },
        ];
      case 'create':
        return [
          ...base,
          { label: 'Agent Cards', href: '/app/ai/agent-cards', onClick: handleBackToList },
          { label: 'Create' },
        ];
      case 'edit':
        return [
          ...base,
          { label: 'Agent Cards', href: '/app/ai/agent-cards', onClick: handleBackToList },
          { label: selectedCard?.name || 'Edit', onClick: () => setViewMode('detail') },
          { label: 'Edit' },
        ];
      default:
        return base;
    }
  };

  // Build actions based on current view
  const getActions = () => {
    switch (viewMode) {
      case 'list':
        return [
          refreshAction,
          ...(canCreateAgentCards
            ? [
                {
                  id: 'create-agent-card',
                  label: 'Create Agent Card',
                  onClick: handleCreateCard,
                  variant: 'primary' as const,
                  icon: Plus,
                },
              ]
            : []),
        ];
      case 'detail':
        return [
          {
            id: 'back',
            label: 'Back to List',
            onClick: handleBackToList,
            variant: 'secondary' as const,
          },
          ...(canManageAgentCards && selectedCard
            ? [
                {
                  id: 'edit',
                  label: 'Edit',
                  onClick: () => setViewMode('edit'),
                  variant: 'primary' as const,
                },
              ]
            : []),
        ];
      default:
        return [];
    }
  };

  // Get title and description based on current view
  const getPageInfo = () => {
    switch (viewMode) {
      case 'list':
        return {
          title: 'Agent Cards',
          description: 'A2A Agent Cards for agent discovery and communication',
        };
      case 'detail':
        return {
          title: selectedCard?.name || 'Agent Card Details',
          description: selectedCard?.description || 'View agent card details',
        };
      case 'create':
        return {
          title: 'Create Agent Card',
          description: 'Create a new A2A Agent Card',
        };
      case 'edit':
        return {
          title: `Edit ${selectedCard?.name || 'Agent Card'}`,
          description: 'Update agent card configuration',
        };
      default:
        return { title: 'Agent Cards', description: '' };
    }
  };

  const pageInfo = getPageInfo();

  return (
    <PageContainer
      title={pageInfo.title}
      description={pageInfo.description}
      breadcrumbs={getBreadcrumbs()}
      actions={getActions()}
    >
      {viewMode === 'list' && (
        <AgentCardList
          key={listKey}
          onSelectCard={handleSelectCard}
          onEditCard={handleEditCard}
        />
      )}

      {viewMode === 'detail' && selectedCard && (
        <AgentCardDetail
          cardId={selectedCard.id}
          onEdit={() => setViewMode('edit')}
          onClose={handleBackToList}
        />
      )}

      {viewMode === 'create' && (
        <AgentCardEditor onSave={handleSaveCard} onCancel={handleCancel} />
      )}

      {viewMode === 'edit' && selectedCard && (
        <AgentCardEditor
          cardId={selectedCard.id}
          onSave={handleSaveCard}
          onCancel={handleCancel}
        />
      )}
    </PageContainer>
  );
};

export default AgentCardsPage;
