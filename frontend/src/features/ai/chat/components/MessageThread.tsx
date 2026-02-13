import React, { useState, useRef, useEffect } from 'react';
import { X, Send, Loader2, MessageSquareReply, ArrowLeft, Bot, User } from 'lucide-react';
import ReactMarkdown from 'react-markdown';
import { Avatar } from '@/shared/components/ui/Avatar';
import { Button } from '@/shared/components/ui/Button';
import type { AiMessage } from '@/shared/types/ai';

interface MessageThreadProps {
  parentMessage: AiMessage;
  threadMessages: AiMessage[];
  loading: boolean;
  onSendReply: (content: string) => Promise<void>;
  onClose: () => void;
}

function formatTime(dateStr: string): string {
  const date = new Date(dateStr);
  return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

export const MessageThread: React.FC<MessageThreadProps> = ({
  parentMessage,
  threadMessages,
  loading,
  onSendReply,
  onClose,
}) => {
  const [replyContent, setReplyContent] = useState('');
  const [sending, setSending] = useState(false);
  const messagesEndRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [threadMessages.length]);

  const handleSendReply = async () => {
    if (!replyContent.trim() || sending) return;
    const content = replyContent.trim();
    setReplyContent('');
    setSending(true);
    try {
      await onSendReply(content);
    } finally {
      setSending(false);
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleSendReply();
    }
  };

  const renderThreadMessage = (msg: AiMessage) => {
    const isUser = msg.sender_type === 'user';

    return (
      <div key={msg.id} className="flex gap-2.5 px-3 py-2">
        <Avatar size="sm" fallback={isUser ? 'U' : 'AI'} className="flex-shrink-0 mt-0.5">
          {isUser ? <User className="h-3.5 w-3.5" /> : <Bot className="h-3.5 w-3.5" />}
        </Avatar>

        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-0.5">
            <span className="text-xs font-semibold text-theme-primary">
              {msg.sender_info?.name || (isUser ? 'You' : 'AI Assistant')}
            </span>
            <span className="text-[10px] text-theme-text-tertiary">
              {formatTime(msg.created_at)}
            </span>
            {msg.is_edited && (
              <span className="text-[10px] text-theme-text-tertiary italic">(edited)</span>
            )}
          </div>

          <div className="text-sm text-theme-primary">
            {msg.sender_type === 'ai' ? (
              <div className="prose prose-sm max-w-none prose-p:my-1 prose-headings:my-2">
                <ReactMarkdown>{msg.content}</ReactMarkdown>
              </div>
            ) : (
              <p className="whitespace-pre-wrap">{msg.content}</p>
            )}
          </div>
        </div>
      </div>
    );
  };

  return (
    <div className="flex flex-col h-full border-l border-theme bg-theme-surface">
      {/* Header */}
      <div className="flex items-center justify-between px-3 py-2.5 border-b border-theme">
        <div className="flex items-center gap-2">
          <button
            onClick={onClose}
            className="p-1 rounded hover:bg-theme-surface-hover text-theme-text-tertiary"
          >
            <ArrowLeft className="h-4 w-4" />
          </button>
          <MessageSquareReply className="h-4 w-4 text-theme-interactive-primary" />
          <span className="text-sm font-semibold text-theme-primary">Thread</span>
          <span className="text-xs text-theme-text-tertiary">
            {threadMessages.length} {threadMessages.length === 1 ? 'reply' : 'replies'}
          </span>
        </div>
        <button
          onClick={onClose}
          className="p-1 rounded hover:bg-theme-surface-hover text-theme-text-tertiary"
        >
          <X className="h-4 w-4" />
        </button>
      </div>

      {/* Parent message */}
      <div className="px-3 py-2.5 border-b border-theme bg-theme-surface-secondary/50">
        <div className="flex items-center gap-2 mb-1">
          <span className="text-xs font-semibold text-theme-primary">
            {parentMessage.sender_info?.name || (parentMessage.sender_type === 'user' ? 'You' : 'AI Assistant')}
          </span>
          <span className="text-[10px] text-theme-text-tertiary">
            {formatTime(parentMessage.created_at)}
          </span>
        </div>
        <p className="text-sm text-theme-secondary line-clamp-3">
          {parentMessage.content}
        </p>
      </div>

      {/* Thread messages */}
      <div className="flex-1 overflow-y-auto">
        {loading ? (
          <div className="flex items-center justify-center py-8">
            <Loader2 className="h-5 w-5 text-theme-text-tertiary animate-spin" />
          </div>
        ) : threadMessages.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-8 text-center px-4">
            <MessageSquareReply className="h-8 w-8 text-theme-text-tertiary mb-2" />
            <p className="text-sm text-theme-secondary">No replies yet</p>
            <p className="text-xs text-theme-text-tertiary mt-1">Start a conversation in this thread</p>
          </div>
        ) : (
          <div className="divide-y divide-theme/30">
            {threadMessages.map(renderThreadMessage)}
          </div>
        )}
        <div ref={messagesEndRef} />
      </div>

      {/* Reply input */}
      <div className="p-3 border-t border-theme">
        <div className="flex gap-2 items-end">
          <textarea
            value={replyContent}
            onChange={(e) => setReplyContent(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder="Reply in thread..."
            className="flex-1 min-h-[36px] max-h-[100px] px-3 py-1.5 border border-theme rounded-md resize-none bg-theme-background text-sm text-theme-primary placeholder-theme-muted focus:outline-none focus:ring-1 focus:ring-theme-interactive-primary"
            disabled={sending}
          />
          <Button
            variant="primary"
            size="xs"
            onClick={handleSendReply}
            disabled={!replyContent.trim() || sending}
            className="h-[36px] w-[36px] p-0 flex items-center justify-center"
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
