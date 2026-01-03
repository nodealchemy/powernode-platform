import React, { useState, useEffect, useCallback } from 'react';
import { useParams } from 'react-router-dom';
import {
  Webhook, RefreshCw, RotateCcw, CheckCircle, XCircle,
  Clock, AlertTriangle, Calendar, FileJson, Hash
} from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { PageErrorBoundary } from '@/shared/components/error/ErrorBoundary';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { gitProvidersApi } from '@/features/git-providers/services/gitProvidersApi';
import { useNotification } from '@/shared/hooks/useNotification';
import { WebhookPayloadViewer } from './WebhookPayloadViewer';
import type { GitWebhookEventDetail } from '@/features/git-providers/types';

const StatusBadge: React.FC<{ status: string; large?: boolean }> = ({ status, large = false }) => {
  const getConfig = () => {
    switch (status) {
      case 'processed':
        return { bg: 'bg-theme-success/10', text: 'text-theme-success', icon: CheckCircle, label: 'Processed' };
      case 'failed':
        return { bg: 'bg-theme-error/10', text: 'text-theme-error', icon: XCircle, label: 'Failed' };
      case 'processing':
        return { bg: 'bg-theme-info/10', text: 'text-theme-info', icon: Clock, label: 'Processing' };
      case 'pending':
        return { bg: 'bg-theme-warning/10', text: 'text-theme-warning', icon: AlertTriangle, label: 'Pending' };
      default:
        return { bg: 'bg-theme-secondary/10', text: 'text-theme-secondary', icon: Clock, label: status };
    }
  };

  const config = getConfig();
  const Icon = config.icon;
  const sizeClasses = large ? 'px-4 py-2 text-sm' : 'px-2.5 py-1 text-xs';

  return (
    <span className={`inline-flex items-center gap-1.5 rounded-full font-medium ${config.bg} ${config.text} ${sizeClasses}`}>
      <Icon className={large ? 'w-4 h-4' : 'w-3 h-3'} />
      {config.label}
    </span>
  );
};

