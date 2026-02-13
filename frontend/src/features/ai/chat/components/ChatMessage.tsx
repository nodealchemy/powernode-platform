import React, { useState } from 'react';
import ReactMarkdown from 'react-markdown';
import { Bot, User, StopCircle, MessageSquareReply } from 'lucide-react';
import { Avatar } from '@/shared/components/ui/Avatar';
import { ChatStreamingRenderer } from './ChatStreamingRenderer';
import { MessageActions } from './MessageActions';
import { MessageEditor } from './MessageEditor';
import { AttachmentPreview } from './AttachmentPreview';
import type { AiMessage } from '@/shared/types/ai';

interface StreamingInfo {
  isStreaming: boolean;
  tokenCount?: number;
  elapsedMs?: number;
  cost?: number;
}

interface ChatMessageProps {
  message: AiMessage;
  streaming?: StreamingInfo;
  onRate?: (messageId: string, rating: 'positive' | 'negative') => void;
  onCancelStream?: () => void;
  onEdit?: (messageId: string, content: string) => Promise<void>;
  onDelete?: (messageId: string) => Promise<void>;
  onReply?: (messageId: string) => void;
  onViewThread?: (messageId: string) => void;
  onViewEditHistory?: (messageId: string) => void;
  canEdit?: boolean;
  canDelete?: boolean;
}

