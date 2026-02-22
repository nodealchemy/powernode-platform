import React from 'react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import remarkBreaks from 'remark-breaks';
import {
  Bot,
  User,
  Copy,
  ThumbsUp,
  ThumbsDown,
  RefreshCw,
  AlertCircle,
  Loader2,
  MessageSquare,
  MoreVertical,
  MessageSquareReply,
  Pencil,
  Trash2,
} from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Avatar } from '@/shared/components/ui/Avatar';
import { DropdownMenu } from '@/shared/components/ui/DropdownMenu';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { ChatStreamingRenderer } from '@/features/ai/chat/components/ChatStreamingRenderer';
import { MessageEditor } from '@/features/ai/chat/components/MessageEditor';
import { PlanApprovalActions } from '@/features/ai/chat/components/PlanApprovalActions';
import { ConciergeActionCard } from '@/features/ai/chat/components/ConciergeActionCard';
import type { AiMessage } from '@/shared/types/ai';
import { cleanMessageContent, formatTimestamp } from './utils';

interface MessageListProps {
  messages: AiMessage[];
  currentUser: { id?: string; name?: string } | null;
  editingMessageId: string | null;
  editSaving: boolean;
  typingUsers: Set<string>;
  messagesEndRef: React.RefObject<HTMLDivElement>;
  onCopy: (message: AiMessage) => void;
  onRate: (messageId: string, rating: 'thumbs_up' | 'thumbs_down') => void;
  onRegenerate: (messageId: string) => void;
  onEdit: (messageId: string, content: string) => void;
  onSetEditing: (id: string | null) => void;
  onDelete: (message: AiMessage) => void;
  onOpenThread: (message: AiMessage) => void;
  onPlanAction?: (actionType: string, executionId: string, feedback?: string) => Promise<void>;
  conversationId?: string;
  isConcierge?: boolean;
  onConciergeConfirm?: () => void;
  onSuggestedMessage?: (text: string) => void;
}

