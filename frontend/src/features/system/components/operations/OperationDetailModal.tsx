import React, { useState, useEffect } from 'react';
import {
  X,
  Activity,
  Clock,
  CheckCircle,
  XCircle,
  AlertCircle,
  User,
  Server,
  Calendar,
  Square,
  RefreshCw,
  Ban
} from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { systemApi } from '@/features/system/services/systemApi';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotifications } from '@/shared/hooks/useNotifications';
import type { SystemOperation } from '@/features/system/types/system.types';

interface OperationDetailModalProps {
  operationId: string | null;
  isOpen: boolean;
  onClose: () => void;
  onOperationUpdated?: () => void;
}

type TabId = 'info' | 'events' | 'options';

const statusLabels: Record<string, string> = {
  pending: 'Pending',
  scheduled: 'Scheduled',
  running: 'Running',
  complete: 'Complete',
  failed: 'Failed',
  aborted: 'Aborted',
  cancelled: 'Cancelled'
};

const statusColors: Record<string, 'info' | 'success' | 'warning' | 'danger' | 'secondary' | 'primary'> = {
  pending: 'warning',
  scheduled: 'info',
  running: 'primary',
  complete: 'success',
  failed: 'danger',
  aborted: 'secondary',
  cancelled: 'secondary'
};

/**
 * OperationDetailModal - Modal for viewing operation details with event timeline
 */
