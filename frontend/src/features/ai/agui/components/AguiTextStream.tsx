import React, { useMemo } from 'react';
import { MessageSquare } from 'lucide-react';
import type { AguiEvent } from '../types/agui';

interface AguiTextStreamProps {
  events: AguiEvent[];
}

interface TextMessage {
  messageId: string;
  role: string;
  content: string;
  isComplete: boolean;
  timestamp: string;
}

export const AguiTextStream: React.FC<AguiTextStreamProps> = ({ events }) => {
  // Reconstruct text messages from TEXT_MESSAGE events
  const messages = useMemo(() => {
    const messageMap = new Map<string, TextMessage>();

    for (const event of events) {
      if (!event.message_id) continue;

      if (event.type === 'TEXT_MESSAGE_START') {
        messageMap.set(event.message_id, {
          messageId: event.message_id,
          role: event.role || 'assistant',
          content: '',
          isComplete: false,
          timestamp: event.timestamp,
        });
      } else if (event.type === 'TEXT_MESSAGE_CONTENT') {
        const msg = messageMap.get(event.message_id);
        if (msg) {
          msg.content += event.delta?.content ?? event.content ?? '';
        }
      } else if (event.type === 'TEXT_MESSAGE_END') {
        const msg = messageMap.get(event.message_id);
        if (msg) {
          msg.isComplete = true;
        }
      }
    }

    return Array.from(messageMap.values());
  }, [events]);

  if (messages.length === 0) {
    return (
      <div className="text-center py-8">
        <MessageSquare className="h-8 w-8 text-theme-muted mx-auto mb-2 opacity-50" />
        <p className="text-sm text-theme-secondary">No text messages yet.</p>
      </div>
    );
  }

  return (
    <div className="space-y-3">
      {messages.map((msg) => (
        <div
          key={msg.messageId}
          className={`rounded-lg p-3 ${
            msg.role === 'user'
              ? 'bg-theme-interactive-primary bg-opacity-10 ml-8'
              : 'bg-theme-surface mr-8'
          }`}
        >
          <div className="flex items-center justify-between mb-1">
            <span className="text-xs font-medium text-theme-secondary capitalize">
              {msg.role}
            </span>
            <span className="text-xs text-theme-muted">
              {new Date(msg.timestamp).toLocaleTimeString()}
            </span>
          </div>
          <div className="text-sm text-theme-primary whitespace-pre-wrap">
            {msg.content}
            {!msg.isComplete && (
              <span className="inline-block w-1.5 h-4 bg-theme-interactive-primary animate-pulse ml-0.5 align-text-bottom" />
            )}
          </div>
        </div>
      ))}
    </div>
  );
};
