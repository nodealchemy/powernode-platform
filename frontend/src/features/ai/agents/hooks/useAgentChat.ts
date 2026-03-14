import { useState, useCallback } from 'react';
import { agentsApi } from '@/shared/services/ai';
import type { AiAgent, AiConversation } from '@/shared/types/ai';

export function useAgentChat() {
  const [chatAgent, setChatAgent] = useState<AiAgent | null>(null);
  const [chatConversation, setChatConversation] = useState<AiConversation | null>(null);
  const [showChatModal, setShowChatModal] = useState(false);
  const [showCreateConversationModal, setShowCreateConversationModal] = useState(false);

  const handleChatWithAgent = useCallback(async (agent: AiAgent) => {
    try {
      setChatAgent(agent);
      const response = await agentsApi.getActiveConversations(agent.id);
      const conversations = response.items || [];
      if (conversations.length > 0) {
        setChatConversation(conversations[0]);
        setShowChatModal(true);
      } else {
        setShowCreateConversationModal(true);
      }
    } catch (_error) {
      setChatAgent(agent);
      setShowCreateConversationModal(true);
    }
  }, []);

  const handleConversationCreatedForChat = useCallback((conversation: AiConversation) => {
    setShowCreateConversationModal(false);
    setChatConversation(conversation);
    setShowChatModal(true);
  }, []);

  const closeChatModal = useCallback(() => {
    setShowChatModal(false);
    setChatConversation(null);
    setChatAgent(null);
  }, []);

  const closeCreateConversationModal = useCallback(() => {
    setShowCreateConversationModal(false);
    setChatAgent(null);
  }, []);

  return {
    chatAgent,
    chatConversation,
    showChatModal,
    showCreateConversationModal,
    handleChatWithAgent,
    handleConversationCreatedForChat,
    closeChatModal,
    closeCreateConversationModal,
  };
}
