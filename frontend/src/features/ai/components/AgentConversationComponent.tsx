import React, { useState, useEffect, useRef, useCallback } from 'react';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { agentsApi } from '@/shared/services/ai';
import { MessageThread } from '@/features/ai/chat/components/MessageThread';
import type {
  AiConversation,
  AiMessage,
} from '@/shared/types/ai';
import type { ConversationBase } from '@/shared/services/ai/ConversationsApiService';
import { cleanMessageContent, mapBackendMessage } from './conversation/utils';
import { useConversationSocket } from './conversation/useConversationSocket';
import { useMessageActions } from './conversation/useMessageActions';
import { MessageList } from './conversation/MessageList';
import { MessageComposer } from './conversation/MessageComposer';

// Union type to accept either conversation format
type ConversationInput = AiConversation | ConversationBase;

interface AgentConversationComponentProps {
  conversation: ConversationInput;
  onConversationUpdate?: (conversation: ConversationInput) => void;
  onNewMessage?: (message: AiMessage) => void;
}

export const AgentConversationComponent: React.FC<AgentConversationComponentProps> = ({
  conversation,
  onConversationUpdate: _onConversationUpdate,
  onNewMessage
}) => {
  const [messages, setMessages] = useState<AiMessage[]>([]);
  const [loading, setLoading] = useState(true);
  const [sending, setSending] = useState(false);
  const [inputValue, setInputValue] = useState('');
  const [typingUsers, setTypingUsers] = useState<Set<string>>(new Set());
  const [isTyping, setIsTyping] = useState(false);
  const [editingMessageId, setEditingMessageId] = useState<string | null>(null);
  const [editSaving, setEditSaving] = useState(false);
  const [threadMessage, setThreadMessage] = useState<AiMessage | null>(null);
  const [threadMessages, setThreadMessages] = useState<AiMessage[]>([]);
  const [threadLoading, setThreadLoading] = useState(false);

  const messagesEndRef = useRef<HTMLDivElement>(null);
  const typingTimeoutRef = useRef<NodeJS.Timeout | undefined>(undefined);

  const { addNotification } = useNotifications();
  const currentUser = useSelector((state: RootState) => state.auth.user);

  const agentId = conversation.ai_agent?.id;

  // WebSocket connection
  const { sendChannelMessage } = useConversationSocket({
    conversationId: conversation.id,
    currentUserId: currentUser?.id,
    onNewMessage,
    setMessages,
    setTypingUsers
  });

  // Message action handlers
  const {
    handleCopyMessage,
    handleRegenerateResponse,
    handleRateMessage,
    handleEditMessage,
    handleDeleteMessage,
    handleOpenThread,
    handleSendReply
  } = useMessageActions({
    conversationId: conversation.id,
    agentId,
    setMessages,
    setEditingMessageId,
    setEditSaving,
    setThreadMessage,
    setThreadMessages,
    setThreadLoading,
    threadMessage
  });

  const scrollToBottom = useCallback(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, []);

  const loadMessages = useCallback(async () => {
    if (!agentId) {
      setLoading(false);
      return;
    }

    try {
      setLoading(true);
      const response = await agentsApi.getMessages(agentId, conversation.id);
      const rawMessages = Array.isArray(response) ? response : [];
      const mapped = rawMessages.map((msg: AiMessage) => mapBackendMessage(msg as unknown as Record<string, unknown>));
      setMessages(mapped);
    } catch (_error) {
      addNotification({
        type: 'error',
        title: 'Load Failed',
        message: 'Failed to load conversation messages'
      });
    } finally {
      setLoading(false);
    }
  }, [conversation.id]); // eslint-disable-line react-hooks/exhaustive-deps

  const handleSendMessage = useCallback(async () => {
    if (!inputValue.trim() || sending || !currentUser) return;

    const messageContent = inputValue.trim();
    setInputValue('');
    setSending(true);

    // Create optimistic message for immediate UI feedback
    const optimisticMessage: AiMessage = {
      id: `temp-${Date.now()}`,
      sender_type: 'user' as const,
      sender_info: { name: currentUser.name || 'You' },
      content: messageContent,
      created_at: new Date().toISOString(),
      metadata: {
        optimistic: true,
        timestamp: new Date().toISOString()
      }
    };

    setMessages(prev => [...prev, optimisticMessage]);

    try {
      if (!agentId) {
        throw new Error('No agent associated with this conversation');
      }

      const response = await agentsApi.sendMessage(agentId, conversation.id, messageContent);

      const userMsg: AiMessage = {
        id: response.user_message?.id || optimisticMessage.id,
        sender_type: 'user',
        sender_info: { name: currentUser.name || 'You' },
        content: response.user_message?.content || messageContent,
        created_at: response.user_message?.created_at || new Date().toISOString(),
        metadata: { timestamp: response.user_message?.created_at || new Date().toISOString() }
      };

      setMessages(prev => {
        const withoutOptimistic = prev.filter(msg => msg.id !== optimisticMessage.id);
        const newMessages = [...withoutOptimistic, userMsg];

        if (response.assistant_message) {
          const assistantMsg: AiMessage = {
            id: response.assistant_message.id,
            sender_type: 'ai',
            sender_info: { name: 'AI Assistant' },
            content: cleanMessageContent(response.assistant_message.content || ''),
            created_at: response.assistant_message.created_at || new Date().toISOString(),
            metadata: {
              timestamp: response.assistant_message.created_at || new Date().toISOString(),
              tokens_used: response.assistant_message.token_count,
              cost_estimate: parseFloat(response.assistant_message.cost_usd) || 0
            }
          };
          newMessages.push(assistantMsg);
        }

        return newMessages;
      });

      if (response.error) {
        addNotification({
          type: 'warning',
          title: 'Partial Response',
          message: response.error
        });
      }
    } catch (_error) {
      setMessages(prev => prev.filter(msg => msg.id !== optimisticMessage.id));
      addNotification({
        type: 'error',
        title: 'Send Failed',
        message: 'Failed to send message. Please try again.'
      });
      setInputValue(messageContent);
    } finally {
      setSending(false);
    }
  }, [inputValue, sending, currentUser, conversation.id, agentId]); // eslint-disable-line react-hooks/exhaustive-deps

  const handleTyping = useCallback(() => {
    if (!isTyping) {
      setIsTyping(true);
      sendChannelMessage.current('AiConversationChannel', 'typing_indicator', {
        typing: true
      }, { conversation_id: conversation.id });
    }

    if (typingTimeoutRef.current) {
      clearTimeout(typingTimeoutRef.current);
    }

    typingTimeoutRef.current = setTimeout(() => {
      setIsTyping(false);
      sendChannelMessage.current('AiConversationChannel', 'typing_indicator', {
        typing: false
      }, { conversation_id: conversation.id });
    }, 1000);
  }, [isTyping, conversation.id, sendChannelMessage]);

  // Cleanup typing timeout
  useEffect(() => {
    return () => {
      if (typingTimeoutRef.current) {
        clearTimeout(typingTimeoutRef.current);
      }
    };
  }, []);

  // Load initial messages
  useEffect(() => {
    loadMessages();
  }, [conversation.id]); // eslint-disable-line react-hooks/exhaustive-deps

  // Auto-scroll to bottom when messages change
  useEffect(() => {
    if (messages.length > 0) {
      setTimeout(() => {
        scrollToBottom();
      }, 100);
    }
  }, [messages, scrollToBottom]);

  if (loading) {
    return (
      <div className="h-full flex items-center justify-center bg-theme-background">
        <div className="flex flex-col items-center gap-4 p-8">
          <div className="relative">
            <div className="w-12 h-12 border-3 border-theme-interactive-primary/20 border-t-theme-interactive-primary rounded-full animate-spin"></div>
            <div className="absolute inset-3 w-6 h-6 bg-theme-interactive-primary/10 rounded-full animate-ping"></div>
          </div>
          <div className="text-center">
            <h3 className="font-semibold text-theme-primary mb-1">Loading conversation</h3>
            <p className="text-sm text-theme-secondary">Preparing your AI assistant...</p>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="h-full flex bg-theme-background">
      {/* Main chat area */}
      <div className={`flex flex-col ${threadMessage ? 'w-[60%]' : 'w-full'} transition-all duration-200`}>
        {/* Messages */}
        <MessageList
          messages={messages}
          currentUser={currentUser}
          editingMessageId={editingMessageId}
          editSaving={editSaving}
          typingUsers={typingUsers}
          messagesEndRef={messagesEndRef as React.RefObject<HTMLDivElement>}
          onCopy={handleCopyMessage}
          onRate={handleRateMessage}
          onRegenerate={handleRegenerateResponse}
          onEdit={handleEditMessage}
          onSetEditing={setEditingMessageId}
          onDelete={handleDeleteMessage}
          onOpenThread={handleOpenThread}
        />

        {/* Input Area */}
        <MessageComposer
          value={inputValue}
          onChange={setInputValue}
          onSend={handleSendMessage}
          onTyping={handleTyping}
          sending={sending}
        />
      </div>

      {/* Thread panel */}
      {threadMessage && (
        <div className="w-[40%] border-l border-theme">
          <MessageThread
            parentMessage={threadMessage}
            threadMessages={threadMessages}
            loading={threadLoading}
            onSendReply={handleSendReply}
            onClose={() => {
              setThreadMessage(null);
              setThreadMessages([]);
            }}
          />
        </div>
      )}
    </div>
  );
};