export const OperationDetailModal: React.FC<OperationDetailModalProps> = ({
  operationId,
  isOpen,
  onClose,
  onOperationUpdated
}) => {
  const { hasPermission } = usePermissions();
  const { addNotification } = useNotifications();
  const [operation, setOperation] = useState<SystemOperation | null>(null);
  const [loading, setLoading] = useState(false);
  const [activeTab, setActiveTab] = useState<TabId>('info');
  const [actionLoading, setActionLoading] = useState<string | null>(null);

  // Permission checks
  const canControlOperations = hasPermission('system.infra_operations.control');
  const canRescheduleOperations = hasPermission('system.infra_operations.reschedule');

  useEffect(() => {
    if (isOpen && operationId) {
      setLoading(true);
      setActiveTab('info');

      systemApi.getOperation(operationId)
        .then(data => {
          setOperation(data);
        })
        .catch(() => {
          setOperation(null);
        })
        .finally(() => {
          setLoading(false);
        });
    }
  }, [isOpen, operationId]);

  const refreshOperation = async () => {
    if (!operationId) return;
    try {
      const data = await systemApi.getOperation(operationId);
      setOperation(data);
    } catch {
      // Silently fail refresh
    }
  };

  const handleCancel = async () => {
    if (!operation) return;
    setActionLoading('cancel');
    try {
      await systemApi.cancelOperation(operation.id, 'Cancelled by user');
      addNotification({ type: 'success', message: 'Operation cancelled successfully' });
      await refreshOperation();
      onOperationUpdated?.();
    } catch {
      addNotification({ type: 'error', message: 'Failed to cancel operation' });
    } finally {
      setActionLoading(null);
    }
  };

  const handleAbort = async () => {
    if (!operation) return;
    setActionLoading('abort');
    try {
      await systemApi.abortOperation(operation.id, 'Aborted by user');
      addNotification({ type: 'success', message: 'Operation aborted successfully' });
      await refreshOperation();
      onOperationUpdated?.();
    } catch {
      addNotification({ type: 'error', message: 'Failed to abort operation' });
    } finally {
      setActionLoading(null);
    }
  };

  const handleRetry = async () => {
    if (!operation) return;
    setActionLoading('retry');
    try {
      await systemApi.retryOperation(operation.id);
      addNotification({ type: 'success', message: 'Operation scheduled for retry' });
      await refreshOperation();
      onOperationUpdated?.();
    } catch {
      addNotification({ type: 'error', message: 'Failed to retry operation' });
    } finally {
      setActionLoading(null);
    }
  };

  if (!isOpen) return null;

  const formatDateTime = (dateString?: string) => {
    if (!dateString) return '—';
    return new Date(dateString).toLocaleString();
  };

  const formatDuration = () => {
    if (!operation?.started_at) return '—';
    const start = new Date(operation.started_at).getTime();
    const end = operation.completed_at
      ? new Date(operation.completed_at).getTime()
      : Date.now();
    const duration = Math.floor((end - start) / 1000);

    if (duration < 60) return `${duration} seconds`;
    if (duration < 3600) return `${Math.floor(duration / 60)}m ${duration % 60}s`;
    return `${Math.floor(duration / 3600)}h ${Math.floor((duration % 3600) / 60)}m`;
  };

  const tabs = [
    { id: 'info' as const, label: 'Information', icon: Activity },
    { id: 'events' as const, label: 'Events', icon: Clock },
    { id: 'options' as const, label: 'Options', icon: Server }
  ];

  const renderInfoTab = () => {
    if (!operation) return null;

    return (
      <div className="space-y-6">
        {/* Status and Progress */}
        <div className="bg-theme-background rounded-lg p-4 border border-theme">
          <div className="flex items-center justify-between mb-4">
            <h4 className="font-medium text-theme-primary">Status</h4>
            <Badge variant={statusColors[operation.status]}>
              {statusLabels[operation.status] || operation.status}
            </Badge>
          </div>

          {operation.status === 'running' && (
            <div className="space-y-2">
              <div className="flex items-center justify-between text-sm">
                <span className="text-theme-secondary">Progress</span>
                <span className="text-theme-primary font-medium">{operation.progress || 0}%</span>
              </div>
              <div className="w-full bg-theme-surface rounded-full h-3">
                <div
                  className="bg-theme-accent h-3 rounded-full transition-all duration-300"
                  style={{ width: `${operation.progress || 0}%` }}
                />
              </div>
            </div>
          )}
        </div>

        {/* Details Grid */}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div className="space-y-4">
            <div>
              <label className="block text-sm text-theme-secondary mb-1">Command</label>
              <p className="text-theme-primary font-medium">{operation.command}</p>
            </div>
            <div>
              <label className="block text-sm text-theme-secondary mb-1">Description</label>
              <p className="text-theme-primary">{operation.description || '—'}</p>
            </div>
            <div>
              <label className="block text-sm text-theme-secondary mb-1">Resource Type</label>
              <p className="text-theme-primary">{operation.operable_type || '—'}</p>
            </div>
          </div>
          <div className="space-y-4">
            <div>
              <label className="block text-sm text-theme-secondary mb-1">Initiated By</label>
              <div className="flex items-center gap-2">
                <User className="w-4 h-4 text-theme-tertiary" />
                <span className="text-theme-primary">{operation.initiated_by_name || 'System'}</span>
              </div>
            </div>
            <div>
              <label className="block text-sm text-theme-secondary mb-1">Duration</label>
              <p className="text-theme-primary">{formatDuration()}</p>
            </div>
            <div>
              <label className="block text-sm text-theme-secondary mb-1">Exclusive</label>
              <Badge variant={operation.exclusive ? 'warning' : 'secondary'}>
                {operation.exclusive ? 'Yes' : 'No'}
              </Badge>
            </div>
          </div>
        </div>

        {/* Timestamps */}
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 pt-4 border-t border-theme">
          <div>
            <div className="flex items-center gap-2 text-sm text-theme-secondary mb-1">
              <Calendar className="w-4 h-4" />
              <span>Scheduled</span>
            </div>
            <p className="text-theme-primary text-sm">{formatDateTime(operation.scheduled_at)}</p>
          </div>
          <div>
            <div className="flex items-center gap-2 text-sm text-theme-secondary mb-1">
              <Clock className="w-4 h-4" />
              <span>Started</span>
            </div>
            <p className="text-theme-primary text-sm">{formatDateTime(operation.started_at)}</p>
          </div>
          <div>
            <div className="flex items-center gap-2 text-sm text-theme-secondary mb-1">
              <CheckCircle className="w-4 h-4" />
              <span>Completed</span>
            </div>
            <p className="text-theme-primary text-sm">{formatDateTime(operation.completed_at)}</p>
          </div>
        </div>

        {/* Error Message */}
        {operation.error_message && (
          <div className="bg-theme-danger/10 border border-theme-danger/30 rounded-lg p-4">
            <div className="flex items-center gap-2 mb-2">
              <XCircle className="w-5 h-5 text-theme-error" />
              <h4 className="font-medium text-theme-error">Error</h4>
            </div>
            <pre className="text-sm text-theme-error whitespace-pre-wrap font-mono">
              {operation.error_message}
            </pre>
          </div>
        )}
      </div>
    );
  };

  const renderEventsTab = () => {
    if (!operation) return null;

    const events = operation.events || [];

    if (events.length === 0) {
      return (
        <div className="text-center py-12">
          <Clock className="w-12 h-12 text-theme-tertiary mx-auto mb-4" />
          <p className="text-theme-secondary">No events recorded</p>
        </div>
      );
    }

    return (
      <div className="space-y-4">
        <h4 className="font-medium text-theme-primary">Event Timeline</h4>
        <div className="relative">
          <div className="absolute left-4 top-0 bottom-0 w-px bg-theme-border" />
          <div className="space-y-4">
            {events.map((event, idx: number) => {
              const eventType = String(event.type || 'info');
              const eventTimestamp = String(event.timestamp || '');
              const eventMessage = String(event.message || '');

              return (
                <div key={idx} className="relative flex items-start gap-4 pl-10">
                  <div className={`absolute left-2 w-4 h-4 rounded-full border-2 bg-theme-surface ${
                    eventType === 'error' ? 'border-theme-error' :
                    eventType === 'warning' ? 'border-theme-warning' :
                    eventType === 'success' ? 'border-theme-success' :
                    'border-theme-info'
                  }`} />
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 mb-1">
                      <Badge
                        variant={
                          eventType === 'error' ? 'danger' :
                          eventType === 'warning' ? 'warning' :
                          eventType === 'success' ? 'success' :
                          'info'
                        }
                        size="xs"
                      >
                        {eventType}
                      </Badge>
                      <span className="text-xs text-theme-tertiary">
                        {eventTimestamp ? new Date(eventTimestamp).toLocaleTimeString() : '—'}
                      </span>
                    </div>
                    <p className="text-sm text-theme-primary">{eventMessage}</p>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      </div>
    );
  };

  const renderOptionsTab = () => {
    if (!operation) return null;

    const options = operation.options || {};
    const hasOptions = Object.keys(options).length > 0;

    return (
      <div className="space-y-4">
        <h4 className="font-medium text-theme-primary">Operation Options</h4>
        {hasOptions ? (
          <pre className="bg-theme-background rounded-lg p-4 text-sm text-theme-primary overflow-x-auto border border-theme font-mono">
            {JSON.stringify(options, null, 2)}
          </pre>
        ) : (
          <div className="text-center py-12">
            <Server className="w-12 h-12 text-theme-tertiary mx-auto mb-4" />
            <p className="text-theme-secondary">No options configured</p>
          </div>
        )}
      </div>
    );
  };

  return (
    <div className="fixed inset-0 z-50 overflow-y-auto">
      <div className="fixed inset-0 bg-black/50 transition-opacity" onClick={onClose} />

      <div className="flex min-h-full items-center justify-center p-4">
        <div className="relative w-full max-w-3xl bg-theme-surface rounded-lg shadow-xl">
          {/* Header */}
          <div className="flex items-center justify-between p-4 border-b border-theme">
            <div className="flex items-center gap-3">
              <Activity className="w-6 h-6 text-theme-accent" />
              <div>
                <h2 className="text-lg font-semibold text-theme-primary">
                  {loading ? 'Loading...' : operation?.command || 'Operation Details'}
                </h2>
                {operation && (
                  <p className="text-sm text-theme-secondary">
                    {operation.operable_type || 'System Operation'}
                  </p>
                )}
              </div>
            </div>
            <Button variant="ghost" size="sm" onClick={onClose}>
              <X className="w-5 h-5" />
            </Button>
          </div>

          {/* Tabs */}
          <div className="border-b border-theme">
            <nav className="flex -mb-px">
              {tabs.map(tab => (
                <button
                  key={tab.id}
                  onClick={() => setActiveTab(tab.id)}
                  className={`flex items-center gap-2 px-6 py-3 text-sm font-medium border-b-2 transition-colors ${
                    activeTab === tab.id
                      ? 'border-theme-accent text-theme-accent'
                      : 'border-transparent text-theme-secondary hover:text-theme-primary hover:border-theme-tertiary'
                  }`}
                >
                  <tab.icon className="w-4 h-4" />
                  {tab.label}
                </button>
              ))}
            </nav>
          </div>

          {/* Content */}
          <div className="p-6 max-h-[60vh] overflow-y-auto">
            {loading ? (
              <div className="flex items-center justify-center py-12">
                <LoadingSpinner size="lg" />
              </div>
            ) : operation ? (
              <>
                {activeTab === 'info' && renderInfoTab()}
                {activeTab === 'events' && renderEventsTab()}
                {activeTab === 'options' && renderOptionsTab()}
              </>
            ) : (
              <div className="text-center py-12">
                <AlertCircle className="w-12 h-12 text-theme-error mx-auto mb-4" />
                <p className="text-theme-error">Failed to load operation details</p>
              </div>
            )}
          </div>

          {/* Footer */}
          <div className="flex items-center justify-between p-4 border-t border-theme">
            <div className="flex items-center gap-2">
              {/* Control buttons based on operation status */}
              {operation && canControlOperations && (
                <>
                  {/* Cancel for pending/scheduled operations */}
                  {(operation.status === 'pending' || operation.status === 'scheduled') && (
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={handleCancel}
                      disabled={actionLoading !== null}
                      className="text-theme-warning border-theme-warning hover:bg-theme-warning/10"
                    >
                      {actionLoading === 'cancel' ? (
                        <LoadingSpinner size="sm" className="mr-2" />
                      ) : (
                        <Ban className="w-4 h-4 mr-2" />
                      )}
                      Cancel
                    </Button>
                  )}

                  {/* Abort for running operations */}
                  {operation.status === 'running' && (
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={handleAbort}
                      disabled={actionLoading !== null}
                      className="text-theme-error border-theme-error hover:bg-theme-error/10"
                    >
                      {actionLoading === 'abort' ? (
                        <LoadingSpinner size="sm" className="mr-2" />
                      ) : (
                        <Square className="w-4 h-4 mr-2" />
                      )}
                      Abort
                    </Button>
                  )}

                  {/* Retry for failed/aborted operations */}
                  {(operation.status === 'failed' || operation.status === 'aborted') && canRescheduleOperations && (
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={handleRetry}
                      disabled={actionLoading !== null}
                      className="text-theme-info border-theme-info hover:bg-theme-info/10"
                    >
                      {actionLoading === 'retry' ? (
                        <LoadingSpinner size="sm" className="mr-2" />
                      ) : (
                        <RefreshCw className="w-4 h-4 mr-2" />
                      )}
                      Retry
                    </Button>
                  )}
                </>
              )}
            </div>
            <Button variant="outline" onClick={onClose}>
              Close
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
};

export default OperationDetailModal;
