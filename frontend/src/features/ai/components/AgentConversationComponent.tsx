import React, { useState, useEffect, useRef, useCallback } from 'react';
import ReactMarkdown from 'react-markdown';
import {
  Send,
  Bot,
  User,
  Copy,
  ThumbsUp,
  ThumbsDown,
  RefreshCw,
  AlertCircle,
  Loader2,
  MessageSquare,
  MoreVertical
} from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Avatar } from '@/shared/components/ui/Avatar';
import { DropdownMenu } from '@/shared/components/ui/DropdownMenu';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useWebSocket } from '@/shared/hooks/useWebSocket';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { agentsApi } from '@/shared/services/ai';
import { cleanMarkdownContent } from '@/shared/utils/markdownUtils';
import type {
  AiConversation,
  AiMessage,
  ConversationChannelMessage
} from '@/shared/types/ai';
import type { ConversationBase } from '@/shared/services/ai/ConversationsApiService';

// Union type to accept either conversation format
type ConversationInput = AiConversation | ConversationBase;

interface AgentConversationComponentProps {
  conversation: ConversationInput;
  onConversationUpdate?: (conversation: ConversationInput) => void;
}

export const AgentConversationComponent: React.FC<AgentConversationComponentProps> = ({
  conversation,
  onConversationUpdate: _onConversationUpdate
}) => {
  const [messages, setMessages] = useState<AiMessage[]>([]);
  const [loading, setLoading] = useState(true);
  const [sending, setSending] = useState(false);
  const [inputValue, setInputValue] = useState('');
  const [typingUsers, setTypingUsers] = useState<Set<string>>(new Set());
  const [isTyping, setIsTyping] = useState(false);

  const messagesEndRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLTextAreaElement>(null);
  const typingTimeoutRef = useRef<NodeJS.Timeout | undefined>(undefined);
  
  const { addNotification } = useNotifications();
  const currentUser = useSelector((state: RootState) => state.auth.user);

  // WebSocket connection for real-time updates
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

  const scrollToBottom = useCallback(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, []);

  // Clean message content to remove chunked encoding artifacts
  const cleanMessageContent = (content: string): string => {
    if (!content) return '';

    // First clean markdown content for safety
    let cleaned = cleanMarkdownContent(content);

    // Remove various forms of chunked encoding artifacts
    // These can appear as trailing "0", "0\r\n", or just "0"
    // Also handle cases where the "0" appears after punctuation
    cleaned = cleaned
      ?.replace(/[\r\n]*0[\r\n]*$/, '') // Remove "0" with any line breaks at end
      ?.replace(/^[\r\n]*0[\r\n]*/, '') // Remove leading "0" artifacts
      ?.replace(/([.!?])\s*0\s*$/, '$1') // Remove "0" after punctuation
      ?.replace(/\s+0\s*$/, '') // Remove trailing "0" with whitespace
      ?.replace(/0$/, '') // Remove standalone trailing "0"
      ?.trim() || '';

    return cleaned;
  };

  const loadMessages = useCallback(async () => {
    // Guard: Need ai_agent.id to load messages
    if (!conversation.ai_agent?.id) {
      setLoading(false);
      return;
    }

    try {
      setLoading(true);
      const response = await agentsApi.getMessages(conversation.ai_agent.id, conversation.id);

      // Handle potential Rails wrapper format - API returns array directly
      const rawMessages = Array.isArray(response) ? response : [];

      // Clean message content to remove any artifacts
      const messages = rawMessages.map((msg: AiMessage) => ({
        ...msg,
        content: cleanMessageContent(msg.content || '')
      }));

      setMessages(messages.reverse()); // Reverse to show oldest first
    } catch (error) {
      // Use a ref for addNotification to avoid dependency issues
      addNotification({
        type: 'error',
        title: 'Load Failed',
        message: 'Failed to load conversation messages'
      });
    } finally {
      setLoading(false);
    }
  }, [conversation.id]); // Remove addNotification dependency

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
              const newMessages = [...prev, data.message!];
              return newMessages;
            }
          });
          // Auto-scroll will trigger via useEffect when messages.length changes
        } else {
            }
        break;

      case 'ai_response_streaming':
      case 'ai_response_complete':
        if (data.message) {
          // Clean the message content before updating state
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
          // Auto-scroll will trigger via useEffect when messages change
        }

        break;

      case 'typing_indicator':
        if (data.user_id && data.user_id !== currentUser?.id) {
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
        // Use addNotification directly without dependency
        addNotification({
          type: 'error',
          title: 'Conversation Error',
          message: (typeof data.message === 'string' ? data.message : 'An error occurred in the conversation')
        });
        break;
    }
  }, [currentUser?.id]); // Remove addNotification dependency
  
  // Update ref immediately when callback changes
  handleChannelMessageRef.current = handleChannelMessage;

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

    // Add message immediately to UI
    setMessages(prev => [...prev, optimisticMessage]);

    try {
      // Send message via WebSocket channel (not REST API)
      const messageSent = await sendChannelMessageRef.current('AiConversationChannel', 'send_message', {
        content: messageContent
      }, { conversation_id: conversation.id });

      if (!messageSent) {
        throw new Error('Failed to send message via WebSocket');
      }


      // Keep optimistic message until real message arrives via WebSocket
      // The WebSocket message_created event will replace this optimistic message

      // The real-time channel will handle both user message echo and AI responses
    } catch (error) {

      // Remove optimistic message on error
      setMessages(prev => prev.filter(msg => msg.id !== optimisticMessage.id));

      addNotification({
        type: 'error',
        title: 'Send Failed',
        message: 'Failed to send message. Please try again.'
      });
      setInputValue(messageContent); // Restore the message
    } finally {
      setSending(false);
    }
  }, [inputValue, sending, currentUser, conversation.id]);

  const handleTyping = useCallback(() => {
    if (!isTyping) {
      setIsTyping(true);
      sendChannelMessageRef.current('AiConversationChannel', 'typing_indicator', {
        typing: true
      }, { conversation_id: conversation.id });
    }

    // Clear existing timeout
    if (typingTimeoutRef.current) {
      clearTimeout(typingTimeoutRef.current);
    }

    // Set new timeout to stop typing indicator
    typingTimeoutRef.current = setTimeout(() => {
      setIsTyping(false);
      sendChannelMessageRef.current('AiConversationChannel', 'typing_indicator', {
        typing: false
      }, { conversation_id: conversation.id });
    }, 1000);
  }, [isTyping]);

  const handleInputChange = useCallback((e: React.ChangeEvent<HTMLTextAreaElement>) => {
    setInputValue(e.target.value);
    handleTyping();
  }, [handleTyping]);

  const handleKeyDown = useCallback((e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleSendMessage();
    }
  }, [handleSendMessage]);

  const handleCopyMessage = useCallback(async (message: AiMessage) => {
    try {
      // When copying, strip markdown formatting to get plain text
      const plainText = cleanMarkdownContent(message.content).replace(/0\s*$/, '').trim();
      await navigator.clipboard.writeText(plainText);
      // Use addNotification directly without dependency
      addNotification({
        type: 'success',
        title: 'Copied',
        message: 'Message copied to clipboard'
      });
    } catch (error) {
    }
  }, []); // Remove addNotification dependency

  const handleRegenerateResponse = useCallback(async (messageId: string) => {
    // Need agent_id from conversation to call the API
    const agentId = conversation.ai_agent?.id;
    if (!agentId) {
      addNotification({
        type: 'error',
        title: 'Regeneration Failed',
        message: 'Unable to regenerate - missing agent information'
      });
      return;
    }

    try {
      const result = await agentsApi.regenerateMessage(agentId, conversation.id, messageId);

      if (result.regeneration_queued) {
        addNotification({
          type: 'success',
          title: 'Regeneration Queued',
          message: 'AI response regeneration has been queued. New response will appear shortly.'
        });

        // Update the message in the UI to show regeneration status
        setMessages(prev => prev.map(msg =>
          msg.id === messageId
            ? { ...msg, metadata: { ...msg.metadata, regenerating: true } }
            : msg
        ));
      }
    } catch (error) {
      addNotification({
        type: 'error',
        title: 'Regeneration Failed',
        message: 'Failed to regenerate AI response. Please try again.'
      });
    }
  }, [conversation.id, conversation.ai_agent?.id]);

  const handleRateMessage = useCallback(async (messageId: string, rating: 'thumbs_up' | 'thumbs_down') => {
    // Need agent_id from conversation to call the API
    const agentId = conversation.ai_agent?.id;
    if (!agentId) {
      addNotification({
        type: 'error',
        title: 'Rating Failed',
        message: 'Unable to rate - missing agent information'
      });
      return;
    }

    try {
      const result = await agentsApi.rateMessage(agentId, conversation.id, messageId, rating);

      addNotification({
        type: 'success',
        title: 'Feedback Recorded',
        message: `Thank you for your ${rating === 'thumbs_up' ? 'positive' : 'negative'} feedback!`
      });

      // Update the message in the UI to show rating
      setMessages(prev => prev.map(msg =>
        msg.id === messageId
          ? { ...msg, metadata: { ...msg.metadata, user_rating: result.rating } }
          : msg
      ));
    } catch (error) {
      addNotification({
        type: 'error',
        title: 'Rating Failed',
        message: 'Failed to submit your feedback. Please try again.'
      });
    }
  }, [conversation.id, conversation.ai_agent?.id]);

  const formatTimestamp = (timestamp: string) => {
    return new Date(timestamp).toLocaleTimeString([], { 
      hour: '2-digit', 
      minute: '2-digit' 
    });
  };

  const renderMessage = (message: AiMessage, _index: number) => {
    const isUser = message.sender_type === 'user';
    const isAI = message.sender_type === 'ai';
    const isSystem = message.sender_type === 'system';
    const isProcessing = message.metadata.processing;
    const hasError = message.metadata.error;

    if (isSystem) {
      return (
        <div key={message.id} className="flex justify-center my-4">
          <div className="bg-theme-surface border border-theme px-3 py-1 rounded-full text-sm text-theme-muted shadow-sm">
            {cleanMessageContent(message.content)}
          </div>
        </div>
      );
    }

    return (
      <div
        key={message.id}
        className={`group flex gap-3 mb-4 ${
          isUser ? 'flex-row-reverse' : 'flex-row'
        }`}
      >
        <div className="flex-shrink-0 flex items-start justify-center">
          <Avatar className={`h-8 w-8 flex items-center justify-center ${
            isUser
              ? 'bg-theme-primary text-white'
              : 'bg-theme-surface border border-theme text-theme-primary'
          }`}>
            <div className="flex items-center justify-center w-full h-full">
              {isUser ? (
                <User className="h-4 w-4" />
              ) : (
                <Bot className="h-4 w-4" />
              )}
            </div>
          </Avatar>
        </div>

        <div className={`flex-1 max-w-[85%] sm:max-w-[80%] ${
          isUser ? 'flex flex-col items-end' : 'flex flex-col items-start'
        }`}>
          <div className={`flex items-center gap-2 mb-2 ${
            isUser ? 'flex-row-reverse' : 'flex-row'
          }`}>
            <span className="text-sm font-semibold text-theme-primary">
              {message.sender_info?.name || (isUser ? 'You' : 'AI Assistant')}
            </span>
            <span className="text-xs text-theme-secondary">
              {formatTimestamp(message.created_at)}
            </span>
          </div>

          <div
            className={`rounded-2xl px-4 py-3 max-w-full shadow-md ${
              isUser
                ? 'bg-theme-info text-white rounded-br-md ml-auto'
                : hasError
                ? 'bg-theme-danger/10 dark:bg-theme-danger/20 border border-theme-danger/30 dark:border-theme-danger/50 text-theme-danger dark:text-theme-danger rounded-bl-md'
                : 'bg-theme-surface border border-theme text-theme-primary rounded-bl-md'
            }`}
          >
            {isProcessing ? (
              <div className="flex items-center gap-2 py-1">
                <Loader2 className="h-4 w-4 animate-spin" />
                <span className="text-sm">AI is thinking...</span>
              </div>
            ) : (
              <div className="text-sm break-words">
                {message.sender_type === 'ai' ? (
                  <div className="markdown-content">
                    <ReactMarkdown
                      components={{
                        // Headers
                        h1: ({ children }) => <h1 className="text-2xl font-bold mb-4 mt-6">{children}</h1>,
                        h2: ({ children }) => <h2 className="text-xl font-bold mb-3 mt-5">{children}</h2>,
                        h3: ({ children }) => <h3 className="text-lg font-bold mb-2 mt-4">{children}</h3>,
                        h4: ({ children }) => <h4 className="text-base font-bold mb-2 mt-3">{children}</h4>,
                        // Paragraphs
                        p: ({ children }) => <p className="mb-4">{children}</p>,
                        // Lists
                        ul: ({ children }) => <ul className="list-disc list-inside mb-4 ml-4">{children}</ul>,
                        ol: ({ children }) => <ol className="list-decimal list-inside mb-4 ml-4">{children}</ol>,
                        li: ({ children }) => <li className="mb-1">{children}</li>,
                        // Code blocks
                        pre: ({ children }) => (
                          <pre className="bg-theme-surface dark:bg-theme-surface p-4 rounded-lg overflow-x-auto mb-4 text-sm text-theme-primary dark:text-theme-primary">
                            {children}
                          </pre>
                        ),
                        code: ({ className, children }) => {
                          const isInline = !className?.startsWith('language-');
                          return isInline ? (
                            <code className="bg-theme-surface dark:bg-theme-surface px-1.5 py-0.5 rounded text-sm font-mono text-theme-primary dark:text-theme-primary">
                              {children}
                            </code>
                          ) : (
                            <code className="font-mono text-sm">{children}</code>
                          );
                        },
                        // Links
                        a: ({ href, children }) => (
                          <a
                            href={href}
                            target="_blank"
                            rel="noopener noreferrer"
                            className="text-theme-info hover:text-theme-info/80 underline"
                          >
                            {children}
                          </a>
                        ),
                        // Blockquotes
                        blockquote: ({ children }) => (
                          <blockquote className="border-l-4 border-theme dark:border-theme pl-4 italic mb-4">
                            {children}
                          </blockquote>
                        ),
                        // Horizontal rules
                        hr: () => <hr className="border-t border-theme dark:border-theme my-4" />,
                        // Tables
                        table: ({ children }) => (
                          <div className="overflow-x-auto mb-4">
                            <table className="min-w-full divide-y divide-gray-300 dark:divide-gray-600">
                              {children}
                            </table>
                          </div>
                        ),
                        th: ({ children }) => (
                          <th className="px-3 py-2 text-left text-xs font-medium text-theme-secondary dark:text-theme-secondary uppercase tracking-wider">
                            {children}
                          </th>
                        ),
                        td: ({ children }) => (
                          <td className="px-3 py-2 text-sm text-theme-primary dark:text-theme-primary">
                            {children}
                          </td>
                        ),
                        // Strong and emphasis
                        strong: ({ children }) => <strong className="font-bold">{children}</strong>,
                        em: ({ children }) => <em className="italic">{children}</em>,
                      }}
                    >
                      {cleanMessageContent(message.content)}
                    </ReactMarkdown>
                  </div>
                ) : (
                  <div className="whitespace-pre-wrap">
                    {cleanMessageContent(message.content)}
                  </div>
                )}
              </div>
            )}

            {hasError && (
              <div className="flex items-center gap-2 mt-2 p-2 bg-theme-danger/10 rounded border border-theme-danger/30">
                <AlertCircle className="h-4 w-4 text-theme-danger flex-shrink-0" />
                <span className="text-xs text-theme-danger">
                  {message.metadata.error_message || 'An error occurred'}
                </span>
              </div>
            )}

            {message.metadata.tokens_used && (
              <div className="flex items-center gap-3 mt-2 pt-2 border-t border-theme text-xs text-theme-muted">
                <span>{message.metadata.tokens_used} tokens</span>
                {message.metadata.response_time_ms && (
                  <span>{message.metadata.response_time_ms}ms</span>
                )}
                {message.metadata.cost_estimate && (
                  <span>${message.metadata.cost_estimate.toFixed(4)}</span>
                )}
              </div>
            )}
          </div>

          {isAI && !isProcessing && (
            <div className="flex items-center gap-1 mt-2 opacity-0 group-hover:opacity-100 transition-opacity duration-200">
              <div className="flex items-center bg-theme-surface/80 backdrop-blur-sm rounded-full border border-theme/20 p-1 shadow-sm">
                <Button
                  variant="ghost"
                  size="xs"
                  onClick={() => handleCopyMessage(message)}
                  className="h-7 w-7 p-0 hover:bg-theme-surface-hover rounded-full transition-all duration-200"
                  title="Copy message"
                >
                  <Copy className="h-3.5 w-3.5" />
                </Button>

                <Button
                  variant="ghost"
                  size="xs"
                  onClick={() => handleRateMessage(message.id, 'thumbs_up')}
                  className="h-7 w-7 p-0 hover:bg-theme-success/10 hover:text-theme-success dark:hover:bg-theme-success/20 rounded-full transition-all duration-200"
                  title="Good response"
                >
                  <ThumbsUp className="h-3.5 w-3.5" />
                </Button>

                <Button
                  variant="ghost"
                  size="xs"
                  onClick={() => handleRateMessage(message.id, 'thumbs_down')}
                  className="h-7 w-7 p-0 hover:bg-theme-danger/10 hover:text-theme-danger dark:hover:bg-theme-danger/20 rounded-full transition-all duration-200"
                  title="Poor response"
                >
                  <ThumbsDown className="h-3.5 w-3.5" />
                </Button>

                <DropdownMenu
                  trigger={
                    <Button
                      variant="ghost"
                      size="xs"
                      className="h-7 w-7 p-0 hover:bg-theme-surface-hover rounded-full transition-all duration-200"
                      title="More options"
                    >
                      <MoreVertical className="h-3.5 w-3.5" />
                    </Button>
                  }
                  items={[
                    {
                      icon: RefreshCw,
                      label: 'Regenerate Response',
                      onClick: () => handleRegenerateResponse(message.id)
                    }
                  ]}
                />
              </div>
            </div>
          )}
        </div>
      </div>
    );
  };

  // Set up WebSocket subscription
  useEffect(() => {

    const unsubscribe = subscribeRef.current({
      channel: 'AiConversationChannel',
      params: {
        conversation_id: conversation.id
      },
      onMessage: (data: unknown) => {
        handleChannelMessageRef.current?.(data as ConversationChannelMessage);
      }
    });

    return () => {
      unsubscribe();
      if (typingTimeoutRef.current) {
        clearTimeout(typingTimeoutRef.current);
      }
    };
  }, [conversation.id]);

  // Load initial messages - only when conversation changes
  useEffect(() => {
    loadMessages();
  }, [conversation.id]); // Only depend on conversation.id, not loadMessages

  // Auto-scroll to bottom when messages change
  useEffect(() => {
    if (messages.length > 0) {
      // Use setTimeout to ensure DOM has updated
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
    <div className="h-full flex flex-col bg-theme-background">
      {/* Messages - No header for cleaner interface */}
      <div className="flex-1 overflow-y-auto bg-gradient-to-b from-transparent to-theme-surface/10">
        <div className="p-4 space-y-4">
          {(() => {
            return messages.length === 0 ? (
              <EmptyState
                icon={MessageSquare}
                title="Start a conversation"
                description="Send a message to begin chatting with your AI assistant"
              />
            ) : (
              messages.map((message, index) => {
                return renderMessage(message, index);
              })
            );
          })()}

          {/* Typing indicators */}
          {typingUsers.size > 0 && (
            <div className="flex items-center gap-3 p-3 bg-theme-surface/70 backdrop-blur-md rounded-xl border border-theme/20 shadow-lg">
              <div className="flex gap-1">
                <div className="w-2 h-2 bg-theme-interactive-primary/80 rounded-full animate-bounce" />
                <div className="w-2 h-2 bg-theme-interactive-primary/80 rounded-full animate-bounce delay-100" />
                <div className="w-2 h-2 bg-theme-interactive-primary/80 rounded-full animate-bounce delay-200" />
              </div>
              <span className="text-sm font-medium text-theme-secondary">
                {Array.from(typingUsers).join(', ')} {typingUsers.size === 1 ? 'is' : 'are'} typing...
              </span>
            </div>
          )}

          <div ref={messagesEndRef} />
        </div>
      </div>

      {/* Input Area */}
      <div className="p-4 border-t border-theme/30 bg-theme-surface/40 backdrop-blur-sm">
        <div className="flex gap-2 items-end">
          <div className="flex-1">
            <textarea
              ref={inputRef}
              value={inputValue}
              onChange={handleInputChange}
              onKeyDown={handleKeyDown}
              placeholder="Type your message... (Press Enter to send, Shift+Enter for new line)"
              className="w-full min-h-[40px] max-h-[120px] px-3 py-2 border border-theme/40 rounded-lg resize-none bg-white/90 backdrop-blur-sm text-theme-primary placeholder-theme-muted focus:outline-none focus:ring-2 focus:ring-theme-primary focus:border-theme-primary focus:bg-white disabled:bg-theme-surface disabled:text-theme-muted transition-all duration-200"
              disabled={sending}
            />
          </div>

          <Button
            onClick={handleSendMessage}
            disabled={!inputValue.trim() || sending}
            className="h-[40px] px-3"
          >
            {sending ? (
              <Loader2 className="h-4 w-4 animate-spin" />
            ) : (
              <Send className="h-4 w-4" />
            )}
          </Button>
        </div>

      </div>
    </div>
  );
};