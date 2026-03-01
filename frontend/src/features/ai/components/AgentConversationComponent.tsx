import React, { useState, useEffect, useRef, useCallback } from 'react';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { agentsApi, conversationsApi, workspacesApi } from '@/shared/services/ai';
import { MessageThread } from '@/features/ai/chat/components/MessageThread';
import type {
  AiConversation,
  AiMessage,
} from '@/shared/types/ai';
import type { ConversationBase } from '@/shared/services/ai/ConversationsApiService';
import { cleanStreamingContent, mapBackendMessage } from './conversation/utils';
import { useConversationSocket } from './conversation/useConversationSocket';
import { useWebSocket } from '@/shared/hooks/useWebSocket';
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
  const [messages, setMessagesRaw] = useState<AiMessage[]>([]);
  const [loading, setLoading] = useState(true);
  const [sending, setSending] = useState(false);
  const [inputValue, setInputValue] = useState('');
  const inputValueRef = useRef('');
  const [typingUsers, setTypingUsers] = useState<Set<string>>(new Set());
  const [isTyping, setIsTyping] = useState(false);
  const [editingMessageId, setEditingMessageId] = useState<string | null>(null);
  const [editSaving, setEditSaving] = useState(false);
  const [threadMessage, setThreadMessage] = useState<AiMessage | null>(null);
  const [threadMessages, setThreadMessages] = useState<AiMessage[]>([]);
  const [threadLoading, setThreadLoading] = useState(false);
  const [workspaceMembers, setWorkspaceMembers] = useState<Array<{ id: string; name: string; role: string; agent_type: string; is_lead: boolean }>>([]);
  const [pendingMentions, setPendingMentions] = useState<Array<{ id: string; name: string }>>([]);
  const pendingMentionsRef = useRef<Array<{ id: string; name: string }>>([]);
  pendingMentionsRef.current = pendingMentions;

  // Cursor-based pagination state
  const [hasOlder, setHasOlder] = useState(false);
  const [loadingOlder, setLoadingOlder] = useState(false);
  const [oldestCursor, setOldestCursor] = useState<number | null>(null);
  const newestCursorRef = useRef<number | null>(null);

  // Dedup wrapper: ensures no two messages share the same ID (last write wins)
  const setMessages: typeof setMessagesRaw = useCallback((update) => {
    setMessagesRaw(prev => {
      const next = typeof update === 'function' ? update(prev) : update;
      const seen = new Set<string>();
      const deduped: AiMessage[] = [];
      for (let i = next.length - 1; i >= 0; i--) {
        if (!seen.has(next[i].id)) {
          seen.add(next[i].id);
          deduped.push(next[i]);
        }
      }
      deduped.reverse();
      return deduped;
    });
  }, []);

  const messagesEndRef = useRef<HTMLDivElement>(null);
  const typingTimeoutRef = useRef<NodeJS.Timeout | undefined>(undefined);

  const { addNotification } = useNotifications();
  const currentUser = useSelector((state: RootState) => state.auth.user);

  const agentId = conversation.ai_agent?.id;
  const isConcierge = !!(conversation as AiConversation).ai_agent?.is_concierge;
  const { isConnected } = useWebSocket();

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

  const handlePlanAction = useCallback(async (actionType: string, executionId: string, feedback?: string) => {
    await conversationsApi.sendPlanResponse(conversation.id, actionType, executionId, feedback);
    addNotification({
      type: 'success',
      title: actionType === 'approve' ? 'Plan Approved' : 'Changes Requested',
      message: actionType === 'approve' ? 'Plan approved. Execution starting...' : 'Feedback submitted. Revising plan...'
    });
    loadMessages();
  }, [conversation.id]);

  const initialLoadRef = useRef(true);

  const scrollToBottom = useCallback((instant?: boolean) => {
    messagesEndRef.current?.scrollIntoView({ behavior: instant ? 'instant' : 'smooth' });
  }, []);

  const loadMessages = useCallback(async () => {
    if (!agentId) {
      setLoading(false);
      return;
    }

    try {
      setLoading(true);
      const response = await agentsApi.getMessages(agentId, conversation.id);
      const mapped = (response.messages || []).map((msg: AiMessage) => mapBackendMessage(msg as unknown as Record<string, unknown>));
      setMessages(mapped);
      setHasOlder(response.pagination?.has_older ?? false);
      setOldestCursor(response.pagination?.oldest_cursor ?? null);
      newestCursorRef.current = response.pagination?.newest_cursor ?? null;
    } catch (_error) {
      addNotification({
        type: 'error',
        title: 'Load Failed',
        message: 'Failed to load conversation messages'
      });
    } finally {
      setLoading(false);
    }
  }, [conversation.id]);

  // Catch up on messages missed during WebSocket disconnection or tab blur
  const catchUpMissedMessages = useCallback(async () => {
    if (!agentId || !newestCursorRef.current || loading) return;
    try {
      const response = await agentsApi.getMessages(agentId, conversation.id, { after: newestCursorRef.current });
      if (response.messages?.length > 0) {
        const mapped = response.messages.map((msg: AiMessage) => mapBackendMessage(msg as unknown as Record<string, unknown>));
        setMessages(prev => [...prev, ...mapped]);
        newestCursorRef.current = response.pagination?.newest_cursor ?? newestCursorRef.current;
      }
    } catch (_error) {
      // Silent — catch-up is best-effort
    }
  }, [conversation.id, agentId, loading]);

  const loadOlderMessages = useCallback(async () => {
    if (!agentId || !hasOlder || loadingOlder || !oldestCursor) return;
    try {
      setLoadingOlder(true);
      const response = await agentsApi.getMessages(agentId, conversation.id, { before: oldestCursor });
      const mapped = (response.messages || []).map((msg: AiMessage) => mapBackendMessage(msg as unknown as Record<string, unknown>));
      setMessages(prev => [...mapped, ...prev]);
      setHasOlder(response.pagination?.has_older ?? false);
      setOldestCursor(response.pagination?.oldest_cursor ?? null);
    } catch (_error) {
      addNotification({
        type: 'error',
        title: 'Load Failed',
        message: 'Failed to load older messages'
      });
    } finally {
      setLoadingOlder(false);
    }
  }, [conversation.id, agentId, hasOlder, loadingOlder, oldestCursor]);

  const handleClearChat = useCallback(async () => {
    if (!agentId) return;
    if (!window.confirm('Clear all messages in this conversation? This cannot be undone.')) return;
    try {
      await agentsApi.clearMessages(agentId, conversation.id);
      setMessages([]);
      setHasOlder(false);
      setOldestCursor(null);
      addNotification({ type: 'success', title: 'Chat Cleared', message: 'All messages have been cleared' });
    } catch (_error) {
      addNotification({ type: 'error', title: 'Error', message: 'Failed to clear messages' });
    }
  }, [conversation.id, agentId]);  

  const handleInputChange = useCallback((value: string) => {
    inputValueRef.current = value;
    setInputValue(value);
  }, []);

  const handleMentionClick = useCallback((name: string) => {
    const current = inputValueRef.current;
    const needsSpace = current.length > 0 && !current.endsWith(' ');
    const newValue = current + (needsSpace ? ' ' : '') + name + ' ';
    inputValueRef.current = newValue;
    setInputValue(newValue);
    // Focus the composer textarea so the user can continue typing
    requestAnimationFrame(() => {
      const input = document.querySelector<HTMLTextAreaElement>('[data-testid="message-input"]');
      if (input) {
        input.focus();
        input.setSelectionRange(newValue.length, newValue.length);
      }
    });
  }, []);

  const handleSendMessage = useCallback(async (overrideText?: string) => {
    const messageContent = (typeof overrideText === 'string' ? overrideText : inputValueRef.current).trim();
    if (!messageContent || sending || !currentUser) return;

    setInputValue('');
    inputValueRef.current = '';
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

      // Include mention metadata when mentions are present
      const currentMentions = pendingMentionsRef.current;
      const messagePayload = currentMentions.length > 0
        ? { content: messageContent, metadata: { mentions: currentMentions } }
        : messageContent;

      const response = await agentsApi.sendMessage(agentId, conversation.id, messagePayload);

      // Don't construct user message from HTTP response — let WebSocket deliver it
      // with full metadata (mentions, content_metadata). The optimistic message will
      // be replaced by the WebSocket message_created event via content matching.

      // Only handle the assistant message from the HTTP response (concierge sync path)
      if (response.assistant_message) {
        const assistantMessage = response.assistant_message;
        setMessages(prev => {
          const assistantMsg: AiMessage = {
            id: assistantMessage.id,
            sender_type: 'ai',
            sender_info: { name: 'AI Assistant' },
            content: cleanStreamingContent(assistantMessage.content || ''),
            created_at: assistantMessage.created_at || new Date().toISOString(),
            metadata: {
              timestamp: assistantMessage.created_at || new Date().toISOString(),
              tokens_used: assistantMessage.token_count,
              cost_estimate: parseFloat(assistantMessage.cost_usd) || 0
            }
          };
          if (prev.some(msg => msg.id === assistantMsg.id)) return prev;
          return [...prev, assistantMsg];
        });
      }

      // For concierge-routed responses, re-map the assistant message with full metadata
      if (response.concierge_routed && response.assistant_message) {
        const mappedAssistant = mapBackendMessage(response.assistant_message as unknown as Record<string, unknown>);
        setMessages(prev => prev.map(msg =>
          msg.id === mappedAssistant.id ? mappedAssistant : msg
        ));
        setSending(false);
        return;
      }

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
      inputValueRef.current = messageContent;
    } finally {
      setSending(false);
    }
  }, [sending, currentUser, conversation.id, agentId]);

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

  // Fetch workspace members for mention autocomplete.
  // The conversation prop may be a synthetic object from tab state (SplitPanelContainer)
  // with stale workspace flags, so we verify via the real conversations API first.
  useEffect(() => {
    let cancelled = false;
    const fetchWorkspaceMembers = async () => {
      try {
        const real = await conversationsApi.getConversation(conversation.id);
        if (cancelled) return;
        const isWorkspace = real.conversation_type === 'team' &&
          real.agent_team?.team_type === 'workspace' &&
          real.agent_team?.id;
        if (isWorkspace) {
          const res = await workspacesApi.getWorkspace(conversation.id);
          if (!cancelled) setWorkspaceMembers(res.members || []);
        }
      } catch {
        // Non-critical — autocomplete just won't work
      }
    };
    fetchWorkspaceMembers();
    return () => { cancelled = true; };
  }, [conversation.id]);

  // Listen for chat-cleared events from the header
  useEffect(() => {
    const handler = (e: Event) => {
      const detail = (e as CustomEvent).detail;
      if (detail?.conversationId === conversation.id) {
        setMessages([]);
        setHasOlder(false);
        setOldestCursor(null);
      }
    };
    window.addEventListener('powernode:chat-cleared', handler);
    return () => window.removeEventListener('powernode:chat-cleared', handler);
  }, [conversation.id]);

  // Keep newestCursorRef in sync with messages (covers WebSocket-delivered messages)
  useEffect(() => {
    if (messages.length > 0) {
      const lastMsg = messages[messages.length - 1];
      if (lastMsg.sequence_number && lastMsg.sequence_number > (newestCursorRef.current ?? 0)) {
        newestCursorRef.current = lastMsg.sequence_number;
      }
    }
  }, [messages]);

  // Catch up on missed messages when tab/window regains focus
  useEffect(() => {
    const handler = () => {
      if (document.visibilityState === 'visible') {
        catchUpMissedMessages();
      }
    };
    document.addEventListener('visibilitychange', handler);
    return () => document.removeEventListener('visibilitychange', handler);
  }, [catchUpMissedMessages]);

  // Catch up on missed messages when WebSocket reconnects
  const wasConnectedRef = useRef(isConnected);
  useEffect(() => {
    if (isConnected && !wasConnectedRef.current) {
      catchUpMissedMessages();
    }
    wasConnectedRef.current = isConnected;
  }, [isConnected, catchUpMissedMessages]);

  // Load initial messages
  useEffect(() => {
    loadMessages();
  }, [conversation.id]);

  // Auto-scroll to bottom when messages change (skip when loading older messages)
  useEffect(() => {
    if (loadingOlder) return;
    if (messages.length > 0) {
      if (initialLoadRef.current) {
        // First load: jump to bottom instantly (no animation)
        initialLoadRef.current = false;
        setTimeout(() => scrollToBottom(true), 50);
      } else {
        // Subsequent messages: smooth scroll
        setTimeout(() => scrollToBottom(), 100);
      }
    }
  }, [messages, scrollToBottom, loadingOlder]);

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
          onPlanAction={handlePlanAction}
          conversationId={conversation.id}
          isConcierge={isConcierge}
          onConciergeConfirm={loadMessages}
          onSuggestedMessage={handleSendMessage}
          hasOlder={hasOlder}
          loadingOlder={loadingOlder}
          onLoadOlder={loadOlderMessages}
          onClearChat={handleClearChat}
          onMentionClick={handleMentionClick}
        />

        {/* Input Area */}
        <MessageComposer
          value={inputValue}
          onChange={handleInputChange}
          onSend={handleSendMessage}
          onTyping={handleTyping}
          sending={sending}
          members={workspaceMembers}
          onMentionsChange={setPendingMentions}
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
