import React from 'react';
import { Bot, User } from 'lucide-react';
import type { AiConversation, AiMessage } from '@/shared/types/ai';

interface MessageThreadProps {
  messages: AiMessage[];
  conversation: AiConversation;
}

const formatDate = (dateStr: string | undefined | null, format: 'date' | 'time' | 'full' = 'full') => {
  if (!dateStr) return 'N/A';
  const date = new Date(dateStr);
  if (isNaN(date.getTime())) return 'N/A';
  switch (format) {
    case 'date': return date.toLocaleDateString();
    case 'time': return date.toLocaleTimeString();
    default: return date.toLocaleString();
  }
};

const formatCurrency = (amount: number) =>
  new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', minimumFractionDigits: 4 }).format(amount);

export const MessageThread: React.FC<MessageThreadProps> = ({ messages, conversation }) => {
  if (!messages || messages.length === 0) {
    return <p className="text-theme-muted">No messages found in this conversation.</p>;
  }

  return (
    <div className="space-y-4">
      {messages.map((message) => (
        <div
          key={message.id}
          className={`p-3 rounded-lg border ${
            message.sender_type === 'user'
              ? 'bg-theme-primary-subtle border-theme-primary/20'
              : 'bg-theme-surface border-theme/20'
          }`}
        >
          <div className="flex items-center gap-2 mb-2">
            <div className="flex-shrink-0 flex items-center justify-center w-5 h-5">
              {message.sender_type === 'user' ? (
                <User className="h-4 w-4 text-theme-primary" />
              ) : (
                <Bot className="h-4 w-4 text-theme-muted" />
              )}
            </div>
            <span className="text-sm font-medium text-theme-primary">
              {message.sender_type === 'user'
                ? message.sender_info?.name || 'User'
                : conversation.ai_agent?.name || 'AI Assistant'}
            </span>
            <span className="text-xs text-theme-muted">
              {formatDate(message.created_at, 'time')}
            </span>
          </div>
          <p className="text-theme-primary text-sm">{message.content}</p>
          {message.metadata?.tokens_used && (
            <div className="mt-2 text-xs text-theme-muted">
              Tokens: {message.metadata.tokens_used}
              {message.metadata?.cost_estimate && (
                <> &bull; Cost: {formatCurrency(message.metadata.cost_estimate)}</>
              )}
            </div>
          )}
        </div>
      ))}
    </div>
  );
};