function formatTime(dateStr: string): string {
  const date = new Date(dateStr);
  return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

export const ChatMessage: React.FC<ChatMessageProps> = ({
  message,
  streaming,
  onRate,
  onCancelStream,
  onEdit,
  onDelete,
  onReply,
  onViewThread,
  onViewEditHistory,
  canEdit = false,
  canDelete = false,
}) => {
  const [isHovered, setIsHovered] = useState(false);
  const [isEditing, setIsEditing] = useState(false);
  const [editSaving, setEditSaving] = useState(false);

  const isUser = message.sender_type === 'user';
  const isAi = message.sender_type === 'ai';
  const isSystem = message.sender_type === 'system';
  const isActivelyStreaming = streaming?.isStreaming || false;
  const isDeleted = !!message.deleted_at;
  const hasThread = (message.reply_count ?? 0) > 0;

  const handleEditSave = async (content: string) => {
    if (!onEdit) return;
    setEditSaving(true);
    try {
      await onEdit(message.id, content);
      setIsEditing(false);
    } finally {
      setEditSaving(false);
    }
  };

  if (isSystem) {
    return (
      <div className="flex justify-center py-2">
        <span className="text-xs text-theme-text-tertiary bg-theme-surface-secondary px-3 py-1 rounded-full">
          {message.content}
        </span>
      </div>
    );
  }

  if (isDeleted) {
    return (
      <div className={`flex gap-2.5 px-4 py-2 ${isUser ? 'flex-row-reverse' : ''}`}>
        <Avatar size="sm" fallback={isUser ? 'U' : 'AI'} className="flex-shrink-0 mt-0.5 opacity-50">
          {isUser ? <User className="h-4 w-4" /> : <Bot className="h-4 w-4" />}
        </Avatar>
        <div className={`flex flex-col max-w-[75%] ${isUser ? 'items-end' : 'items-start'}`}>
          <div className="rounded-lg px-3 py-2 bg-theme-surface-secondary border border-theme border-dashed">
            <p className="text-sm text-theme-text-tertiary italic">This message was deleted</p>
          </div>
          <div className="flex items-center gap-2 mt-1 px-1">
            <span className="text-[10px] text-theme-text-tertiary">
              {formatTime(message.created_at)}
            </span>
            {canDelete && onDelete && (
              <MessageActions
                message={message}
                canEdit={false}
                canDelete={canDelete}
                onEdit={() => {}}
                onDelete={() => onDelete(message.id)}
                onReply={() => {}}
              />
            )}
          </div>
        </div>
      </div>
    );
  }

  return (
    <div
      className={`flex gap-2.5 px-4 py-2 ${isUser ? 'flex-row-reverse' : ''}`}
      onMouseEnter={() => setIsHovered(true)}
      onMouseLeave={() => setIsHovered(false)}
    >
      <Avatar size="sm" fallback={isUser ? 'U' : 'AI'} className="flex-shrink-0 mt-0.5">
        {isUser ? <User className="h-4 w-4" /> : <Bot className="h-4 w-4" />}
      </Avatar>

      <div className={`flex flex-col max-w-[75%] ${isUser ? 'items-end' : 'items-start'}`}>
        <div
          className={`rounded-lg px-3 py-2 ${
            isUser
              ? 'bg-theme-interactive-primary text-white'
              : 'bg-theme-surface border border-theme'
          }`}
        >
          {isEditing ? (
            <MessageEditor
              initialContent={message.content}
              onSave={handleEditSave}
              onCancel={() => setIsEditing(false)}
              saving={editSaving}
            />
          ) : isUser ? (
            <p className="text-sm whitespace-pre-wrap">{message.content}</p>
          ) : isActivelyStreaming ? (
            <ChatStreamingRenderer
              content={message.content}
              isStreaming={true}
              tokenCount={streaming?.tokenCount}
              elapsedMs={streaming?.elapsedMs}
              cost={streaming?.cost}
            />
          ) : (
            <div className="text-sm text-theme-primary prose prose-sm max-w-none prose-p:my-1 prose-headings:my-2">
              <ReactMarkdown>{message.content}</ReactMarkdown>
            </div>
          )}

          {/* Attachments */}
          {message.attachments && message.attachments.length > 0 && (
            <div className="mt-1.5">
              <AttachmentPreview
                attachments={message.attachments.map(a => ({
                  name: a.name,
                  type: a.type,
                  size: a.size,
                  url: a.url,
                  preview_url: a.preview_url,
                }))}
                compact={isUser}
              />
            </div>
          )}
        </div>

        {/* Meta info */}
        <div className="flex items-center gap-2 mt-1 px-1">
          <span className="text-[10px] text-theme-text-tertiary">
            {formatTime(message.created_at)}
          </span>

          {message.is_edited && (
            <span className="text-[10px] text-theme-text-tertiary italic">(edited)</span>
          )}

          {!isActivelyStreaming && message.metadata?.tokens_used && (
            <span className="text-[10px] text-theme-text-tertiary">
              {message.metadata.tokens_used} tokens
            </span>
          )}

          {!isActivelyStreaming && message.metadata?.cost_estimate && (
            <span className="text-[10px] text-theme-text-tertiary">
              ${Number(message.metadata.cost_estimate).toFixed(4)}
            </span>
          )}

          {/* Cancel button during streaming */}
          {isActivelyStreaming && onCancelStream && (
            <button
              onClick={onCancelStream}
              className="flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] text-theme-error hover:bg-theme-error-background transition-colors"
              title="Cancel response"
            >
              <StopCircle className="h-3 w-3" />
              Cancel
            </button>
          )}

          {/* Thread indicator */}
          {hasThread && (
            <button
              onClick={() => onViewThread?.(message.id)}
              className="flex items-center gap-0.5 px-1 py-0.5 rounded text-[10px] text-theme-interactive-primary hover:bg-theme-surface-hover transition-colors"
            >
              <MessageSquareReply className="h-3 w-3" />
              {message.reply_count} {message.reply_count === 1 ? 'reply' : 'replies'}
            </button>
          )}

          {/* Thumbs up/down for AI messages */}
          {isHovered && !isActivelyStreaming && !isEditing && isAi && onRate && (
            <div className="flex items-center gap-0.5">
              <button
                onClick={() => onRate(message.id, 'positive')}
                className={`p-0.5 rounded hover:bg-theme-surface-hover ${
                  message.metadata?.user_rating?.rating === 'positive'
                    ? 'text-theme-success'
                    : 'text-theme-text-tertiary'
                }`}
                title="Good response"
              >
                <svg className="h-3 w-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M7 10v12"/><path d="M15 5.88 14 10h5.83a2 2 0 0 1 1.92 2.56l-2.33 8A2 2 0 0 1 17.5 22H4a2 2 0 0 1-2-2v-8a2 2 0 0 1 2-2h2.76a2 2 0 0 0 1.79-1.11L12 2h0a3.13 3.13 0 0 1 3 3.88Z"/></svg>
              </button>
              <button
                onClick={() => onRate(message.id, 'negative')}
                className={`p-0.5 rounded hover:bg-theme-surface-hover ${
                  message.metadata?.user_rating?.rating === 'negative'
                    ? 'text-theme-danger'
                    : 'text-theme-text-tertiary'
                }`}
                title="Poor response"
              >
                <svg className="h-3 w-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M17 14V2"/><path d="M9 18.12 10 14H4.17a2 2 0 0 1-1.92-2.56l2.33-8A2 2 0 0 1 6.5 2H20a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-2.76a2 2 0 0 0-1.79 1.11L12 22h0a3.13 3.13 0 0 1-3-3.88Z"/></svg>
              </button>
            </div>
          )}

          {/* Message actions menu */}
          {isHovered && !isActivelyStreaming && !isEditing && (
            <MessageActions
              message={message}
              canEdit={canEdit && isUser}
              canDelete={canDelete}
              onEdit={() => setIsEditing(true)}
              onDelete={() => onDelete?.(message.id)}
              onReply={() => onReply?.(message.id)}
              onViewThread={hasThread ? () => onViewThread?.(message.id) : undefined}
              onViewEditHistory={message.is_edited ? () => onViewEditHistory?.(message.id) : undefined}
            />
          )}
        </div>
      </div>
    </div>
  );
};
