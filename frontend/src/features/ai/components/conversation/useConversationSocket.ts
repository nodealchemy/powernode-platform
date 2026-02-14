import { useEffect, useRef, useCallback } from 'react';
import { useWebSocket } from '@/shared/hooks/useWebSocket';
import { useNotifications } from '@/shared/hooks/useNotifications';
import type { AiMessage, ConversationChannelMessage } from '@/shared/types/ai';
import { cleanMessageContent } from './utils';

interface UseConversationSocketOptions {
  conversationId: string;
  currentUserId?: string;
  onNewMessage?: (message: AiMessage) => void;
  setMessages: React.Dispatch<React.SetStateAction<AiMessage[]>>;
  setTypingUsers: React.Dispatch<React.SetStateAction<Set<string>>>;
}

export function useConversationSocket({
  conversationId,
  currentUserId,
  onNewMessage,
  setMessages,
  setTypingUsers
}: UseConversationSocketOptions) {
  const { addNotification } = useNotifications();
  const webSocket = useWebSocket();

  // Create stable refs that don't change
  const subscribeRef = useRef(webSocket.subscribe);
  const sendChannelMessageRef = useRef(webSocket.sendMessage);

  // Update refs only when absolutely necessary
  if (subscribeRef.current !== webSocket.subscribe) {
    subscribeRef.current = webSocket.subscribe;
  }
  if (sendChannelMessageRef.current !== webSocket.sendMessage) {
    sendChannelMessageRef.current = webSocket.sendMessage;
  }

  const handleChannelMessageRef = useRef<((data: ConversationChannelMessage) => void) | undefined>(undefined);

  const handleChannelMessage = useCallback((data: ConversationChannelMessage) => {
    switch (data.type) {
      case 'message_created':
        if (data.message) {
          setMessages(prev => {
            // Check if we have an optimistic message to replace
            const optimisticIndex = prev.findIndex(msg =>
              msg.metadata?.optimistic &&
              msg.content === data.message!.content &&
              msg.sender_type === data.message!.sender_type
            );

            if (optimisticIndex >= 0) {
              const newMessages = [...prev];
              newMessages[optimisticIndex] = data.message!;
              return newMessages;
            } else {
              return [...prev, data.message!];
            }
          });
          onNewMessage?.(data.message);
        }
        break;

      case 'ai_response_streaming':
      case 'ai_response_complete':
        if (data.message) {
          const cleanedMessage = {
            ...data.message,
            content: cleanMessageContent(data.message.content || '')
          };
          setMessages(prev => {
            const existingIndex = prev.findIndex(m => m.id === cleanedMessage.id);
            if (existingIndex >= 0) {
              const updated = [...prev];
              updated[existingIndex] = cleanedMessage;
              return updated;
            } else {
              return [...prev, cleanedMessage];
            }
          });
        }
        break;

      case 'typing_indicator':
        if (data.user_id && data.user_id !== currentUserId) {
          setTypingUsers(prev => {
            const updated = new Set(prev);
            const userName = (data.user_name || data.user_id) as string;
            if (data.typing) {
              updated.add(userName);
            } else {
              updated.delete(userName);
            }
            return updated;
          });
        }
        break;

      case 'error':
        addNotification({
          type: 'error',
          title: 'Conversation Error',
          message: (typeof data.message === 'string' ? data.message : 'An error occurred in the conversation')
        });
        break;
    }
  }, [currentUserId]);  

  // Update ref immediately when callback changes
  handleChannelMessageRef.current = handleChannelMessage;

  // Set up WebSocket subscription
  useEffect(() => {
    const unsubscribe = subscribeRef.current({
      channel: 'AiConversationChannel',
      params: {
        conversation_id: conversationId
      },
      onMessage: (data: unknown) => {
        handleChannelMessageRef.current?.(data as ConversationChannelMessage);
      }
    });

    return () => {
      unsubscribe();
    };
  }, [conversationId]);

  return {
    sendChannelMessage: sendChannelMessageRef
  };
}
