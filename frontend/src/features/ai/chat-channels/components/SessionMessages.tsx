import React, { useState, useEffect, useCallback, useRef } from 'react';
import { ArrowLeft, RefreshCw } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { Loading } from '@/shared/components/ui/Loading';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { chatChannelsApi } from '@/shared/services/ai';
import { cn } from '@/shared/utils/cn';
import type { ChatMessageSummary } from '@/shared/services/ai';

interface SessionMessagesProps {
  sessionId: string;
  sessionStatus?: string;
  onBack: () => void;
  className?: string;
}

const deliveryStatusConfig: Record<string, { variant: 'success' | 'warning' | 'danger' | 'outline'; label: string }> = {
  pending: { variant: 'outline', label: 'Pending' },
  sent: { variant: 'outline', label: 'Sent' },
  delivered: { variant: 'success', label: 'Delivered' },
  read: { variant: 'success', label: 'Read' },
  failed: { variant: 'danger', label: 'Failed' },
};

export const SessionMessages: React.FC<SessionMessagesProps> = ({
  sessionId,
  sessionStatus,
  onBack,
  className,
}) => {
  const [messages, setMessages] = useState<ChatMessageSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const messagesEndRef = useRef<HTMLDivElement>(null);

  const loadMessages = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const response = await chatChannelsApi.getSessionMessages(sessionId, {
        per_page: 100,
      });
      setMessages(response.items || []);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load messages');
    } finally {
      setLoading(false);
    }
  }, [sessionId]);

  useEffect(() => {
    loadMessages();
  }, [loadMessages]);

  // Auto-refresh for active sessions
  useEffect(() => {
    if (sessionStatus === 'active') {
      const interval = setInterval(loadMessages, 5000);
      return () => clearInterval(interval);
    }
  }, [sessionStatus, loadMessages]);

  // Scroll to bottom on new messages
  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  const formatTime = (dateStr: string) => {
    return new Date(dateStr).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  };

  if (loading && messages.length === 0) {
    return (
      <div className="flex items-center justify-center p-8">
        <Loading size="lg" />
      </div>
    );
  }

  return (
    <div className={cn('space-y-4', className)}>
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Button variant="ghost" size="sm" onClick={onBack}>
            <ArrowLeft className="w-4 h-4" />
          </Button>
          <h3 className="font-medium text-theme-text-primary">Message History</h3>
          <span className="text-sm text-theme-text-secondary">
            ({messages.length} messages)
          </span>
        </div>
        <Button variant="ghost" size="sm" onClick={loadMessages} disabled={loading}>
          <RefreshCw className={cn('w-4 h-4', loading && 'animate-spin')} />
        </Button>
      </div>

      {/* Error */}
      {error && (
        <div className="p-3 rounded-lg bg-theme-status-error/10 text-theme-status-error text-sm">
          {error}
        </div>
      )}

      {/* Messages */}
      {messages.length === 0 ? (
        <EmptyState
          title="No messages"
          description="No messages have been exchanged in this session yet"
        />
      ) : (
        <div className="space-y-3 max-h-[600px] overflow-y-auto p-2">
          {messages.map((message) => {
            const isInbound = message.direction === 'inbound';
            const status = deliveryStatusConfig[message.delivery_status] || deliveryStatusConfig.pending;

            return (
              <div
                key={message.id}
                className={cn(
                  'flex',
                  isInbound ? 'justify-start' : 'justify-end'
                )}
              >
                <div
                  className={cn(
                    'max-w-[75%] rounded-lg px-4 py-2',
                    isInbound
                      ? 'bg-theme-bg-secondary text-theme-text-primary'
                      : 'bg-theme-primary/10 text-theme-text-primary'
                  )}
                >
                  <p className="text-sm whitespace-pre-wrap">{message.content}</p>
                  <div className="flex items-center gap-2 mt-1">
                    <span className="text-xs text-theme-text-secondary">
                      {formatTime(message.created_at)}
                    </span>
                    {!isInbound && (
                      <Badge variant={status.variant} size="xs">
                        {status.label}
                      </Badge>
                    )}
                  </div>
                </div>
              </div>
            );
          })}
          <div ref={messagesEndRef} />
        </div>
      )}
    </div>
  );
};
