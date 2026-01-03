import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Webhook, RefreshCw, Filter, ChevronDown, RotateCcw,
  CheckCircle, XCircle, Clock, AlertTriangle
} from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { PageErrorBoundary } from '@/shared/components/error/ErrorBoundary';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotification } from '@/shared/hooks/useNotification';
import { useWebhookEvents } from '../hooks/useWebhookEvents';
import type { GitWebhookEvent, WebhookEventFilters } from '../types';

const StatusBadge: React.FC<{ status: string }> = ({ status }) => {
  const getConfig = () => {
    switch (status) {
      case 'processed':
        return { bg: 'bg-theme-success/10', text: 'text-theme-success', icon: CheckCircle };
      case 'failed':
        return { bg: 'bg-theme-error/10', text: 'text-theme-error', icon: XCircle };
      case 'processing':
        return { bg: 'bg-theme-info/10', text: 'text-theme-info', icon: Clock };
      case 'pending':
        return { bg: 'bg-theme-warning/10', text: 'text-theme-warning', icon: AlertTriangle };
      default:
        return { bg: 'bg-theme-secondary/10', text: 'text-theme-secondary', icon: Clock };
    }
  };

  const config = getConfig();
  const Icon = config.icon;

  return (
    <span className={`inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-medium ${config.bg} ${config.text}`}>
      <Icon className="w-3 h-3" />
      {status.charAt(0).toUpperCase() + status.slice(1)}
    </span>
  );
};

const formatTimeAgo = (dateString: string): string => {
  const date = new Date(dateString);
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffMins = Math.floor(diffMs / 60000);
  const diffHours = Math.floor(diffMins / 60);
  const diffDays = Math.floor(diffHours / 24);

  if (diffMins < 1) return 'just now';
  if (diffMins < 60) return `${diffMins}m ago`;
  if (diffHours < 24) return `${diffHours}h ago`;
  if (diffDays < 7) return `${diffDays}d ago`;
  return date.toLocaleDateString();
};

interface EventRowProps {
  event: GitWebhookEvent;
  onClick: () => void;
  onRetry: () => void;
}

const EventRow: React.FC<EventRowProps> = ({ event, onClick, onRetry }) => (
  <div
    className="flex items-center justify-between p-4 hover:bg-theme-surface-hover cursor-pointer border-b border-theme last:border-b-0"
    onClick={onClick}
  >
    <div className="flex items-center gap-4 min-w-0 flex-1">
      <div className="w-10 h-10 rounded-lg bg-theme-secondary/10 flex items-center justify-center flex-shrink-0">
        <Webhook className="w-5 h-5 text-theme-secondary" />
      </div>
      <div className="min-w-0">
        <div className="flex items-center gap-2">
          <p className="font-medium text-theme-primary">{event.event_type}</p>
          {event.repository?.name && (
            <span className="text-xs text-theme-tertiary bg-theme-secondary/10 px-2 py-0.5 rounded">
              {event.repository.name}
            </span>
          )}
        </div>
        <p className="text-xs text-theme-tertiary mt-1 truncate">
          ID: {event.id.slice(0, 8)}...
          {event.delivery_id && ` • Delivery: ${event.delivery_id.slice(0, 8)}...`}
        </p>
      </div>
    </div>

    <div className="flex items-center gap-4">
      <StatusBadge status={event.status} />
      <span className="text-xs text-theme-tertiary min-w-[70px] text-right">
        {formatTimeAgo(event.created_at)}
      </span>
      {event.status === 'failed' && (
        <Button
          onClick={(e) => {
            e.stopPropagation();
            onRetry();
          }}
          variant="ghost"
          size="sm"
          title="Retry event"
        >
          <RotateCcw className="w-4 h-4" />
        </Button>
      )}
    </div>
  </div>
);

const StatsCard: React.FC<{ label: string; value: number | string; color: string }> = ({ label, value, color }) => (
  <div className="bg-theme-surface rounded-lg p-4 border border-theme">
    <p className="text-xs text-theme-tertiary mb-1">{label}</p>
    <p className={`text-2xl font-semibold ${color}`}>{value}</p>
  </div>
);

