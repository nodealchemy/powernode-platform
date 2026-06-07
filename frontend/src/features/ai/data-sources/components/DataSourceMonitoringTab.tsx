import React, { useState, useEffect, useCallback, useMemo } from 'react';
import {
  Radar,
  Plus,
  Trash2,
  Save,
  X,
  Clock,
  AlertTriangle,
  RefreshCw,
  Fingerprint,
  Timer,
} from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { Select } from '@/shared/components/ui/Select';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { dataSourcesApi } from '@/shared/services/ai/DataSourcesApiService';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { logger } from '@/shared/utils/logger';
import type {
  AiDataSourceEndpoint,
  AiDataSourceSubscription,
  DataSourcePollFrequency,
  DataSourceSubscriptionStatus,
} from '@/shared/types/ai';

interface DataSourceMonitoringTabProps {
  dataSourceId: string;
  // Stream grant (ai.data_sources.stream) gates create/cancel. Listing + SWR
  // config remain visible read-only without it.
  canManageSubscriptions: boolean;
}

type BadgeVariant = 'success' | 'warning' | 'danger' | 'info' | 'outline' | 'secondary';

// Cadence options mirror Ai::DataSourceSubscription::POLL_FREQUENCIES.
const POLL_FREQUENCIES: DataSourcePollFrequency[] = [
  'manual', '5min', 'hourly', 'daily', 'weekly', 'monthly', 'realtime',
];

const FREQUENCY_LABELS: Record<DataSourcePollFrequency, string> = {
  manual: 'Manual',
  '5min': 'Every 5 min',
  hourly: 'Hourly',
  daily: 'Daily',
  weekly: 'Weekly',
  monthly: 'Monthly',
  realtime: 'Realtime',
};

function statusBadge(
  status: DataSourceSubscriptionStatus
): { variant: BadgeVariant; label: string } {
  switch (status) {
    case 'active':
      return { variant: 'success', label: 'Active' };
    case 'paused':
      return { variant: 'outline', label: 'Paused' };
    case 'error':
      return { variant: 'danger', label: 'Error' };
    default:
      return { variant: 'secondary', label: status };
  }
}

// Compact a checksum for display — the full SHA is not useful inline.
function shortChecksum(checksum: string | null | undefined): string {
  if (!checksum) return '—';
  return checksum.length > 12 ? `${checksum.slice(0, 12)}…` : checksum;
}

function formatTimestamp(value: string | null | undefined): string {
  if (!value) return '—';
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return '—';
  return parsed.toLocaleString();
}

