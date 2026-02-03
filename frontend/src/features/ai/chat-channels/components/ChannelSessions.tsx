import React, { useState, useEffect, useCallback } from 'react';
import {
  MessageSquare,
  User,
  Clock,
  ArrowRight,
  RefreshCw,
  X,
} from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Select } from '@/shared/components/ui/Select';
import { Loading } from '@/shared/components/ui/Loading';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { chatChannelsApi } from '@/shared/services/ai';
import { cn } from '@/shared/utils/cn';
import type { ChatSessionSummary, SessionFilters, SessionStatus } from '@/shared/services/ai';

interface ChannelSessionsProps {
  channelId: string;
  onSelectSession?: (session: ChatSessionSummary) => void;
  onTransferSession?: (session: ChatSessionSummary) => void;
  onCloseSession?: (session: ChatSessionSummary) => void;
  className?: string;
}

const statusConfig: Record<SessionStatus, {
  variant: 'success' | 'warning' | 'danger' | 'outline';
  label: string;
}> = {
  active: { variant: 'success', label: 'Active' },
  idle: { variant: 'outline', label: 'Idle' },
  transferred: { variant: 'warning', label: 'Transferred' },
  closed: { variant: 'danger', label: 'Closed' },
  expired: { variant: 'outline', label: 'Expired' },
};

const statusOptions = [
  { value: '', label: 'All Sessions' },
  { value: 'active', label: 'Active' },
  { value: 'idle', label: 'Idle' },
  { value: 'transferred', label: 'Transferred' },
  { value: 'closed', label: 'Closed' },
];

export const ChannelSessions: React.FC<ChannelSessionsProps> = ({
  channelId,
  onSelectSession,
  onTransferSession,
  onCloseSession,
  className,
}) => {
  const [sessions, setSessions] = useState<ChatSessionSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [statusFilter, setStatusFilter] = useState<string>('');
  const [totalCount, setTotalCount] = useState(0);

  const loadSessions = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);

      const filters: SessionFilters = {
        channel_id: channelId,
        per_page: 50,
      };
      if (statusFilter) filters.status = statusFilter as SessionStatus;

      const response = await chatChannelsApi.getSessions(filters);
      setSessions(response.items || []);
      setTotalCount(response.pagination?.total_count || 0);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load sessions');
    } finally {
      setLoading(false);
    }
  }, [channelId, statusFilter]);

  useEffect(() => {
    loadSessions();
  }, [loadSessions]);

  // Auto-refresh for active sessions
  useEffect(() => {
    const hasActive = sessions.some(s => s.status === 'active');
    if (hasActive) {
      const interval = setInterval(loadSessions, 10000);
      return () => clearInterval(interval);
    }
  }, [sessions, loadSessions]);

  const handleClose = async (session: ChatSessionSummary) => {
    try {
      await chatChannelsApi.closeSession(session.id);
      loadSessions();
      onCloseSession?.(session);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to close session');
    }
  };

  const formatTime = (dateStr: string) => {
    const date = new Date(dateStr);
    const now = new Date();
    const diff = now.getTime() - date.getTime();

    if (diff < 60000) return 'Just now';
    if (diff < 3600000) return `${Math.floor(diff / 60000)}m ago`;
    if (diff < 86400000) return `${Math.floor(diff / 3600000)}h ago`;
    return date.toLocaleDateString();
  };

  if (loading && sessions.length === 0) {
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
        <div>
          <h3 className="font-medium text-theme-text-primary">Chat Sessions</h3>
          <p className="text-sm text-theme-text-secondary">
            {totalCount} session{totalCount !== 1 ? 's' : ''}
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Select
            value={statusFilter}
            onChange={(value) => setStatusFilter(value)}
            className="w-32"
          >
            {statusOptions.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </Select>
          <Button variant="ghost" size="sm" onClick={loadSessions} disabled={loading}>
            <RefreshCw className={cn('w-4 h-4', loading && 'animate-spin')} />
          </Button>
        </div>
      </div>

      {/* Error */}
      {error && (
        <div className="p-3 rounded-lg bg-theme-status-error/10 text-theme-status-error text-sm">
          {error}
        </div>
      )}

      {/* Sessions List */}
      {sessions.length === 0 ? (
        <EmptyState
          icon={MessageSquare}
          title="No sessions found"
          description={
            statusFilter
              ? 'Try adjusting your filter'
              : 'No chat sessions have been started yet'
          }
        />
      ) : (
        <div className="space-y-2">
          {sessions.map((session) => {
            const status = statusConfig[session.status] || statusConfig.idle;

            return (
              <Card
                key={session.id}
                className="cursor-pointer hover:bg-theme-bg-secondary/50 transition-colors"
                onClick={() => onSelectSession?.(session)}
              >
                <CardContent className="p-3">
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-3">
                      <div className="h-8 w-8 bg-theme-bg-secondary rounded-full flex items-center justify-center">
                        <User className="w-4 h-4 text-theme-text-secondary" />
                      </div>
                      <div>
                        <div className="flex items-center gap-2">
                          <span className="font-medium text-theme-text-primary text-sm">
                            {session.platform_user_id}
                          </span>
                          <Badge variant={status.variant} size="sm">
                            {status.label}
                          </Badge>
                        </div>
                        <div className="flex items-center gap-3 text-xs text-theme-text-secondary">
                          <span className="flex items-center gap-1">
                            <MessageSquare className="w-3 h-3" />
                            {session.message_count} messages
                          </span>
                          <span className="flex items-center gap-1">
                            <Clock className="w-3 h-3" />
                            {formatTime(session.last_activity_at)}
                          </span>
                        </div>
                      </div>
                    </div>
                    <div className="flex items-center gap-2">
                      {session.status === 'active' && (
                        <>
                          {onTransferSession && (
                            <Button
                              variant="ghost"
                              size="sm"
                              onClick={(e) => {
                                e.stopPropagation();
                                onTransferSession(session);
                              }}
                            >
                              <ArrowRight className="w-3 h-3" />
                            </Button>
                          )}
                          <Button
                            variant="ghost"
                            size="sm"
                            onClick={(e) => {
                              e.stopPropagation();
                              handleClose(session);
                            }}
                          >
                            <X className="w-3 h-3" />
                          </Button>
                        </>
                      )}
                    </div>
                  </div>
                </CardContent>
              </Card>
            );
          })}
        </div>
      )}
    </div>
  );
};

export default ChannelSessions;