const WebhookEventsPageContent: React.FC = () => {
  const navigate = useNavigate();
  const { showNotification } = useNotification();
  const [page, setPage] = useState(1);
  const [filters, setFilters] = useState<WebhookEventFilters>({
    status: 'all',
  });
  const [showFilters, setShowFilters] = useState(false);

  const {
    events = [],
    pagination,
    stats = { total_events: 0, pending: 0, processed: 0, failed: 0 },
    loading,
    error,
    refresh,
    retryEvent
  } = useWebhookEvents({
    page,
    perPage: 20,
    ...filters,
  });

  const handleRetryEvent = async (eventId: string) => {
    try {
      await retryEvent(eventId);
      showNotification('Event retry queued', 'success');
    } catch (err) {
      showNotification(err instanceof Error ? err.message : 'Failed to retry event', 'error');
    }
  };

  const breadcrumbs = [
    { label: 'CI/CD', href: '/app/ci-cd', icon: Webhook },
    { label: 'Webhook Events' }
  ];

  const actions = [
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: refresh,
      variant: 'primary' as const,
      icon: RefreshCw
    }
  ];

  const eventTypes = ['push', 'pull_request', 'workflow_run', 'check_run', 'check_suite', 'release', 'tag'];
  const statusOptions = ['all', 'pending', 'processing', 'processed', 'failed'];

  return (
    <PageContainer
      title="Webhook Events"
      description="View and manage incoming webhook events"
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      <div className="space-y-6">
        {/* Stats */}
        {stats && (
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            <StatsCard label="Total Events" value={stats.total_events} color="text-theme-primary" />
            <StatsCard label="Processed" value={stats.processed} color="text-theme-success" />
            <StatsCard label="Pending" value={stats.pending} color="text-theme-warning" />
            <StatsCard label="Failed" value={stats.failed} color="text-theme-error" />
          </div>
        )}

        {/* Filters */}
        <div className="flex items-center justify-between">
          <Button
            onClick={() => setShowFilters(!showFilters)}
            variant="secondary"
            size="sm"
          >
            <Filter className="w-4 h-4 mr-2" />
            Filters
            <ChevronDown className={`w-4 h-4 ml-2 transition-transform ${showFilters ? 'rotate-180' : ''}`} />
          </Button>
          {(filters.status !== 'all' || filters.eventType || filters.since || filters.until) && (
            <Button
              onClick={() => {
                setFilters({ status: 'all' });
                setPage(1);
              }}
              variant="ghost"
              size="sm"
            >
              Clear Filters
            </Button>
          )}
        </div>

        {showFilters && (
          <div className="bg-theme-surface rounded-lg p-4 border border-theme flex flex-wrap gap-4">
            <div>
              <label className="block text-xs text-theme-tertiary mb-1">Status</label>
              <select
                value={filters.status || 'all'}
                onChange={(e) => {
                  setFilters({ ...filters, status: e.target.value as WebhookEventFilters['status'] });
                  setPage(1);
                }}
                className="bg-theme-surface border border-theme rounded-lg px-3 py-2 text-sm text-theme-primary"
              >
                {statusOptions.map((status) => (
                  <option key={status} value={status}>
                    {status === 'all' ? 'All Statuses' : status.charAt(0).toUpperCase() + status.slice(1)}
                  </option>
                ))}
              </select>
            </div>
            <div>
              <label className="block text-xs text-theme-tertiary mb-1">Event Type</label>
              <select
                value={filters.eventType || ''}
                onChange={(e) => {
                  setFilters({ ...filters, eventType: e.target.value || undefined });
                  setPage(1);
                }}
                className="bg-theme-surface border border-theme rounded-lg px-3 py-2 text-sm text-theme-primary"
              >
                <option value="">All Types</option>
                {eventTypes.map((type) => (
                  <option key={type} value={type}>
                    {type.replace('_', ' ')}
                  </option>
                ))}
              </select>
            </div>
            <div>
              <label className="block text-xs text-theme-tertiary mb-1">Since</label>
              <Input
                type="date"
                value={filters.since || ''}
                onChange={(e) => {
                  setFilters({ ...filters, since: e.target.value || undefined });
                  setPage(1);
                }}
                className="w-40"
              />
            </div>
            <div>
              <label className="block text-xs text-theme-tertiary mb-1">Until</label>
              <Input
                type="date"
                value={filters.until || ''}
                onChange={(e) => {
                  setFilters({ ...filters, until: e.target.value || undefined });
                  setPage(1);
                }}
                className="w-40"
              />
            </div>
          </div>
        )}

        {/* Error State */}
        {error && (
          <div className="bg-theme-error/10 border border-theme-error rounded-lg p-4">
            <p className="text-theme-error">{error}</p>
            <Button onClick={refresh} variant="secondary" size="sm" className="mt-2">
              Try Again
            </Button>
          </div>
        )}

        {/* Events List */}
        <div className="bg-theme-surface rounded-lg border border-theme">
          <div className="p-4 border-b border-theme">
            <h3 className="font-medium text-theme-primary">Events</h3>
          </div>

          {loading ? (
            <div className="flex items-center justify-center py-12">
              <LoadingSpinner size="md" />
              <span className="ml-3 text-theme-secondary">Loading events...</span>
            </div>
          ) : events.length > 0 ? (
            <>
              <div className="divide-y divide-theme">
                {events.map((event) => (
                  <EventRow
                    key={event.id}
                    event={event}
                    onClick={() => navigate(`/app/ci-cd/webhooks/${event.id}`)}
                    onRetry={() => handleRetryEvent(event.id)}
                  />
                ))}
              </div>

              {/* Pagination */}
              {pagination && pagination.total_pages > 1 && (
                <div className="flex items-center justify-between p-4 border-t border-theme">
                  <p className="text-sm text-theme-tertiary">
                    Showing {events.length} of {pagination.total_count} events
                  </p>
                  <div className="flex items-center gap-2">
                    <Button
                      onClick={() => setPage((p) => Math.max(1, p - 1))}
                      disabled={page === 1}
                      variant="secondary"
                      size="sm"
                    >
                      Previous
                    </Button>
                    <span className="text-sm text-theme-secondary">
                      Page {page} of {pagination.total_pages}
                    </span>
                    <Button
                      onClick={() => setPage((p) => Math.min(pagination.total_pages, p + 1))}
                      disabled={page >= pagination.total_pages}
                      variant="secondary"
                      size="sm"
                    >
                      Next
                    </Button>
                  </div>
                </div>
              )}
            </>
          ) : (
            <div className="p-8 text-center">
              <Webhook className="w-12 h-12 text-theme-secondary mx-auto mb-4" />
              <h3 className="text-lg font-medium text-theme-primary mb-2">No Webhook Events</h3>
              <p className="text-theme-secondary">
                {filters.status !== 'all' || filters.eventType
                  ? 'Try adjusting your filters.'
                  : 'No webhook events have been received yet. Configure webhooks in your Git provider.'}
              </p>
            </div>
          )}
        </div>
      </div>
    </PageContainer>
  );
};

export const WebhookEventsPage: React.FC = () => (
  <PageErrorBoundary>
    <WebhookEventsPageContent />
  </PageErrorBoundary>
);

export default WebhookEventsPage;