export const DataSourceMonitoringTab: React.FC<DataSourceMonitoringTabProps> = ({
  dataSourceId,
  canManageSubscriptions,
}) => {
  const { addNotification } = useNotifications();

  const [endpoints, setEndpoints] = useState<AiDataSourceEndpoint[]>([]);
  const [subscriptions, setSubscriptions] = useState<AiDataSourceSubscription[]>([]);
  const [loading, setLoading] = useState(true);
  const [creating, setCreating] = useState(false);
  const [cancelingId, setCancelingId] = useState<string | null>(null);
  const [formOpen, setFormOpen] = useState(false);
  const [formEndpointId, setFormEndpointId] = useState<string>('');
  const [formFrequency, setFormFrequency] = useState<DataSourcePollFrequency>('hourly');

  // Resolve an endpoint name from its id for subscription rows.
  const endpointsById = useMemo(() => {
    const map = new Map<string, AiDataSourceEndpoint>();
    endpoints.forEach((ep) => map.set(ep.id, ep));
    return map;
  }, [endpoints]);

  const loadData = useCallback(async () => {
    if (!dataSourceId) return;
    try {
      setLoading(true);
      const [eps, subs] = await Promise.all([
        dataSourcesApi.getEndpoints(dataSourceId),
        dataSourcesApi.getSubscriptions(dataSourceId),
      ]);
      setEndpoints(eps);
      setSubscriptions(subs);
    } catch (error) {
      logger.error('Failed to load data source subscriptions', { dataSourceId, error });
      addNotification({
        type: 'error',
        title: 'Error',
        message: 'Failed to load monitoring subscriptions. Please try again.',
      });
    } finally {
      setLoading(false);
    }
  }, [dataSourceId, addNotification]);

  useEffect(() => {
    loadData();
  }, [loadData]);

  const openCreateForm = () => {
    setFormEndpointId(endpoints[0]?.id ?? '');
    setFormFrequency('hourly');
    setFormOpen(true);
  };

  const closeForm = () => {
    setFormOpen(false);
    setFormEndpointId('');
    setFormFrequency('hourly');
  };

  const handleCreate = async () => {
    if (!formEndpointId) {
      addNotification({
        type: 'error',
        title: 'Validation',
        message: 'Select an endpoint to subscribe to.',
      });
      return;
    }
    try {
      setCreating(true);
      await dataSourcesApi.createSubscription(dataSourceId, {
        endpoint_id: formEndpointId,
        poll_frequency: formFrequency,
      });
      const endpointName = endpointsById.get(formEndpointId)?.name ?? 'endpoint';
      addNotification({
        type: 'success',
        title: 'Subscription Saved',
        message: `Now monitoring "${endpointName}" (${FREQUENCY_LABELS[formFrequency]}).`,
      });
      closeForm();
      await loadData();
    } catch (error) {
      logger.error('Failed to create data source subscription', {
        dataSourceId,
        endpointId: formEndpointId,
        error,
      });
      addNotification({
        type: 'error',
        title: 'Save Failed',
        message: error instanceof Error ? error.message : 'Failed to save subscription',
      });
    } finally {
      setCreating(false);
    }
  };

  const handleCancel = async (subscription: AiDataSourceSubscription) => {
    const endpointName = endpointsById.get(subscription.endpoint_id)?.name ?? 'this endpoint';
    if (!window.confirm(`Cancel the monitoring subscription for "${endpointName}"?`)) {
      return;
    }
    try {
      setCancelingId(subscription.id);
      await dataSourcesApi.deleteSubscription(dataSourceId, subscription.id);
      addNotification({
        type: 'success',
        title: 'Subscription Cancelled',
        message: `Stopped monitoring "${endpointName}".`,
      });
      await loadData();
    } catch (error) {
      logger.error('Failed to cancel data source subscription', {
        dataSourceId,
        subscriptionId: subscription.id,
        error,
      });
      addNotification({
        type: 'error',
        title: 'Cancel Failed',
        message: error instanceof Error ? error.message : 'Failed to cancel subscription',
      });
    } finally {
      setCancelingId(null);
    }
  };

  const renderForm = () => (
    <Card>
      <CardHeader
        title="New Subscription"
        action={
          <Button variant="ghost" size="sm" onClick={closeForm} disabled={creating}>
            <X className="h-4 w-4" />
          </Button>
        }
      />
      <CardContent className="space-y-4">
        <Select
          label="Endpoint"
          value={formEndpointId}
          onValueChange={(value) => setFormEndpointId(value)}
          options={endpoints.map((ep) => ({
            value: ep.id,
            label: `${ep.http_method} ${ep.name}`,
          }))}
        />
        <Select
          label="Poll Frequency"
          value={formFrequency}
          onValueChange={(value) => setFormFrequency(value as DataSourcePollFrequency)}
          options={POLL_FREQUENCIES.map((freq) => ({
            value: freq,
            label: FREQUENCY_LABELS[freq],
          }))}
        />
        <p className="text-xs text-theme-tertiary">
          The server-side monitor polls due subscriptions on this cadence, change-detects against
          the last fetched payload, refreshes the cache, and signals agents when the source changes.
        </p>
        <div className="flex items-center justify-end gap-2 pt-2">
          <Button variant="outline" onClick={closeForm} disabled={creating}>
            Cancel
          </Button>
          <Button variant="primary" onClick={handleCreate} loading={creating}>
            <Save className="h-4 w-4 mr-2" />
            Create Subscription
          </Button>
        </div>
      </CardContent>
    </Card>
  );

  const renderSubscriptionRow = (subscription: AiDataSourceSubscription) => {
    const endpoint = endpointsById.get(subscription.endpoint_id);
    const badge = statusBadge(subscription.status);
    return (
      <div
        key={subscription.id}
        className="flex items-start justify-between p-3 border border-theme rounded-lg gap-3"
      >
        <div className="min-w-0 space-y-1.5">
          <div className="flex items-center gap-2 flex-wrap">
            {endpoint && (
              <Badge variant="info" size="sm">{endpoint.http_method}</Badge>
            )}
            <p className="text-sm font-medium text-theme-primary truncate">
              {endpoint?.name ?? subscription.endpoint_id}
            </p>
            <Badge variant={badge.variant} size="sm">
              {subscription.status === 'error' && <AlertTriangle className="h-3 w-3 mr-1" />}
              {badge.label}
            </Badge>
            <Badge variant="secondary" size="sm">
              {FREQUENCY_LABELS[subscription.poll_frequency] ?? subscription.poll_frequency}
            </Badge>
          </div>

          <div className="flex items-center gap-4 text-xs text-theme-tertiary flex-wrap">
            <span className="flex items-center gap-1">
              <Clock className="h-3 w-3" />
              Last polled: {formatTimestamp(subscription.last_polled_at)}
            </span>
            <span className="flex items-center gap-1">
              <Timer className="h-3 w-3" />
              Next poll: {formatTimestamp(subscription.next_poll_at)}
            </span>
          </div>

          <div className="flex items-center gap-4 text-xs text-theme-tertiary flex-wrap">
            <span className="flex items-center gap-1" title={subscription.last_checksum ?? undefined}>
              <Fingerprint className="h-3 w-3" />
              Last change: <span className="font-mono">{shortChecksum(subscription.last_checksum)}</span>
            </span>
            {subscription.consecutive_failures > 0 && (
              <span className="flex items-center gap-1 text-theme-warning">
                <AlertTriangle className="h-3 w-3" />
                {subscription.consecutive_failures} consecutive failure
                {subscription.consecutive_failures === 1 ? '' : 's'}
              </span>
            )}
          </div>
        </div>

        {canManageSubscriptions && (
          <div className="shrink-0">
            <Button
              variant="danger"
              size="sm"
              onClick={() => handleCancel(subscription)}
              loading={cancelingId === subscription.id}
            >
              <Trash2 className="h-4 w-4" />
            </Button>
          </div>
        )}
      </div>
    );
  };

  // Per-endpoint stale-while-revalidate / stale-if-error windows. Surfaced so an
  // operator can see which endpoints serve stale-on-revalidate or stale-on-error
  // and the configured windows. Both null => SWR disabled for that endpoint.
  const renderSwrRow = (endpoint: AiDataSourceEndpoint) => {
    const swr = endpoint.stale_while_revalidate_seconds;
    const sie = endpoint.stale_if_error_seconds;
    const enabled = (swr ?? 0) > 0 || (sie ?? 0) > 0;
    return (
      <div
        key={endpoint.id}
        className="flex items-start justify-between p-3 border border-theme rounded-lg gap-3"
      >
        <div className="min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <Badge variant="info" size="sm">{endpoint.http_method}</Badge>
            <p className="text-sm font-medium text-theme-primary truncate">{endpoint.name}</p>
            {!enabled && (
              <Badge variant="outline" size="sm">SWR disabled</Badge>
            )}
          </div>
          {enabled && (
            <div className="mt-1 flex items-center gap-4 text-xs text-theme-tertiary flex-wrap">
              <span className="flex items-center gap-1">
                <RefreshCw className="h-3 w-3" />
                Stale-while-revalidate: {swr != null && swr > 0 ? `${swr}s` : 'off'}
              </span>
              <span className="flex items-center gap-1">
                <AlertTriangle className="h-3 w-3" />
                Stale-if-error: {sie != null && sie > 0 ? `${sie}s` : 'off'}
              </span>
            </div>
          )}
        </div>
      </div>
    );
  };

  if (loading) {
    return (
      <Card>
        <CardHeader title="Monitoring" />
        <CardContent>
          <LoadingSpinner className="py-8" />
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader
          title="Subscriptions"
          subtitle="Pull-based monitoring: the server polls each subscribed endpoint on its cadence and signals agents on change."
          action={
            !formOpen && canManageSubscriptions && endpoints.length > 0 ? (
              <Button variant="outline" onClick={openCreateForm}>
                <Plus className="h-4 w-4 mr-2" />
                Add Subscription
              </Button>
            ) : undefined
          }
        />
        <CardContent>
          {endpoints.length === 0 ? (
            <div className="text-center py-8">
              <Radar className="h-8 w-8 mx-auto text-theme-tertiary mb-2" />
              <p className="text-sm text-theme-tertiary">
                No endpoints configured. Subscriptions monitor a specific endpoint, so add an
                endpoint first.
              </p>
            </div>
          ) : subscriptions.length > 0 ? (
            <div className="space-y-3">{subscriptions.map(renderSubscriptionRow)}</div>
          ) : (
            <div className="text-center py-8">
              <Radar className="h-8 w-8 mx-auto text-theme-tertiary mb-2" />
              <p className="text-sm text-theme-tertiary">
                No active subscriptions for this data source.
              </p>
              {canManageSubscriptions && (
                <p className="text-sm text-theme-tertiary mt-1">
                  Click &quot;Add Subscription&quot; to start monitoring an endpoint.
                </p>
              )}
            </div>
          )}
        </CardContent>
      </Card>

      {formOpen && canManageSubscriptions && renderForm()}

      {endpoints.length > 0 && (
        <Card>
          <CardHeader
            title="Cache Freshness (SWR)"
            subtitle="Stale-while-revalidate and stale-if-error windows configured per endpoint."
          />
          <CardContent>
            <div className="space-y-3">{endpoints.map(renderSwrRow)}</div>
          </CardContent>
        </Card>
      )}
    </div>
  );
};
