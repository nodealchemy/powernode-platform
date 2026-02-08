import { useState, useCallback } from 'react';
import type { AgentCard } from '@/shared/services/ai/types/a2a-types';

export function useAgentCards() {
  const [cardViewMode, setCardViewMode] = useState<'list' | 'detail' | 'create' | 'edit'>('list');
  const [selectedCard, setSelectedCard] = useState<AgentCard | null>(null);
  const [cardListKey, setCardListKey] = useState(0);

  const handleSelectCard = useCallback((card: AgentCard) => {
    setSelectedCard(card);
    setCardViewMode('detail');
  }, []);

  const handleEditCard = useCallback((card: AgentCard) => {
    setSelectedCard(card);
    setCardViewMode('edit');
  }, []);

  const handleCreateCard = useCallback(() => {
    setSelectedCard(null);
    setCardViewMode('create');
  }, []);

  const handleSaveCard = useCallback((card: AgentCard) => {
    setSelectedCard(card);
    setCardViewMode('detail');
    setCardListKey((k) => k + 1);
  }, []);

  const handleCardCancel = useCallback(() => {
    if (cardViewMode === 'edit' && selectedCard) {
      setCardViewMode('detail');
    } else {
      setCardViewMode('list');
      setSelectedCard(null);
    }
  }, [cardViewMode, selectedCard]);

  const handleBackToCardList = useCallback(() => {
    setCardViewMode('list');
    setSelectedCard(null);
  }, []);

  return {
    cardViewMode,
    selectedCard,
    cardListKey,
    handleSelectCard,
    handleEditCard,
    handleCreateCard,
    handleSaveCard,
    handleCardCancel,
    handleBackToCardList,
  };
}
