import React from 'react';
import { AgentCardList, AgentCardDetail, AgentCardEditor } from '@/features/ai/agent-cards';
import type { AgentCard } from '@/shared/services/ai/types/a2a-types';

interface CardsTabProps {
  cardViewMode: 'list' | 'detail' | 'create' | 'edit';
  selectedCard: AgentCard | null;
  cardListKey: number;
  onSelectCard: (card: AgentCard) => void;
  onEditCard: (card: AgentCard) => void;
  onSaveCard: (card: AgentCard) => void;
  onCancelCard: () => void;
  onBackToList: () => void;
}

export const CardsTab: React.FC<CardsTabProps> = ({
  cardViewMode,
  selectedCard,
  cardListKey,
  onSelectCard,
  onEditCard,
  onSaveCard,
  onCancelCard,
  onBackToList,
}) => (
  <>
    {cardViewMode === 'list' && (
      <AgentCardList
        key={cardListKey}
        onSelectCard={onSelectCard}
        onEditCard={onEditCard}
      />
    )}

    {cardViewMode === 'detail' && selectedCard && (
      <AgentCardDetail
        cardId={selectedCard.id}
        onEdit={() => onEditCard(selectedCard)}
        onClose={onBackToList}
      />
    )}

    {cardViewMode === 'create' && (
      <AgentCardEditor onSave={onSaveCard} onCancel={onCancelCard} />
    )}

    {cardViewMode === 'edit' && selectedCard && (
      <AgentCardEditor
        cardId={selectedCard.id}
        onSave={onSaveCard}
        onCancel={onCancelCard}
      />
    )}
  </>
);
