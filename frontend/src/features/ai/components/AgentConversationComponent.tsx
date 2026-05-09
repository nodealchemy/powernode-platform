import React, { useState, useEffect, useRef, useCallback } from 'react';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { agentsApi, conversationsApi, workspacesApi } from '@/shared/services/ai';
import { apiClient } from '@/shared/services/apiClient';
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
import { MissionStatusBar } from '@/features/ai/provisioning/MissionStatusBar';

// Union type to accept either conversation format
type ConversationInput = AiConversation | ConversationBase;

interface AgentConversationComponentProps {
  conversation: ConversationInput;
  onConversationUpdate?: (conversation: ConversationInput) => void;
  onNewMessage?: (message: AiMessage) => void;
  // Lazy-creation hook — chat surface passes this for pending tabs to
  // materialize the server-side row before the first message send. Returns
  // the agent_id to use for the send call (may differ from conversation.ai_agent
  // when materialization is what assigns the agent). Returns null on failure.
  beforeSend?: () => Promise<string | null>;
  // Lazy-creation gate — false while the conversation is pending (no DB row
  // yet); true once materialized. Skips the websocket subscription while
  // pending so it doesn't get rejected by the channel's row-existence check.
  isPending?: boolean;
}

export const AgentConversationComponent: React.FC<AgentConversationComponentProps> = ({
  conversation,
  onConversationUpdate: _onConversationUpdate,
  onNewMessage,
  beforeSend,
  isPending = false
}) => {
  const [messages, setMessagesRaw] = useState<AiMessage[]>([]);
  const [loading, setLoading] = useState(true);
  const [sending, setSending] = useState(false);
  const [inputValue, setInputValue] = useState('');
  const inputValueRef = useRef('');
  const [typingUsers, setTypingUsers] = useState<Set<string>>(new Set());
  const [aiThinking, setAiThinking] = useState<string | null>(null);
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

  // The conversation prop is a synthetic placeholder from the chat tab's
  // metadata (per ChatWindow.tsx + SplitPanelContainer.tsx via
  // buildSyntheticConversation). The mount effect below replaces it with
  // the full server row via conversationsApi.getConversation. Derivations
  // (isConcierge, isProvisioning, isWorkspace) prefer the fetched copy
  // when available so newly-introduced conversation_type discriminators
  // work without coordinating frontend type plumbing through the tab
  // builder.
  const [realConversation, setRealConversation] = useState<AiConversation | null>(null);
  const effectiveConversation = realConversation || (conversation as AiConversation);

  const agentId = effectiveConversation.ai_agent?.id;
  const isConcierge = !!effectiveConversation.ai_agent?.is_concierge;
  // M5 conversation unification — when conversation_type='provisioning',
  // MessageList renders a provisioning-specific cold-open greeting +
  // suggestion chips instead of the generic concierge greeting.
  const isProvisioning = effectiveConversation.conversation_type === 'provisioning';
  const { isConnected } = useWebSocket();

  // WebSocket connection. Skipped while the conversation is pending (lazy
  // creation has not yet materialized the DB row); flips on after materialize.
  const { sendChannelMessage } = useConversationSocket({
    conversationId: conversation.id,
    currentUserId: currentUser?.id,
    onNewMessage,
    setMessages,
    setTypingUsers,
    setAiThinking,
    enabled: !isPending
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
    if (isPending) {
      // Lazy-pending conversation — no DB row yet, no messages to fetch.
      setLoading(false);
      return;
    }
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
    } catch (err) {
      // Stale tab: conversation deleted server-side. Same close-tab signal
      // as the realConversation fetch — whichever 404 fires first wins; the
      // listener (in ChatWindowContext) is idempotent so duplicate events
      // are harmless.
      const status = (err as { response?: { status?: number } })?.response?.status;
      if (status === 404) {
        window.dispatchEvent(new CustomEvent('ai:conversation-not-found', {
          detail: { conversationId: conversation.id }
        }));
      } else {
        addNotification({
          type: 'error',
          title: 'Load Failed',
          message: 'Failed to load conversation messages'
        });
      }
    } finally {
      setLoading(false);
    }
  }, [conversation.id, agentId, isPending, addNotification]);

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
    if (!messageContent || !currentUser) return;

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
      // Materialize lazy-created conversations (e.g., provisioning tab opened
      // by quick-launch but the DB row was deferred until first message).
      // beforeSend may return a freshly-allocated agent_id when materialization
      // is what assigns it, so prefer it over the prop-derived agentId.
      let resolvedAgentId = agentId;
      if (beforeSend) {
        const materializedAgentId = await beforeSend();
        if (materializedAgentId === null) {
          // Materialization failed; surface the optimistic message removal and bail.
          setMessages(prev => prev.filter(m => m.id !== optimisticMessage.id));
          setSending(false);
          return;
        }
        if (materializedAgentId) resolvedAgentId = materializedAgentId;
      }

      if (!resolvedAgentId) {
        throw new Error('No agent associated with this conversation');
      }

      // Include mention metadata when mentions are present
      const currentMentions = pendingMentionsRef.current;
      const messagePayload = currentMentions.length > 0
        ? { content: messageContent, metadata: { mentions: currentMentions } }
        : messageContent;

      const response = await agentsApi.sendMessage(resolvedAgentId, conversation.id, messagePayload);

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
  }, [currentUser, conversation.id, agentId, beforeSend, addNotification]);

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

  // Ref to track whether this conversation is a workspace (set after first verification)
  const isWorkspaceRef = useRef(false);

  // Refresh workspace members for mention autocomplete. Parallel-fetches
  // workspace team members + extension-provided mention sources (system
  // extension peer-mirror agents — see Phase 10.7). Each source is
  // best-effort; a 404 from a missing extension doesn't break the picker.
  const refreshWorkspaceMembers = useCallback(async () => {
    const sources = await Promise.allSettled([
      workspacesApi.getWorkspace(conversation.id).then((r) => r.members || []),
      // System extension peer-mirror agents (operators of node-instance peers).
      // Loaded only when the extension serves the endpoint; 404/network error
      // is silently dropped so non-system installs aren't affected.
      apiClient
        .get<{ data?: { members?: unknown[] }; members?: unknown[] }>(
          '/api/v1/system/node_instance_peers/mentionable'
        )
        .then((res: { data: { data?: { members?: unknown[] }; members?: unknown[] } }) => {
          const inner = res.data.data ?? res.data;
          const members = (inner as { members?: unknown[] }).members;
          return Array.isArray(members) ? members : [];
        }),
    ]);

    const merged = sources.flatMap((s) =>
      s.status === 'fulfilled' ? (s.value as unknown[]) : []
    );
    // Cast: the parent's MentionMember shape is the lowest-common-denominator
    // we receive — both sources return {id, name, role, agent_type}.
    setWorkspaceMembers(
      merged as Array<{ id: string; name: string; role: string; agent_type: string; is_lead: boolean }>
    );
  }, [conversation.id]);

  // Fetch the full conversation server-side after mount. The prop is a
  // synthetic placeholder (from the tab metadata) — the fetched row is
  // the source of truth for conversation_type, agent_team, etc. Stored
  // in component state so derivations re-evaluate on update.
  // Skipped while isPending (lazy-creation: no DB row exists yet); re-runs
  // when isPending flips to false after materialization.
  useEffect(() => {
    if (isPending) return;
    let cancelled = false;
    const verifyAndFetch = async () => {
      try {
        const real = await conversationsApi.getConversation(conversation.id);
        if (cancelled) return;
        // Cast via unknown — ConversationDetail is a strict superset of
        // AiConversation in practice but TS can't prove the shape match.
        setRealConversation(real as unknown as AiConversation);
        const isWorkspace = real.conversation_type === 'team' &&
          real.agent_team?.team_type === 'workspace' &&
          real.agent_team?.id;
        isWorkspaceRef.current = !!isWorkspace;
        if (isWorkspace) {
          await refreshWorkspaceMembers();
        }
      } catch (err) {
        // Stale tab: the conversation was deleted server-side while it was
        // still open here (cleanup job, manual delete, cross-device sync).
        // Emit an event so ChatWindowContext can close the orphaned tab —
        // we use a CustomEvent to keep this component decoupled from the
        // chat surface (it's also rendered standalone in AgentChatPage and
        // ConversationContinueModal where the event is simply ignored).
        const status = (err as { response?: { status?: number } })?.response?.status;
        if (status === 404) {
          window.dispatchEvent(new CustomEvent('ai:conversation-not-found', {
            detail: { conversationId: conversation.id }
          }));
        }
        // Otherwise non-critical — derivations fall back to the synthetic prop
      }
    };
    verifyAndFetch();
    return () => { cancelled = true; };
  }, [conversation.id, refreshWorkspaceMembers, isPending]);

  // Re-fetch workspace members when members are added/removed via the panel
  useEffect(() => {
    const handler = (e: Event) => {
      const detail = (e as CustomEvent).detail;
      if (detail?.conversationId === conversation.id && isWorkspaceRef.current) {
        refreshWorkspaceMembers();
      }
    };
    window.addEventListener('powernode:workspace-members-changed', handler);
    return () => window.removeEventListener('powernode:workspace-members-changed', handler);
  }, [conversation.id, refreshWorkspaceMembers]);

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

  // Load initial messages. Re-runs when isPending flips false after lazy
  // materialization so the conversation's empty state transitions to its
  // real (still empty, but server-backed) state.
  useEffect(() => {
    loadMessages();
  }, [conversation.id, isPending]);

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
        {isProvisioning && <MissionStatusBar messages={messages} />}
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
          isProvisioning={isProvisioning}
          onConciergeConfirm={loadMessages}
          onSuggestedMessage={handleSendMessage}
          hasOlder={hasOlder}
          loadingOlder={loadingOlder}
          onLoadOlder={loadOlderMessages}
          onClearChat={handleClearChat}
          onMentionClick={handleMentionClick}
          aiThinking={aiThinking}
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
