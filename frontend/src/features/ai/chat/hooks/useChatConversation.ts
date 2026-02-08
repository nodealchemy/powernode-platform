import { useState, useCallback } from 'react';
import { chatApi, ChatConversation, ChatMessage } from '../services/chatApi';

interface UseChatConversationReturn {
  conversation: ChatConversation | null;
  messages: ChatMessage[];
  isLoading: boolean;
  isSending: boolean;
  error: string | null;
  initConversation: (agentId: string) => Promise<void>;
  sendMessage: (content: string) => Promise<void>;
}

export function useChatConversation(): UseChatConversationReturn {
  const [conversation, setConversation] = useState<ChatConversation | null>(null);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [isSending, setIsSending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [currentAgentId, setCurrentAgentId] = useState<string | null>(null);

  const initConversation = useCallback(async (agentId: string) => {
    setIsLoading(true);
    setError(null);
    setCurrentAgentId(agentId);

    try {
      const conv = await chatApi.getOrCreateConversation(agentId);
      setConversation(conv);

      // Load message history
      const history = await chatApi.getHistory(agentId, conv.id);
      setMessages(history);
    } catch {
      setError('Failed to initialize conversation');
    } finally {
      setIsLoading(false);
    }
  }, []);

  const sendMessage = useCallback(async (content: string) => {
    if (!conversation || !currentAgentId || isSending) return;

    setIsSending(true);
    setError(null);

    try {
      const response = await chatApi.sendMessage(currentAgentId, conversation.id, content);
      setMessages(prev => [...prev, response]);
    } catch {
      setError('Failed to send message');
    } finally {
      setIsSending(false);
    }
  }, [conversation, currentAgentId, isSending]);

  return {
    conversation,
    messages,
    isLoading,
    isSending,
    error,
    initConversation,
    sendMessage
  };
}
