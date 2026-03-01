import React, { useState } from 'react';
import { Radio, Trash2, Clock, Play, CheckCircle, XCircle, AlertTriangle } from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { Card } from '@/shared/components/ui/Card';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useListAguiSessions, useDestroyAguiSession } from '../api/aguiApi';
import type { AguiSession, AguiSessionStatus, AguiSessionFilterParams } from '../types/agui';

const STATUS_VARIANTS: Record<AguiSessionStatus, 'default' | 'primary' | 'success' | 'danger' | 'warning' | 'secondary'> = {
  idle: 'default',
  running: 'primary',
  completed: 'success',
  error: 'danger',
  cancelled: 'warning',
};

const STATUS_ICONS: Record<AguiSessionStatus, React.FC<{ className?: string }>> = {
  idle: Clock,
  running: Play,
  completed: CheckCircle,
  error: XCircle,
  cancelled: AlertTriangle,
};

const STATUS_OPTIONS: AguiSessionStatus[] = ['idle', 'running', 'completed', 'error', 'cancelled'];

interface AguiSessionListProps {
  selectedSessionId: string | null;
  onSelectSession: (session: AguiSession) => void;
}

export const AguiSessionList: React.FC<AguiSessionListProps> = ({
  selectedSessionId,
  onSelectSession,
}) => {
  const { hasPermission } = usePermissions();
  const { addNotification } = useNotifications();
  const [filters, setFilters] = useState<AguiSessionFilterParams>({});

  const { data: sessions, isLoading } = useListAguiSessions(filters);
  const destroySession = useDestroyAguiSession();

  const canManage = hasPermission('ai.agents.manage');

  const handleStatusFilter = (status: AguiSessionStatus | undefined) => {
    setFilters((prev) => ({ ...prev, status }));
  };

  const handleDestroy = (e: React.MouseEvent, sessionId: string) => {
    e.stopPropagation();
    destroySession.mutate(sessionId, {
      onSuccess: () => {
        addNotification({ type: 'success', message: 'Session destroyed' });
      },
      onError: () => {
        addNotification({ type: 'error', message: 'Failed to destroy session' });
      },
    });
  };

  if (isLoading) {
    return <LoadingSpinner size="sm" className="py-8" />;
  }

  const sessionList = sessions || [];

  return (
    <div className="space-y-4">
      {/* Status Filters */}
      <div className="flex flex-wrap items-center gap-2">
        <Button
          variant={filters.status === undefined ? 'primary' : 'outline'}
          size="xs"
          onClick={() => handleStatusFilter(undefined)}
        >
          All
        </Button>
        {STATUS_OPTIONS.map((status) => (
          <Button
            key={status}
            variant={filters.status === status ? 'primary' : 'outline'}
            size="xs"
            onClick={() => handleStatusFilter(status)}
          >
            {status}
          </Button>
        ))}
      </div>

      {/* Session List */}
      {sessionList.length === 0 ? (
        <div className="text-center py-12">
          <Radio className="h-10 w-10 text-theme-muted mx-auto mb-3 opacity-50" />
          <p className="text-theme-secondary text-sm">No AG-UI sessions found.</p>
        </div>
      ) : (
        <div className="space-y-2">
          {sessionList.map((session) => {
            const StatusIcon = STATUS_ICONS[session.status];
            const isSelected = selectedSessionId === session.id;

            return (
              <Card
                key={session.id}
                className={`p-3 cursor-pointer transition-colors hover:bg-theme-surface-hover ${
                  isSelected ? 'ring-2 ring-theme-interactive-primary' : ''
                }`}
                onClick={() => onSelectSession(session)}
              >
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-3 min-w-0">
                    <StatusIcon className="h-4 w-4 text-theme-muted flex-shrink-0" />
                    <div className="min-w-0">
                      <div className="flex items-center gap-2">
                        <span className="text-sm font-medium text-theme-primary truncate">
                          {session.thread_id}
                        </span>
                        <Badge variant={STATUS_VARIANTS[session.status]} size="xs">
                          {session.status}
                        </Badge>
                      </div>
                      <div className="flex items-center gap-2 mt-0.5">
                        {session.agent_id && (
                          <span className="text-xs text-theme-tertiary truncate">
                            Agent: {session.agent_id.slice(0, 8)}...
                          </span>
                        )}
                        <span className="text-xs text-theme-muted">
                          Seq #{session.sequence_number}
                        </span>
                      </div>
                    </div>
                  </div>
                  <div className="flex items-center gap-2 flex-shrink-0">
                    <span className="text-xs text-theme-muted">
                      {new Date(session.created_at).toLocaleString()}
                    </span>
                    {canManage && (
                      <Button
                        variant="ghost"
                        size="xs"
                        onClick={(e) => handleDestroy(e, session.id)}
                        loading={destroySession.isPending}
                        title="Destroy session"
                      >
                        <Trash2 className="h-3.5 w-3.5" />
                      </Button>
                    )}
                  </div>
                </div>
              </Card>
            );
          })}
        </div>
      )}
    </div>
  );
};