export const MessageList: React.FC<MessageListProps> = ({
  messages,
  currentUser,
  editingMessageId,
  editSaving,
  typingUsers,
  messagesEndRef,
  onCopy,
  onRate,
  onRegenerate,
  onEdit,
  onSetEditing,
  onDelete,
  onOpenThread,
  onPlanAction,
  conversationId,
  isConcierge,
  onConciergeConfirm,
  onSuggestedMessage
}) => {
  const renderMessage = (message: AiMessage) => {
    const isUser = message.sender_type === 'user';
    const isAI = message.sender_type === 'ai';
    const isSystem = message.sender_type === 'system';
    const isProcessing = message.metadata?.processing;
    const hasError = message.metadata?.error;
    const isDeleted = !!message.deleted_at;
    const isEditing = editingMessageId === message.id;
    const canEdit = isUser && currentUser?.id === message.user_id;
    const canDelete = isUser && currentUser?.id === message.user_id;

    if (isSystem) {
      const isResolved = message.metadata?.resolved;
      return (
        <div key={message.id} className="flex justify-center my-4">
          <div className={`bg-theme-surface border border-theme px-3 py-1 rounded-full text-sm shadow-sm ${isResolved ? 'text-theme-muted/50 line-through' : 'text-theme-muted'}`}>
            {cleanMessageContent(message.content)}
          </div>
        </div>
      );
    }

    // Soft-deleted message
    if (isDeleted) {
      return (
        <div key={message.id} className="group flex gap-3 flex-row opacity-50">
          <div className="flex-shrink-0 flex items-start justify-center">
            <Avatar className="h-8 w-8 flex items-center justify-center bg-theme-surface border border-theme text-theme-muted" aria-hidden="true">
              <div className="flex items-center justify-center w-full h-full">
                <Trash2 className="h-4 w-4" aria-hidden="true" />
              </div>
            </Avatar>
          </div>
          <div className="flex-1 max-w-[85%] sm:max-w-[80%] flex flex-col items-start">
            <div className="flex items-center gap-2 mb-2">
              <span className="text-sm text-theme-muted italic">This message was deleted</span>
              <span className="text-xs text-theme-secondary">{formatTimestamp(message.created_at)}</span>
            </div>
            {canDelete && (
              <button
                onClick={() => onDelete(message)}
                className="text-xs text-theme-interactive-primary hover:underline"
              >
                Restore message
              </button>
            )}
          </div>
        </div>
      );
    }

    return (
      <div
        key={message.id}
        className="group flex gap-3 flex-row"
      >
        <div className="flex-shrink-0 flex items-start justify-center">
          <Avatar
            className={`h-8 w-8 flex items-center justify-center ${
              isUser
                ? 'bg-theme-primary text-white'
                : 'bg-theme-surface border border-theme text-theme-primary'
            }`}
            aria-hidden="true"
          >
            <div className="flex items-center justify-center w-full h-full">
              {isUser ? (
                <User className="h-4 w-4" aria-hidden="true" />
              ) : (
                <Bot className="h-4 w-4" aria-hidden="true" />
              )}
            </div>
          </Avatar>
        </div>

        <div className="flex-1 max-w-[85%] sm:max-w-[80%] flex flex-col items-start">
          <div className="flex items-center gap-2 mb-2 flex-row">
            <span className="text-sm font-semibold text-theme-primary">
              {message.sender_info?.name || (isUser ? 'You' : 'AI Assistant')}
            </span>
            <span className="text-xs text-theme-secondary">
              {formatTimestamp(message.created_at)}
            </span>
            {message.is_edited && (
              <span className="text-[10px] text-theme-text-tertiary italic">(edited)</span>
            )}
          </div>

          {isEditing ? (
            <div className="w-full">
              <MessageEditor
                initialContent={message.content}
                onSave={(content) => onEdit(message.id, content)}
                onCancel={() => onSetEditing(null)}
                saving={editSaving}
              />
            </div>
          ) : (
            <div
              className={`rounded-2xl px-4 py-3 max-w-full shadow-md ${
                isUser
                  ? 'bg-theme-info text-white rounded-bl-md'
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
              ) : message.metadata?.streaming ? (
                <ChatStreamingRenderer
                  content={cleanMessageContent(message.content)}
                  isStreaming={true}
                  tokenCount={message.metadata?.tokens_used}
                />
              ) : (
                <div className="text-sm break-words">
                  {message.sender_type === 'ai' ? (
                    <div className="markdown-content">
                      <ReactMarkdown
                        remarkPlugins={[remarkGfm, remarkBreaks]}
                        components={{
                          h1: ({ children }) => <h1 className="text-2xl font-bold mb-4 mt-6">{children}</h1>,
                          h2: ({ children }) => <h2 className="text-xl font-bold mb-3 mt-5">{children}</h2>,
                          h3: ({ children }) => <h3 className="text-lg font-bold mb-2 mt-4">{children}</h3>,
                          h4: ({ children }) => <h4 className="text-base font-bold mb-2 mt-3">{children}</h4>,
                          p: ({ children }) => <p className="mb-4">{children}</p>,
                          ul: ({ children }) => <ul className="list-disc list-inside mb-4 ml-4">{children}</ul>,
                          ol: ({ children }) => <ol className="list-decimal list-inside mb-4 ml-4">{children}</ol>,
                          li: ({ children }) => <li className="mb-1">{children}</li>,
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
                          blockquote: ({ children }) => (
                            <blockquote className="border-l-4 border-theme dark:border-theme pl-4 italic mb-4">
                              {children}
                            </blockquote>
                          ),
                          hr: () => <hr className="border-t border-theme dark:border-theme my-4" />,
                          table: ({ children }) => (
                            <div className="overflow-x-auto mb-4">
                              <table className="min-w-full divide-y divide-theme">
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
                    {message.metadata?.error_message || 'An error occurred'}
                  </span>
                </div>
              )}

              {message.metadata?.tokens_used != null && message.metadata.tokens_used > 0 && (
                <div className="flex items-center gap-3 mt-2 pt-2 border-t border-theme text-xs text-theme-muted">
                  <span>{message.metadata.tokens_used} tokens</span>
                  {message.metadata?.response_time_ms != null && message.metadata.response_time_ms > 0 && (
                    <span>{message.metadata.response_time_ms}ms</span>
                  )}
                  {message.metadata?.cost_estimate != null && message.metadata.cost_estimate > 0 && (
                    <span>${message.metadata.cost_estimate.toFixed(4)}</span>
                  )}
                </div>
              )}
            </div>
          )}

          {/* Plan approval actions */}
          {isAI && message.metadata?.actions && message.metadata?.action_context && !message.metadata?.concierge_action && onPlanAction && (
            <PlanApprovalActions
              actions={message.metadata.actions}
              actionContext={message.metadata.action_context}
              onAction={onPlanAction}
            />
          )}

          {/* Concierge action card */}
          {isAI && message.metadata?.concierge_action && conversationId && (
            <ConciergeActionCard
              conversationId={conversationId}
              actions={message.metadata.actions || [
                { type: 'confirm', label: 'Confirm', style: 'primary' },
                { type: 'modify', label: 'Modify', style: 'secondary' },
              ]}
              actionContext={{
                type: 'concierge',
                action_type: (message.metadata.action_context as unknown as Record<string, string>)?.action_type || (message.metadata as Record<string, string>).action_type || '',
                status: message.metadata.action_context?.status || 'pending',
                resolved_at: message.metadata.action_context?.resolved_at,
              }}
              actionParams={(message.metadata.action_params || {}) as Record<string, unknown>}
              onConfirmed={onConciergeConfirm}
            />
          )}

          {/* Message action bar */}
          {!isProcessing && !isEditing && (
            <div className="flex items-center gap-1 mt-2" role="group" aria-label="Message actions">
              <div className="flex items-center bg-theme-surface/80 backdrop-blur-sm rounded-full border border-theme/20 p-1 shadow-sm">
                <Button
                  variant="ghost"
                  size="xs"
                  onClick={() => onCopy(message)}
                  className="h-7 w-7 p-0 hover:bg-theme-surface-hover rounded-full transition-all duration-200"
                  title="Copy message"
                  aria-label="Copy message to clipboard"
                >
                  <Copy className="h-3.5 w-3.5" aria-hidden="true" />
                </Button>

                <Button
                  variant="ghost"
                  size="xs"
                  onClick={() => onOpenThread(message)}
                  className="h-7 w-7 p-0 hover:bg-theme-surface-hover rounded-full transition-all duration-200"
                  title="Reply in thread"
                  aria-label="Reply in thread"
                >
                  <MessageSquareReply className="h-3.5 w-3.5" aria-hidden="true" />
                </Button>

                {isAI && (
                  <>
                    <Button
                      variant="ghost"
                      size="xs"
                      onClick={() => onRate(message.id, 'thumbs_up')}
                      className="h-7 w-7 p-0 hover:bg-theme-success/10 hover:text-theme-success dark:hover:bg-theme-success/20 rounded-full transition-all duration-200"
                      title="Good response"
                      aria-label="Rate this response as helpful"
                    >
                      <ThumbsUp className="h-3.5 w-3.5" aria-hidden="true" />
                    </Button>

                    <Button
                      variant="ghost"
                      size="xs"
                      onClick={() => onRate(message.id, 'thumbs_down')}
                      className="h-7 w-7 p-0 hover:bg-theme-danger/10 hover:text-theme-danger dark:hover:bg-theme-danger/20 rounded-full transition-all duration-200"
                      title="Poor response"
                      aria-label="Rate this response as not helpful"
                    >
                      <ThumbsDown className="h-3.5 w-3.5" aria-hidden="true" />
                    </Button>
                  </>
                )}

                <DropdownMenu
                  trigger={
                    <Button
                      variant="ghost"
                      size="xs"
                      className="h-7 w-7 p-0 hover:bg-theme-surface-hover rounded-full transition-all duration-200"
                      title="More options"
                      aria-label="More message options"
                    >
                      <MoreVertical className="h-3.5 w-3.5" aria-hidden="true" />
                    </Button>
                  }
                  items={[
                    ...(isAI ? [{
                      icon: RefreshCw,
                      label: 'Regenerate Response',
                      onClick: () => onRegenerate(message.id)
                    }] : []),
                    ...(canEdit ? [{
                      icon: Pencil,
                      label: 'Edit Message',
                      onClick: () => onSetEditing(message.id)
                    }] : []),
                    ...(canDelete ? [{
                      icon: Trash2,
                      label: 'Delete Message',
                      onClick: () => onDelete(message),
                      danger: true
                    }] : []),
                  ]}
                />
              </div>
            </div>
          )}

          {/* Thread indicator */}
          {(message.reply_count ?? 0) > 0 && (
            <button
              onClick={() => onOpenThread(message)}
              className="flex items-center gap-1.5 mt-1.5 text-xs text-theme-interactive-primary hover:underline"
            >
              <MessageSquareReply className="h-3 w-3" />
              {message.reply_count} {message.reply_count === 1 ? 'reply' : 'replies'}
            </button>
          )}
        </div>
      </div>
    );
  };

  return (
    <div className="flex-1 overflow-y-auto bg-gradient-to-b from-transparent to-theme-surface/10">
      <div className="p-4 space-y-4">
        {messages.length === 0 && isConcierge ? (
          <div className="flex flex-col items-center justify-center h-full py-12 px-4">
            <div className="w-14 h-14 rounded-2xl bg-theme-interactive-primary/10 flex items-center justify-center mb-4">
              <Bot className="h-7 w-7 text-theme-interactive-primary" />
            </div>
            <h3 className="text-lg font-semibold text-theme-primary mb-1">Hi, how can I help?</h3>
            <p className="text-sm text-theme-secondary mb-6 text-center max-w-sm">
              I can help you manage missions, analyze repositories, coordinate teams, and more.
            </p>
            {onSuggestedMessage && (
              <div className="flex flex-wrap gap-2 justify-center max-w-md">
                {[
                  'Check mission status',
                  'Create a new mission',
                  'Analyze a repository',
                  'Ask a question',
                ].map((suggestion) => (
                  <button
                    key={suggestion}
                    onClick={() => onSuggestedMessage(suggestion)}
                    className="px-3 py-1.5 text-sm rounded-full border border-theme bg-theme-surface hover:bg-theme-surface-hover text-theme-primary transition-colors"
                  >
                    {suggestion}
                  </button>
                ))}
              </div>
            )}
          </div>
        ) : messages.length === 0 ? (
          <EmptyState
            icon={MessageSquare}
            title="Start a conversation"
            description="Send a message to begin chatting with your AI assistant"
          />
        ) : (
          messages.map((message) => renderMessage(message))
        )}

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
  );
};