const WebhookEventDetailPageContent: React.FC = () => {
  const { eventId } = useParams<{ eventId: string }>();
  const { showNotification } = useNotification();

  const [event, setEvent] = useState<GitWebhookEventDetail | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<'payload' | 'headers' | 'result'>('payload');

  const fetchEvent = useCallback(async () => {
    if (!eventId) return;

    try {
      setLoading(true);
      setError(null);
      const data = await gitProvidersApi.getWebhookEvent(eventId);
      setEvent(data);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch event');
    } finally {
      setLoading(false);
    }
  }, [eventId]);

  useEffect(() => {
    fetchEvent();
  }, [fetchEvent]);

  const handleRetry = async () => {
    if (!eventId) return;
    try {
      await gitProvidersApi.retryWebhookEvent(eventId);
      showNotification('Event retry queued', 'success');
      fetchEvent();
    } catch (err) {
      showNotification(err instanceof Error ? err.message : 'Failed to retry event', 'error');
    }
  };

  const breadcrumbs = [
    { label: 'CI/CD', href: '/app/ci-cd', icon: Webhook },
    { label: 'Webhook Events', href: '/app/ci-cd/webhooks' },
    { label: event?.event_type || 'Event' }
  ];

  const canRetry = event?.status === 'failed';

  const actions = [
    ...(canRetry ? [{
      id: 'retry',
      label: 'Retry',
      onClick: handleRetry,
      variant: 'secondary' as const,
      icon: RotateCcw
    }] : []),
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: fetchEvent,
      variant: 'primary' as const,
      icon: RefreshCw
    }
  ];

  if (error) {
    return (
      <PageContainer
        title="Webhook Event"
        breadcrumbs={breadcrumbs}
        actions={actions}
      >
        <div className="bg-theme-error/10 border border-theme-error rounded-lg p-4">
          <p className="text-theme-error">{error}</p>
          <Button onClick={fetchEvent} variant="secondary" size="sm" className="mt-2">
            Try Again
          </Button>
        </div>
      </PageContainer>
    );
  }

  if (loading && !event) {
    return (
      <PageContainer
        title="Webhook Event"
        breadcrumbs={breadcrumbs}
        actions={actions}
      >
        <div className="flex items-center justify-center py-12">
          <LoadingSpinner size="lg" />
          <span className="ml-3 text-theme-secondary">Loading event details...</span>
        </div>
      </PageContainer>
    );
  }

  const tabs = [
    { id: 'payload', label: 'Payload', icon: FileJson },
    { id: 'headers', label: 'Headers', icon: Hash },
    { id: 'result', label: 'Result', icon: CheckCircle },
  ];

  return (
    <PageContainer
      title={event?.event_type || 'Webhook Event'}
      description={`Event ID: ${event?.id?.slice(0, 8)}...`}
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      <div className="space-y-6">
        {/* Event Header */}
        {event && (
          <div className="bg-theme-surface rounded-lg p-6 border border-theme">
            <div className="flex items-start justify-between mb-4">
              <div className="flex items-center gap-4">
                <div className="w-14 h-14 rounded-lg bg-theme-secondary/10 flex items-center justify-center">
                  <Webhook className="w-7 h-7 text-theme-secondary" />
                </div>
                <div>
                  <h2 className="text-xl font-semibold text-theme-primary">{event.event_type}</h2>
                  <p className="text-sm text-theme-tertiary mt-1">
                    {event.repository?.name && `Repository: ${event.repository.name}`}
                  </p>
                </div>
              </div>
              <StatusBadge status={event.status} large />
            </div>

            {/* Metadata Grid */}
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4 pt-4 border-t border-theme">
              <div className="flex items-center gap-2">
                <Hash className="w-4 h-4 text-theme-tertiary" />
                <div>
                  <p className="text-xs text-theme-tertiary">Event ID</p>
                  <p className="text-sm text-theme-primary font-mono">{event.id.slice(0, 12)}...</p>
                </div>
              </div>
              {event.delivery_id && (
                <div className="flex items-center gap-2">
                  <Hash className="w-4 h-4 text-theme-tertiary" />
                  <div>
                    <p className="text-xs text-theme-tertiary">Delivery ID</p>
                    <p className="text-sm text-theme-primary font-mono">{event.delivery_id.slice(0, 12)}...</p>
                  </div>
                </div>
              )}
              <div className="flex items-center gap-2">
                <Calendar className="w-4 h-4 text-theme-tertiary" />
                <div>
                  <p className="text-xs text-theme-tertiary">Received</p>
                  <p className="text-sm text-theme-primary">
                    {new Date(event.created_at).toLocaleString()}
                  </p>
                </div>
              </div>
              {event.processed_at && (
                <div className="flex items-center gap-2">
                  <Calendar className="w-4 h-4 text-theme-tertiary" />
                  <div>
                    <p className="text-xs text-theme-tertiary">Processed</p>
                    <p className="text-sm text-theme-primary">
                      {new Date(event.processed_at).toLocaleString()}
                    </p>
                  </div>
                </div>
              )}
              {event.retry_count !== undefined && event.retry_count > 0 && (
                <div className="flex items-center gap-2">
                  <RotateCcw className="w-4 h-4 text-theme-tertiary" />
                  <div>
                    <p className="text-xs text-theme-tertiary">Retries</p>
                    <p className="text-sm text-theme-primary">{event.retry_count}</p>
                  </div>
                </div>
              )}
            </div>

            {/* Error Message */}
            {event.status === 'failed' && event.error_message && (
              <div className="mt-4 pt-4 border-t border-theme">
                <div className="bg-theme-error/10 border border-theme-error rounded-lg p-4">
                  <p className="text-xs text-theme-error font-medium mb-1">Error</p>
                  <p className="text-sm text-theme-error">{event.error_message}</p>
                </div>
              </div>
            )}
          </div>
        )}

        {/* Tabs */}
        <div className="bg-theme-surface rounded-lg border border-theme">
          <div className="flex border-b border-theme">
            {tabs.map((tab) => {
              const Icon = tab.icon;
              return (
                <button
                  key={tab.id}
                  onClick={() => setActiveTab(tab.id as typeof activeTab)}
                  className={`flex items-center gap-2 px-4 py-3 text-sm font-medium border-b-2 transition-colors ${
                    activeTab === tab.id
                      ? 'border-theme-primary text-theme-primary'
                      : 'border-transparent text-theme-secondary hover:text-theme-primary'
                  }`}
                >
                  <Icon className="w-4 h-4" />
                  {tab.label}
                </button>
              );
            })}
          </div>

          <div className="p-4">
            {activeTab === 'payload' && event?.payload && (
              <WebhookPayloadViewer payload={event.payload} />
            )}
            {activeTab === 'payload' && !event?.payload && (
              <p className="text-center text-theme-secondary py-8">No payload data available</p>
            )}

            {activeTab === 'headers' && event?.headers && (
              <WebhookPayloadViewer payload={event.headers} />
            )}
            {activeTab === 'headers' && !event?.headers && (
              <p className="text-center text-theme-secondary py-8">No headers data available</p>
            )}

            {activeTab === 'result' && (
              <div className="space-y-4">
                {event?.processing_result ? (
                  <WebhookPayloadViewer payload={event.processing_result} />
                ) : event?.status === 'processed' ? (
                  <div className="text-center py-8">
                    <CheckCircle className="w-12 h-12 text-theme-success mx-auto mb-4" />
                    <p className="text-theme-primary font-medium">Event processed successfully</p>
                    <p className="text-sm text-theme-tertiary mt-1">No additional result data</p>
                  </div>
                ) : event?.status === 'failed' ? (
                  <div className="text-center py-8">
                    <XCircle className="w-12 h-12 text-theme-error mx-auto mb-4" />
                    <p className="text-theme-primary font-medium">Event processing failed</p>
                    {event.error_message && (
                      <p className="text-sm text-theme-error mt-2">{event.error_message}</p>
                    )}
                  </div>
                ) : (
                  <div className="text-center py-8">
                    <Clock className="w-12 h-12 text-theme-warning mx-auto mb-4" />
                    <p className="text-theme-primary font-medium">Event is {event?.status}</p>
                    <p className="text-sm text-theme-tertiary mt-1">Result will be available after processing</p>
                  </div>
                )}
              </div>
            )}
          </div>
        </div>
      </div>
    </PageContainer>
  );
};

export const WebhookEventDetailPage: React.FC = () => (
  <PageErrorBoundary>
    <WebhookEventDetailPageContent />
  </PageErrorBoundary>
);

export default WebhookEventDetailPage;
