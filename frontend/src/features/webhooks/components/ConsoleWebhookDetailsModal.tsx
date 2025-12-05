import React, { useState, useEffect, useCallback } from 'react';
import { Button } from '@/shared/components/ui/Button';
import { FormField } from '@/shared/components/ui/FormField';
import {
  Activity, XCircle, Copy, Zap, TrendingUp, RefreshCw
} from 'lucide-react';
import { webhooksApi, DetailedWebhookEndpoint, WebhookDelivery } from '@/features/webhooks/services/webhooksApi';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';

export interface ConsoleWebhookDetailsModalProps {
  webhook: DetailedWebhookEndpoint | null;
  isOpen: boolean;
  onClose: () => void;
  showDeliveryHistory?: boolean;
}

export const ConsoleWebhookDetailsModal: React.FC<ConsoleWebhookDetailsModalProps> = ({
  webhook,
  isOpen,
  onClose,
  showDeliveryHistory = true
}) => {
  const [activeTab, setActiveTab] = useState<'details' | 'deliveries'>('details');
  const [deliveries, setDeliveries] = useState<WebhookDelivery[]>([]);
  const [deliveriesLoading, setDeliveriesLoading] = useState(false);

  const { showNotification } = useNotifications();

  // Fixed: Memoized date formatting functions to prevent excessive Date object creation
  const formatCreatedAt = useCallback((timestamp: string) => {
    return new Date(timestamp).toLocaleString();
  }, []);

  const formatRetryTime = useCallback((timestamp: string) => {
    return new Date(timestamp).toLocaleString();
  }, []);

  useEffect(() => {
    if (isOpen && webhook && activeTab === 'deliveries') {
      loadDeliveries();
    }
  }, [isOpen, webhook, activeTab]);

  const loadDeliveries = async () => {
    if (!webhook) return;

    try {
      setDeliveriesLoading(true);
      const response = await webhooksApi.getDeliveryHistory(webhook.id);
      if (response.success && response.data) {
        setDeliveries(response.data.deliveries);
      }
    } catch (error) {
      showNotification('Failed to load delivery history', 'error');
    } finally {
      setDeliveriesLoading(false);
    }
  };

  const copySecretToken = async () => {
    if (!webhook?.secret_token) return;

    try {
      await navigator.clipboard.writeText(webhook.secret_token);
      showNotification('Secret token copied to clipboard', 'success');
    } catch (error) {
      showNotification('Failed to copy secret token', 'error');
    }
  };

  if (!isOpen || !webhook) return null;

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4 z-50">
      <div className="bg-theme-surface rounded-lg shadow-xl max-w-4xl w-full max-h-[90vh] overflow-hidden">
        <div className="px-6 py-4 border-b border-theme flex items-center justify-between">
          <div>
            <h3 className="text-lg font-semibold text-theme-primary">{webhooksApi.formatUrl(webhook.url, 60)}</h3>
            <p className="text-sm text-theme-secondary">{webhook.description || 'No description'}</p>
          </div>
          <Button onClick={onClose} variant="outline">
            <XCircle className="w-5 h-5" />
          </Button>
        </div>

        {/* Tabs */}
        <div className="px-6 border-b border-theme">
          <div className="flex space-x-8">
            <Button variant="outline" onClick={() => setActiveTab('details')}
              className={`py-2 px-1 border-b-2 font-medium text-sm ${
                activeTab === 'details'
                  ? 'border-theme-interactive-primary text-theme-interactive-primary'
                  : 'border-transparent text-theme-secondary hover:text-theme-primary'
              }`}
            >
              Details
            </Button>
            {showDeliveryHistory && (
              <Button variant="outline" onClick={() => setActiveTab('deliveries')}
                className={`py-2 px-1 border-b-2 font-medium text-sm ${
                  activeTab === 'deliveries'
                    ? 'border-theme-interactive-primary text-theme-interactive-primary'
                    : 'border-transparent text-theme-secondary hover:text-theme-primary'
                }`}
              >
                Delivery History
              </Button>
            )}
          </div>
        </div>

        <div className="overflow-auto max-h-[calc(90vh-200px)] p-6">
          {activeTab === 'details' && (
            <div className="space-y-6">
              {/* Status and Stats */}
              <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div className="bg-theme-background p-4 rounded-lg">
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="text-sm text-theme-secondary">Status</p>
                      <p className={`font-semibold ${webhook.status === 'active' ? 'text-theme-success' : 'text-theme-warning'}`}>
                        {webhook.status.charAt(0).toUpperCase() + webhook.status.slice(1)}
                      </p>
                    </div>
                    <Activity className={`w-8 h-8 ${webhook.status === 'active' ? 'text-theme-success' : 'text-theme-warning'}`} />
                  </div>
                </div>

                <div className="bg-theme-background p-4 rounded-lg">
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="text-sm text-theme-secondary">Success Rate</p>
                      <p className="text-lg font-semibold text-theme-primary">
                        {webhooksApi.getSuccessRate(webhook)}%
                      </p>
                    </div>
                    <TrendingUp className="w-8 h-8 text-theme-info" />
                  </div>
                </div>

                <div className="bg-theme-background p-4 rounded-lg">
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="text-sm text-theme-secondary">Total Deliveries</p>
                      <p className="text-lg font-semibold text-theme-primary">
                        {webhook.delivery_stats.total_deliveries}
                      </p>
                    </div>
                    <Zap className="w-8 h-8 text-theme-interactive-primary" />
                  </div>
                </div>
              </div>

              {/* Configuration */}
              <div className="space-y-4">
                <h4 className="font-medium text-theme-primary">Configuration</h4>

                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div>
                    <label className="block text-sm text-theme-secondary mb-1">URL</label>
                    <p className="text-theme-primary font-mono text-sm bg-theme-background p-2 rounded border">
                      {webhook.url}
                    </p>
                  </div>

                  <div>
                    <label className="block text-sm text-theme-secondary mb-1">Content Type</label>
                    <p className="text-theme-primary">{webhook.content_type}</p>
                  </div>

                  <div>
                    <label className="block text-sm text-theme-secondary mb-1">Timeout</label>
                    <p className="text-theme-primary">{webhook.timeout_seconds}s</p>
                  </div>

                  <div>
                    <label className="block text-sm text-theme-secondary mb-1">Retry Limit</label>
                    <p className="text-theme-primary">{webhook.retry_limit}</p>
                  </div>
                </div>

                <div className="flex items-center gap-2">
                  <FormField
                    label="Secret Token"
                    type="password"
                    value={webhook.secret_token}
                    onChange={() => {}}
                    disabled
                  />
                  <Button onClick={copySecretToken} variant="outline">
                    <Copy className="w-4 h-4" />
                    Copy
                  </Button>
                </div>

                <div>
                  <label className="block text-sm text-theme-secondary mb-2">Event Types</label>
                  <div className="flex flex-wrap gap-2">
                    {webhook.event_types.map((eventType) => (
                      <span key={eventType} className="px-2 py-1 bg-theme-interactive-primary bg-opacity-10 text-theme-interactive-primary text-xs rounded">
                        {webhooksApi.formatEventType(eventType)}
                      </span>
                    ))}
                  </div>
                </div>
              </div>
            </div>
          )}

          {showDeliveryHistory && activeTab === 'deliveries' && (
            <div className="space-y-4">
              <div className="flex items-center justify-between">
                <h4 className="font-medium text-theme-primary">Recent Deliveries</h4>
                <Button onClick={loadDeliveries} disabled={deliveriesLoading} variant="outline">
                  <RefreshCw className={`w-4 h-4 ${deliveriesLoading ? 'animate-spin' : ''}`} />
                  Refresh
                </Button>
              </div>

              {deliveriesLoading ? (
                <div className="flex justify-center py-8">
                  <LoadingSpinner size="lg" />
                </div>
              ) : deliveries.length === 0 ? (
                <div className="text-center py-8">
                  <Activity className="w-12 h-12 text-theme-secondary mx-auto mb-4" />
                  <p className="text-theme-secondary">No deliveries found</p>
                </div>
              ) : (
                <div className="space-y-3">
                  {deliveries.map((delivery) => (
                    <div key={delivery.id} className="bg-theme-background p-4 rounded-lg border border-theme">
                      <div className="flex items-center justify-between">
                        <div className="flex items-center gap-3">
                          <span className={`px-2 py-1 text-xs rounded-full ${webhooksApi.getDeliveryStatusColor(delivery.status)}`}>
                            {delivery.status.replace('_', ' ').toUpperCase()}
                          </span>
                          <span className="text-sm text-theme-secondary">{webhooksApi.formatEventType(delivery.event_type)}</span>
                        </div>
                        <div className="text-right text-sm text-theme-secondary">
                          <div>{formatCreatedAt(delivery.created_at)}</div>
                          {delivery.response_time_ms && (
                            <div>{delivery.response_time_ms}ms</div>
                          )}
                        </div>
                      </div>

                      {delivery.error_message && (
                        <div className="mt-2 text-sm text-theme-error bg-theme-error-background p-2 rounded">
                          {delivery.error_message}
                        </div>
                      )}

                      <div className="mt-2 flex items-center gap-4 text-xs text-theme-secondary">
                        <span>Attempt {delivery.attempt_count}</span>
                        {delivery.http_status && <span>HTTP {delivery.http_status}</span>}
                        {delivery.next_retry_at && (
                          <span>Next retry: {formatRetryTime(delivery.next_retry_at)}</span>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}
        </div>

        <div className="px-6 py-4 border-t border-theme flex justify-end">
          <Button onClick={onClose} variant="outline">
            Close
          </Button>
        </div>
      </div>
    </div>
  );
};
