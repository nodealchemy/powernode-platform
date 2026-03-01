import React, { useState, useRef, useEffect, useCallback } from 'react';
import { Send, Hash, AlertCircle, Clock } from 'lucide-react';
import { useChannelMessages } from '../hooks/useChannelMessages';
import type { TeamChannelMessage } from '@/shared/services/ai/TeamsApiService';
import { useNotifications } from '@/shared/hooks/useNotifications';

interface ChannelConversationComponentProps {
  teamId: string;
  channelId: string;
  channelName?: string;
}

const MESSAGE_TYPE_COLORS: Record<string, string> = {
  task_assignment: 'bg-theme-info/10 text-theme-info',
  task_update: 'bg-theme-info/10 text-theme-info',
  task_result: 'bg-theme-success/10 text-theme-success',
  work_plan: 'bg-theme-interactive-primary/10 text-theme-interactive-primary',
  synthesis: 'bg-theme-interactive-primary/10 text-theme-interactive-primary',
  question: 'bg-theme-warning/10 text-theme-warning',
  answer: 'bg-theme-success/10 text-theme-success',
  escalation: 'bg-theme-error/10 text-theme-error',
  coordination: 'bg-theme-text-tertiary/10 text-theme-secondary',
  broadcast: 'bg-theme-text-tertiary/10 text-theme-secondary',
  human_input: 'bg-theme-interactive-primary/10 text-theme-interactive-primary',
};

const PRIORITY_INDICATORS: Record<string, string> = {
  urgent: 'text-theme-error',
  high: 'text-theme-warning',
};

function formatTime(dateStr: string): string {
  const date = new Date(dateStr);
  return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

const ChannelMessage: React.FC<{ message: TeamChannelMessage }> = ({ message }) => {
  const isHuman = message.message_type === 'human_input';
  const senderName = isHuman
    ? message.user?.name || 'User'
    : message.from_role?.role_name || 'System';
  const senderDetail = isHuman
    ? null
    : message.from_role?.agent_name;
  const typeColor = MESSAGE_TYPE_COLORS[message.message_type] || MESSAGE_TYPE_COLORS.coordination;
  const priorityColor = PRIORITY_INDICATORS[message.priority];

  return (
    <div className={`flex gap-2.5 px-4 py-2 hover:bg-theme-surface-hover/50 transition-colors ${isHuman ? 'bg-theme-interactive-primary/5' : ''}`}>
      {/* Sender avatar placeholder */}
      <div className={`flex-shrink-0 h-7 w-7 rounded-full flex items-center justify-center text-[10px] font-bold ${
        isHuman ? 'bg-theme-interactive-primary/20 text-theme-interactive-primary' : 'bg-theme-surface-secondary text-theme-secondary'
      }`}>
        {senderName.charAt(0).toUpperCase()}
      </div>

      <div className="flex-1 min-w-0">
        {/* Header: sender, type badge, priority, time */}
        <div className="flex items-center gap-1.5 flex-wrap">
          <span className="text-sm font-semibold text-theme-primary">
            {senderName}
          </span>
          {senderDetail && (
            <span className="text-xs text-theme-text-tertiary">
              ({senderDetail})
            </span>
          )}
          <span className={`text-[9px] font-semibold uppercase px-1 py-0.5 rounded ${typeColor}`}>
            {message.message_type.replace(/_/g, ' ')}
          </span>
          {priorityColor && (
            <AlertCircle className={`h-3 w-3 ${priorityColor}`} />
          )}
          {message.requires_response && !message.responded_at && (
            <span className="flex items-center gap-0.5 text-[9px] font-medium text-theme-warning bg-theme-warning/10 px-1 py-0.5 rounded">
              <Clock className="h-2.5 w-2.5" />
              Awaiting response
            </span>
          )}
          <span className="text-[10px] text-theme-text-tertiary ml-auto flex-shrink-0">
            {formatTime(message.created_at)}
          </span>
        </div>

        {/* Target role */}
        {message.to_role && (
          <div className="text-[10px] text-theme-text-tertiary mt-0.5">
            → {message.to_role.role_name}
            {message.to_role.agent_name && ` (${message.to_role.agent_name})`}
          </div>
        )}

        {/* Content */}
        <div className="text-sm text-theme-primary mt-1 whitespace-pre-wrap break-words">
          {message.content}
        </div>
      </div>
    </div>
  );
};

export const ChannelConversationComponent: React.FC<ChannelConversationComponentProps> = ({
  teamId,
  channelId,
  channelName,
}) => {
  const { messages, loading, sending, sendMessage } = useChannelMessages({ teamId, channelId });
  const { addNotification } = useNotifications();
  const [input, setInput] = useState('');
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLTextAreaElement>(null);

  // Auto-scroll to bottom on new messages
  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages.length]);

  const handleSend = useCallback(async () => {
    const content = input.trim();
    if (!content || sending) return;
    setInput('');
    try {
      await sendMessage(content);
    } catch {
      addNotification({ type: 'error', title: 'Send Failed', message: 'Could not send message. Please try again.' });
    }
    inputRef.current?.focus();
  }, [input, sending, sendMessage, addNotification]);

  const handleKeyDown = useCallback((e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleSend();
    }
  }, [handleSend]);

  return (
    <div className="flex flex-col h-full">
      {/* Channel header */}
      <div className="flex items-center gap-2 px-4 py-2.5 border-b border-theme bg-theme-surface">
        <Hash className="h-4 w-4 text-theme-text-tertiary" />
        <span className="text-sm font-semibold text-theme-primary">
          {channelName || 'Channel'}
        </span>
      </div>

      {/* Messages area */}
      <div className="flex-1 overflow-y-auto">
        {loading ? (
          <div className="flex items-center justify-center h-full">
            <div className="h-5 w-5 border-2 border-theme-interactive-primary border-t-transparent rounded-full animate-spin" />
          </div>
        ) : messages.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-full text-theme-text-tertiary">
            <Hash className="h-8 w-8 mb-2 opacity-40" />
            <p className="text-sm">No messages yet</p>
            <p className="text-xs mt-1">Send a message to get started</p>
          </div>
        ) : (
          <div className="py-2">
            {messages.map((msg) => (
              <ChannelMessage key={msg.id} message={msg} />
            ))}
            <div ref={messagesEndRef} />
          </div>
        )}
      </div>

      {/* Composer */}
      <div className="border-t border-theme bg-theme-surface p-3">
        <div className="flex items-end gap-2">
          <textarea
            ref={inputRef}
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder="Send a message..."
            rows={1}
            className="flex-1 px-3 py-2 text-sm bg-theme-background border border-theme rounded-lg text-theme-primary placeholder:text-theme-text-tertiary focus:outline-none focus:ring-1 focus:ring-theme-interactive-primary resize-none"
            style={{ maxHeight: '120px' }}
          />
          <button
            onClick={handleSend}
            disabled={!input.trim() || sending}
            className="flex items-center justify-center h-9 w-9 rounded-lg bg-theme-interactive-primary text-white hover:bg-theme-interactive-primary-hover disabled:opacity-40 disabled:cursor-not-allowed transition-colors flex-shrink-0"
          >
            <Send className="h-4 w-4" />
          </button>
        </div>
      </div>
    </div>
  );
};
