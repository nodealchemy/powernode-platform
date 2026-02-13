import React, { useEffect, useRef } from 'react';
import { Loader2, MessageSquare } from 'lucide-react';
import { ChatMessage } from './ChatMessage';
import type { AiMessage } from '@/shared/types/ai';

interface StreamingInfo {
  messageId: string;
  isStreaming: boolean;
  tokenCount?: number;
  elapsedMs?: number;
  cost?: number;
}

interface ChatMessageListProps {
  messages: AiMessage[];
  loading: boolean;
  streamingInfo?: StreamingInfo | null;
  onRate?: (messageId: string, rating: 'positive' | 'negative') => void;
  onCancelStream?: () => void;
  onEditMessage?: (messageId: string, content: string) => Promise<void>;
  onDeleteMessage?: (messageId: string) => Promise<void>;
  onReplyToMessage?: (messageId: string) => void;
  onViewThread?: (messageId: string) => void;
  onViewEditHistory?: (messageId: string) => void;
  canEditMessages?: boolean;
  canDeleteMessages?: boolean;
}

export const ChatMessageList: React.FC<ChatMessageListProps> = ({
  messages,
  loading,
  streamingInfo,
  onRate,
  onCancelStream,
  onEditMessage,
  onDeleteMessage,
  onReplyToMessage,
  onViewThread,
  onViewEditHistory,
  canEditMessages = false,
  canDeleteMessages = false,
}) => {
  const containerRef = useRef<HTMLDivElement>(null);
  const bottomRef = useRef<HTMLDivElement>(null);

  // Auto-scroll on new messages or streaming content updates
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages.length, streamingInfo?.tokenCount]);

  if (loading) {
    return (
      <div className="flex-1 flex items-center justify-center">
        <Loader2 className="h-6 w-6 text-theme-text-tertiary animate-spin" />
      </div>
    );
  }

  if (messages.length === 0) {
    return (
      <div className="flex-1 flex flex-col items-center justify-center text-center px-4">
        <div className="h-12 w-12 bg-theme-surface-secondary rounded-full flex items-center justify-center mb-3">
          <MessageSquare className="h-6 w-6 text-theme-text-tertiary" />
        </div>
        <p className="text-sm text-theme-secondary">
          No messages yet. Start the conversation!
        </p>
      </div>
    );
  }

  return (
    <div ref={containerRef} className="flex-1 overflow-y-auto py-3">
      {messages.map((msg) => {
        const isStreamingThis = streamingInfo?.messageId === msg.id && streamingInfo?.isStreaming;

        return (
          <ChatMessage
            key={msg.id}
            message={msg}
            streaming={isStreamingThis ? {
              isStreaming: true,
              tokenCount: streamingInfo?.tokenCount,
              elapsedMs: streamingInfo?.elapsedMs,
              cost: streamingInfo?.cost,
            } : undefined}
            onRate={onRate}
            onCancelStream={isStreamingThis ? onCancelStream : undefined}
            onEdit={onEditMessage}
            onDelete={onDeleteMessage}
            onReply={onReplyToMessage}
            onViewThread={onViewThread}
            onViewEditHistory={onViewEditHistory}
            canEdit={canEditMessages}
            canDelete={canDeleteMessages}
          />
        );
      })}
      <div ref={bottomRef} />
    </div>
  );
};
