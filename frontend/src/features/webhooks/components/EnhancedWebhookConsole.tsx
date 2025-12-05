import React, { useState, useEffect, useMemo, useCallback } from 'react';
import { Button } from '@/shared/components/ui/Button';
import {
  Webhook, Plus, Play, Pause, Trash2,
  Activity, CheckCircle,
  Eye, RotateCcw, TrendingUp, Search
} from 'lucide-react';
import { webhooksApi, WebhookEndpoint, DetailedWebhookEndpoint, DetailedWebhookStats } from '@/features/webhooks/services/webhooksApi';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { ConsoleCreateWebhookModal } from './ConsoleCreateWebhookModal';
import { ConsoleWebhookDetailsModal } from './ConsoleWebhookDetailsModal';

interface EnhancedWebhookConsoleProps {
  showStats?: boolean;
  showDeliveryHistory?: boolean;
}

export const EnhancedWebhookConsole: React.FC<EnhancedWebhookConsoleProps> = ({
  showStats = true,
  showDeliveryHistory = true
}) => {
  const [webhooks, setWebhooks] = useState<WebhookEndpoint[]>([]);
  const [stats, setStats] = useState<DetailedWebhookStats | null>(null);
  const [loading, setLoading] = useState(true);
  const [actionLoading, setActionLoading] = useState<{ [key: string]: boolean }>({});
  const [currentPage, setCurrentPage] = useState(1);
  const [totalPages, setTotalPages] = useState(1);
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedWebhook, setSelectedWebhook] = useState<DetailedWebhookEndpoint | null>(null);
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [showDetailsModal, setShowDetailsModal] = useState(false);

  const { showNotification } = useNotifications();
  const perPage = 20;

  // Fixed: Memoized date formatting function to prevent excessive Date object creation
  const formatLastDeliveryInConsole = useCallback((timestamp: string) => {
    return new Date(timestamp).toLocaleDateString();
  }, []);

  useEffect(() => {
    loadWebhooks();
    if (showStats) {
      loadStats();
    }
  }, [currentPage]);

  const loadWebhooks = async () => {
    try {
      setLoading(true);
      const response = await webhooksApi.getWebhooks(currentPage, perPage);

      if (response.success) {
        setWebhooks(response.data.webhooks);
        setTotalPages(response.data.pagination.total_pages);
      } else {
        showNotification(response.error || 'Failed to load webhooks', 'error');
      }
    } catch (error: unknown) {
      showNotification('Failed to load webhooks', 'error');
    } finally {
      setLoading(false);
    }
  };

  const loadStats = async () => {
    try {
      const response = await webhooksApi.getStats();
      if (response.success && response.data) {
        setStats(response.data);
      }
    } catch (error) {
      // Error handled silently - stats are optional
    }
  };

  const handleAction = async (action: string, webhookId: string) => {
    try {
      setActionLoading(prev => ({ ...prev, [webhookId]: true }));
      let response;

      switch (action) {
        case 'toggle':
          response = await webhooksApi.toggleWebhookStatus(webhookId);
          break;
        case 'test':
          response = await webhooksApi.testWebhook(webhookId);
          break;
        case 'delete':
          if (!window.confirm('Are you sure you want to delete this webhook? This cannot be undone.')) {
            return;
          }
          response = await webhooksApi.deleteWebhook(webhookId);
          break;
        default:
          throw new Error('Unknown action');
      }

      if (response.success) {
        showNotification(response.message || 'Action completed successfully', 'success');
        await loadWebhooks();
        if (showStats) await loadStats();
      } else {
        showNotification(response.error || 'Action failed', 'error');
      }
    } catch (error: unknown) {
      showNotification('Action failed', 'error');
    } finally {
      setActionLoading(prev => ({ ...prev, [webhookId]: false }));
    }
  };

  const handleViewDetails = async (webhook: WebhookEndpoint) => {
    try {
      const response = await webhooksApi.getWebhook(webhook.id);
      if (response.success && response.data) {
        setSelectedWebhook(response.data);
        setShowDetailsModal(true);
      } else {
        showNotification('Failed to load webhook details', 'error');
      }
    } catch (error) {
      showNotification('Failed to load webhook details', 'error');
    }
  };

  const handleRetryFailed = async () => {
    try {
      const response = await webhooksApi.retryFailed();
      if (response.success && response.data) {
        showNotification(`Retrying ${response.data.retry_count} failed deliveries`, 'success');
        await loadWebhooks();
        if (showStats) await loadStats();
      } else {
        showNotification(response.error || 'Failed to retry failed deliveries', 'error');
      }
    } catch (error) {
      showNotification('Failed to retry failed deliveries', 'error');
    }
  };

  // Fixed: Memoized webhook filtering to prevent expensive operations on every render
  const filteredWebhooks = useMemo(() => {
    if (searchTerm === '') return webhooks;

    const lowerSearchTerm = searchTerm.toLowerCase();
    return webhooks.filter(webhook =>
      webhook.url.toLowerCase().includes(lowerSearchTerm) ||
      webhook.description?.toLowerCase().includes(lowerSearchTerm) ||
      webhook.event_types.some(event => event.toLowerCase().includes(lowerSearchTerm))
    );
  }, [webhooks, searchTerm]);

  return (
    <div className="space-y-6">
      {/* Stats Cards */}
      {showStats && stats && (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          <div className="bg-theme-surface rounded-lg border border-theme p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-secondary">Total Endpoints</p>
                <p className="text-2xl font-semibold text-theme-primary">{stats.total_endpoints}</p>
              </div>
              <Webhook className="w-8 h-8 text-theme-secondary" />
            </div>
          </div>

          <div className="bg-theme-surface rounded-lg border border-theme p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-secondary">Active</p>
                <p className="text-2xl font-semibold text-theme-success">{stats.active_endpoints}</p>
              </div>
              <CheckCircle className="w-8 h-8 text-theme-success" />
            </div>
          </div>

          <div className="bg-theme-surface rounded-lg border border-theme p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-secondary">Deliveries Today</p>
                <p className="text-2xl font-semibold text-theme-primary">{stats.total_deliveries_today}</p>
              </div>
              <Activity className="w-8 h-8 text-theme-info" />
            </div>
          </div>

          <div className="bg-theme-surface rounded-lg border border-theme p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-secondary">Success Rate</p>
                <p className="text-2xl font-semibold text-theme-success">
                  {stats.total_deliveries_today > 0 ? Math.round((stats.successful_deliveries_today / stats.total_deliveries_today) * 100) : 0}%
                </p>
              </div>
              <TrendingUp className="w-8 h-8 text-theme-success" />
            </div>
          </div>
        </div>
      )}

      {/* Header and Controls */}
      <div className="flex flex-col sm:flex-row gap-4 justify-between">
        <div>
          <h3 className="text-lg font-semibold text-theme-primary">Webhook Endpoints</h3>
          <p className="text-sm text-theme-secondary">
            Manage webhook endpoints for real-time event notifications
          </p>
        </div>

        <div className="flex items-center gap-2">
          {/* Search */}
          <div className="relative">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 w-4 h-4 text-theme-secondary" />
            <input
              type="text"
              placeholder="Search webhooks..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="pl-10 pr-4 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
            />
          </div>

          {/* Retry Failed Button */}
          {stats && stats.failed_deliveries_today > 0 && (
            <Button onClick={handleRetryFailed} variant="outline">
              <RotateCcw className="w-4 h-4" />
              Retry Failed
            </Button>
          )}

          <Button variant="outline" onClick={() => setShowCreateModal(true)}
            className="px-4 py-2 bg-theme-interactive-primary text-white rounded-md hover:bg-theme-interactive-primary-hover transition-colors flex items-center gap-2"
          >
            <Plus className="w-4 h-4" />
            Create Webhook
          </Button>
        </div>
      </div>

      {/* Webhooks Table */}
      <div className="bg-theme-surface rounded-lg border border-theme overflow-hidden">
        {loading ? (
          <div className="flex items-center justify-center py-12">
            <LoadingSpinner size="lg" />
          </div>
        ) : filteredWebhooks.length === 0 ? (
          <div className="text-center py-12">
            <Webhook className="w-12 h-12 text-theme-secondary mx-auto mb-4" />
            <h4 className="text-lg font-medium text-theme-primary mb-2">No Webhooks Found</h4>
            <p className="text-theme-secondary mb-4">
              {searchTerm ? 'No webhooks match your search criteria.' : 'Create your first webhook to get started with real-time notifications.'}
            </p>
            {!searchTerm && (
              <Button variant="outline" onClick={() => setShowCreateModal(true)}
                className="px-4 py-2 bg-theme-interactive-primary text-white rounded-md hover:bg-theme-interactive-primary-hover transition-colors"
              >
                Create Your First Webhook
              </Button>
            )}
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead className="bg-theme-background">
                <tr>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    Endpoint
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    Events
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    Status
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    Success Rate
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    Last Delivery
                  </th>
                  <th className="px-6 py-3 text-right text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody className="divide-y divide-theme">
                {filteredWebhooks.map((webhook) => (
                  <tr key={webhook.id} className="hover:bg-theme-background transition-colors">
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div>
                        <div className="text-sm font-medium text-theme-primary">
                          {webhooksApi.formatUrl(webhook.url)}
                        </div>
                        {webhook.description && (
                          <div className="text-sm text-theme-secondary">
                            {webhook.description}
                          </div>
                        )}
                      </div>
                    </td>

                    <td className="px-6 py-4">
                      <div className="flex flex-wrap gap-1">
                        {webhook.event_types.slice(0, 3).map((eventType) => (
                          <span key={eventType} className="inline-flex px-2 py-1 text-xs rounded bg-theme-interactive-primary bg-opacity-10 text-theme-interactive-primary">
                            {eventType.split('.')[0]}
                          </span>
                        ))}
                        {webhook.event_types.length > 3 && (
                          <span className="inline-flex px-2 py-1 text-xs rounded bg-theme-surface text-theme-secondary">
                            +{webhook.event_types.length - 3}
                          </span>
                        )}
                      </div>
                    </td>

                    <td className="px-6 py-4 whitespace-nowrap">
                      <span className={`inline-flex px-2 py-1 text-xs font-semibold rounded-full ${webhooksApi.getStatusColor(webhook.status)}`}>
                        {webhook.status.charAt(0).toUpperCase() + webhook.status.slice(1)}
                      </span>
                    </td>

                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="flex items-center">
                        <span className="text-sm text-theme-primary">
                          {webhooksApi.getSuccessRate(webhook)}%
                        </span>
                        <div className="ml-2 w-16 bg-theme-background rounded-full h-2">
                          <div
                            className="bg-theme-success h-2 rounded-full"
                            style={{ width: `${webhooksApi.getSuccessRate(webhook)}%` }}
                          ></div>
                        </div>
                      </div>
                    </td>

                    <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-secondary">
                      {webhook.last_delivery_at
                        ? formatLastDeliveryInConsole(webhook.last_delivery_at)
                        : 'Never'
                      }
                    </td>

                    <td className="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                      <div className="flex items-center justify-end gap-2">
                        <Button variant="outline" onClick={() => handleViewDetails(webhook)}
                          className="p-2 text-theme-secondary hover:text-theme-primary transition-colors"
                          title="View Details"
                        >
                          <Eye className="w-4 h-4" />
                        </Button>

                        <Button variant="outline" onClick={() => handleAction('test', webhook.id)}
                          disabled={actionLoading[webhook.id]}
                          className="p-2 text-theme-secondary hover:text-theme-primary transition-colors disabled:opacity-50"
                          title="Test Webhook"
                        >
                          {actionLoading[webhook.id] ? (
                            <LoadingSpinner size="sm" />
                          ) : (
                            <Play className="w-4 h-4" />
                          )}
                        </Button>

                        <Button variant="outline" onClick={() => handleAction('toggle', webhook.id)}
                          disabled={actionLoading[webhook.id]}
                          className="p-2 text-theme-secondary hover:text-theme-primary transition-colors disabled:opacity-50"
                          title={webhook.status === 'active' ? 'Deactivate' : 'Activate'}
                        >
                          {webhook.status === 'active' ? (
                            <Pause className="w-4 h-4" />
                          ) : (
                            <Play className="w-4 h-4" />
                          )}
                        </Button>

                        <Button variant="outline" onClick={() => handleAction('delete', webhook.id)}
                          disabled={actionLoading[webhook.id]}
                          className="p-2 text-theme-error hover:text-theme-error-hover transition-colors disabled:opacity-50"
                          title="Delete"
                        >
                          <Trash2 className="w-4 h-4" />
                        </Button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Pagination */}
      {totalPages > 1 && (
        <div className="flex items-center justify-between">
          <div className="text-sm text-theme-secondary">
            Page {currentPage} of {totalPages}
          </div>
          <div className="flex gap-2">
            <Button variant="outline" onClick={() => setCurrentPage(prev => Math.max(1, prev - 1))}
              disabled={currentPage === 1}
              className="px-3 py-2 border border-theme rounded-md text-theme-primary hover:bg-theme-surface disabled:opacity-50 disabled:cursor-not-allowed"
            >
              Previous
            </Button>
            <Button variant="outline" onClick={() => setCurrentPage(prev => Math.min(totalPages, prev + 1))}
              disabled={currentPage === totalPages}
              className="px-3 py-2 border border-theme rounded-md text-theme-primary hover:bg-theme-surface disabled:opacity-50 disabled:cursor-not-allowed"
            >
              Next
            </Button>
          </div>
        </div>
      )}

      {/* Modals */}
      <ConsoleCreateWebhookModal
        isOpen={showCreateModal}
        onClose={() => setShowCreateModal(false)}
        onWebhookCreated={() => {
          loadWebhooks();
          if (showStats) loadStats();
        }}
      />

      <ConsoleWebhookDetailsModal
        webhook={selectedWebhook}
        isOpen={showDetailsModal}
        onClose={() => {
          setShowDetailsModal(false);
          setSelectedWebhook(null);
        }}
        showDeliveryHistory={showDeliveryHistory}
      />
    </div>
  );
};
