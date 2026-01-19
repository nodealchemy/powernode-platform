import React, { useState, useEffect, useCallback } from 'react';
import { useSelector } from 'react-redux';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import {
  Plus,
  Activity,
  Globe,
  AlertTriangle,
  CheckCircle,
  Clock,
  RefreshCw,
  BarChart3
} from 'lucide-react';
import { RootState } from '@/shared/services';
import { hasPermissions } from '@/shared/utils/permissionUtils';
import {
  webhooksApi,
  WebhookEndpoint,
  WebhookStats as WebhookStatsType,
  WebhookFormData,
  DetailedWebhookStats
} from '@/features/devops/webhooks/services/webhooksApi';
import { WebhookModal } from '@/features/devops/webhooks/components/WebhookModal';
import { WebhookList } from '@/features/devops/webhooks/components/WebhookList';
import { WebhookDetails } from '@/features/devops/webhooks/components/WebhookDetails';
import { WebhookStats } from '@/features/devops/webhooks/components/WebhookStats';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { useNotifications } from '@/shared/hooks/useNotifications';

type ViewMode = 'list' | 'details' | 'stats';

const WebhookManagementPage: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  const { showNotification } = useNotifications();
  const { confirm, ConfirmationDialog } = useConfirmation();
  // WebSocket for real-time updates
  const { isConnected: _wsConnected } = usePageWebSocket({
    pageType: 'devops',
    onDataUpdate: () => {
      // Trigger data refresh if needed
    }
  });


  // Check webhook permissions (matching backend controller)
  const canReadWebhooks = hasPermissions(user, ['webhook.read']) || hasPermissions(user, ['webhook.create', 'webhook.update', 'webhook.delete']);
  const canCreateWebhooks = hasPermissions(user, ['webhook.create']);
  const canEditWebhooks = hasPermissions(user, ['webhook.update']);
  const canDeleteWebhooks = hasPermissions(user, ['webhook.delete']);

  // State
  const [viewMode, setViewMode] = useState<ViewMode>('list');
  const [webhooks, setWebhooks] = useState<WebhookEndpoint[]>([]);
  const [selectedWebhook, setSelectedWebhook] = useState<WebhookEndpoint | null>(null);
  const [stats, setStats] = useState<WebhookStatsType | null>(null);
  const [detailedStats, setDetailedStats] = useState<DetailedWebhookStats | null>(null);
  const [loading, setLoading] = useState(true);
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [showEditModal, setShowEditModal] = useState(false);
  const [pagination, setPagination] = useState({
    current_page: 1,
    per_page: 20,
    total_pages: 0,
    total_count: 0
  });

  // Filters
  const [filters, setFilters] = useState({
    status: 'all',
    search: ''
  });

  // Load webhooks
  const loadWebhooks = useCallback(async (page = 1) => {
    if (!canReadWebhooks) {
      showNotification('You do not have permission to view webhooks', 'error');
      setLoading(false);
      return;
    }

    setLoading(true);

    try {
      const response = await webhooksApi.getWebhooks(page, pagination.per_page);

      if (response.success && response.data) {
        setWebhooks(response.data.webhooks);
        setPagination(response.data.pagination);
        setStats(response.data.stats);
      } else {
        showNotification(response.error || 'Failed to load webhooks', 'error');
      }
    } catch (_error) {
      showNotification('An unexpected error occurred while loading webhooks', 'error');
    } finally {
      setLoading(false);
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pagination.per_page, canReadWebhooks]);

  // Load detailed stats
  const loadDetailedStats = useCallback(async () => {
    if (!canReadWebhooks) {
      return;
    }

    try {
      const response = await webhooksApi.getStats();
      if (response.success && response.data) {
        setDetailedStats(response.data);
      }
    } catch (_error) {
    }
  }, [canReadWebhooks]);

  // Initial load
  useEffect(() => {
    loadWebhooks();
  }, [loadWebhooks]);

  // Load detailed stats when viewing stats
  useEffect(() => {
    if (viewMode === 'stats') {
      loadDetailedStats();
    }
  }, [viewMode, loadDetailedStats]);

  // Handle webhook creation
  const handleCreateWebhook = async (webhookData: WebhookFormData) => {
    if (!canCreateWebhooks) {
      showNotification('You do not have permission to create webhooks', 'error');
      return;
    }

    try {
      const response = await webhooksApi.createWebhook(webhookData);

      if (response.success) {
        showNotification(response.message || 'Webhook created successfully', 'success');
        setShowCreateModal(false);
        loadWebhooks(pagination.current_page);
      } else {
        showNotification(response.error || 'Failed to create webhook', 'error');
      }
    } catch (_error) {
      showNotification('An unexpected error occurred while creating the webhook', 'error');
    }
  };

  const handleCreateModalSuccess = () => {
    setShowCreateModal(false);
    loadWebhooks(pagination.current_page);
  };

  // Handle webhook update
  const handleUpdateWebhook = async (webhookData: Partial<WebhookFormData>) => {
    if (!selectedWebhook) return;

    if (!canEditWebhooks) {
      showNotification('You do not have permission to edit webhooks', 'error');
      return;
    }

    try {
      const response = await webhooksApi.updateWebhook(selectedWebhook.id, webhookData);

      if (response.success) {
        showNotification(response.message || 'Webhook updated successfully', 'success');
        setShowEditModal(false);
        loadWebhooks(pagination.current_page);
        setSelectedWebhook(null);
      } else {
        showNotification(response.error || 'Failed to update webhook', 'error');
      }
    } catch (_error) {
      showNotification('An unexpected error occurred while updating the webhook', 'error');
    }
  };

  const handleEditModalSuccess = () => {
    setShowEditModal(false);
    setSelectedWebhook(null);
    loadWebhooks(pagination.current_page);
  };

  // Handle webhook deletion
  const handleDeleteWebhook = (webhookId: string) => {
    if (!canDeleteWebhooks) {
      showNotification('You do not have permission to delete webhooks', 'error');
      return;
    }

    confirm({
      title: 'Delete Webhook',
      message: 'Are you sure you want to delete this webhook? This action cannot be undone and may affect integrations.',
      confirmLabel: 'Delete',
      variant: 'danger',
      onConfirm: async () => {
        try {
          const response = await webhooksApi.deleteWebhook(webhookId);

          if (response.success) {
            showNotification(response.message || 'Webhook deleted successfully', 'success');
            loadWebhooks(pagination.current_page);
          } else {
            showNotification(response.error || 'Failed to delete webhook', 'error');
          }
        } catch (_error) {
          showNotification('An unexpected error occurred while deleting the webhook', 'error');
        }
      }
    });
  };

  // Handle webhook status toggle
  const handleToggleStatus = async (webhookId: string) => {
    if (!canEditWebhooks) {
      showNotification('You do not have permission to edit webhooks', 'error');
      return;
    }

    try {
      const response = await webhooksApi.toggleWebhookStatus(webhookId);

      if (response.success) {
        showNotification(response.message || 'Webhook status updated successfully', 'success');
        loadWebhooks(pagination.current_page);
      } else {
        showNotification(response.error || 'Failed to update webhook status', 'error');
      }
    } catch (_error) {
      showNotification('An unexpected error occurred while updating webhook status', 'error');
    }
  };

  // Handle retry failed deliveries
  const handleRetryFailed = async () => {
    if (!canEditWebhooks) {
      showNotification('You do not have permission to retry webhook deliveries', 'error');
      return;
    }

    try {
      const response = await webhooksApi.retryFailed();

      if (response.success && response.data) {
        showNotification(`Queued ${response.data.retry_count} failed deliveries for retry`, 'success');
      } else {
        showNotification(response.error || 'Failed to retry failed deliveries', 'error');
      }
    } catch (_error) {
      showNotification('An unexpected error occurred while retrying failed deliveries', 'error');
    }
  };

  // Handle pagination
  const handlePageChange = (page: number) => {
    loadWebhooks(page);
  };

  // Handle view selection
  const handleViewWebhook = (webhook: WebhookEndpoint) => {
    setSelectedWebhook(webhook);
    setViewMode('details');
  };

  const handleEditWebhook = (webhook: WebhookEndpoint) => {
    setSelectedWebhook(webhook);
    setShowEditModal(true);
  };

  // Render stats overview
  const renderStatsOverview = () => {
    if (!stats) return null;

    return (
      <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-4">
        <div className="bg-theme-background rounded-lg p-4 border border-theme">
          <div className="flex items-center gap-3">
            <Globe className="w-8 h-8 text-theme-interactive-primary" />
            <div>
              <p className="text-2xl font-bold text-theme-primary">{stats.total_endpoints}</p>
              <p className="text-sm text-theme-secondary">Total Endpoints</p>
            </div>
          </div>
        </div>

        <div className="bg-theme-background rounded-lg p-4 border border-theme">
          <div className="flex items-center gap-3">
            <CheckCircle className="w-8 h-8 text-theme-success" />
            <div>
              <p className="text-2xl font-bold text-theme-primary">{stats.active_endpoints}</p>
              <p className="text-sm text-theme-secondary">Active</p>
            </div>
          </div>
        </div>

        <div className="bg-theme-background rounded-lg p-4 border border-theme">
          <div className="flex items-center gap-3">
            <Clock className="w-8 h-8 text-theme-tertiary" />
            <div>
              <p className="text-2xl font-bold text-theme-primary">{stats.inactive_endpoints}</p>
              <p className="text-sm text-theme-secondary">Inactive</p>
            </div>
          </div>
        </div>

        <div className="bg-theme-background rounded-lg p-4 border border-theme">
          <div className="flex items-center gap-3">
            <Activity className="w-8 h-8 text-theme-interactive-primary" />
            <div>
              <p className="text-2xl font-bold text-theme-primary">{stats.total_deliveries_today}</p>
              <p className="text-sm text-theme-secondary">Deliveries Today</p>
            </div>
          </div>
        </div>

        <div className="bg-theme-background rounded-lg p-4 border border-theme">
          <div className="flex items-center gap-3">
            <CheckCircle className="w-8 h-8 text-theme-success" />
            <div>
              <p className="text-2xl font-bold text-theme-primary">{stats.successful_deliveries_today}</p>
              <p className="text-sm text-theme-secondary">Successful</p>
            </div>
          </div>
        </div>

        <div className="bg-theme-background rounded-lg p-4 border border-theme">
          <div className="flex items-center gap-3">
            <AlertTriangle className="w-8 h-8 text-theme-error" />
            <div>
              <p className="text-2xl font-bold text-theme-primary">{stats.failed_deliveries_today}</p>
              <p className="text-sm text-theme-secondary">Failed</p>
            </div>
          </div>
        </div>
      </div>
    );
  };

  // Get page actions based on current view mode
  const getPageActions = (): PageAction[] => {
    const actions: PageAction[] = [];

    if (viewMode === 'list') {
      // Base actions for list view
      actions.push({
        id: 'refresh',
        label: 'Refresh',
        onClick: () => loadWebhooks(pagination.current_page),
        variant: 'secondary',
        icon: RefreshCw,
        disabled: loading
      });

      // Retry failed action if there are failed deliveries
      if (stats && stats.failed_deliveries_today > 0) {
        actions.push({
          id: 'retry-failed',
          label: `Retry Failed (${stats.failed_deliveries_today})`,
          onClick: handleRetryFailed,
          variant: 'warning',
          icon: RefreshCw
        });
      }

      // Add webhook action - only show if user has create permission
      if (canCreateWebhooks) {
        actions.push({
          id: 'add-webhook',
          label: 'Add Webhook',
          onClick: () => setShowCreateModal(true),
          variant: 'primary',
          icon: Plus
        });
      }
    } else {
      // Back action for non-list views
      actions.push({
        id: 'back',
        label: 'Back to Webhooks',
        onClick: () => setViewMode('list'),
        variant: 'secondary'
      });
    }

    // Statistics action - available in all modes
    actions.push({
      id: 'statistics',
      label: 'Statistics',
      onClick: () => setViewMode('stats'),
      variant: viewMode === 'stats' ? 'primary' : 'secondary',
      icon: BarChart3
    });

    return actions;
  };

  // Get breadcrumbs
  const getBreadcrumbs = () => [
    { label: 'Dashboard', href: '/app', icon: '🏠' },
    { label: 'DevOps', href: '/app/devops', icon: '🔧' },
    { label: 'Webhooks', icon: '🔗' }
  ];

  // Get page description
  const getPageDescription = () => {
    if (viewMode === 'details') return 'View webhook details and activity';
    if (viewMode === 'stats') return 'Webhook delivery statistics and analytics';
    return 'Configure and monitor webhook endpoints for real-time notifications';
  };

  // Get page title
  const getPageTitle = () => {
    if (viewMode === 'details') return 'Webhook Details';
    if (viewMode === 'stats') return 'Webhook Statistics';
    return 'Webhook Management';
  };

  // Main render
  return (
    <PageContainer
      title={getPageTitle()}
      description={getPageDescription()}
      breadcrumbs={getBreadcrumbs()}
      actions={getPageActions()}
    >
      {/* Stats overview when in list mode */}
      {viewMode === 'list' && (
        <div className="bg-theme-surface rounded-lg p-6 mb-6">
          {renderStatsOverview()}
        </div>
      )}

      {/* Loading State */}
      {loading && viewMode === 'list' && (
        <div className="flex justify-center py-12">
          <LoadingSpinner size="lg" />
        </div>
      )}

      {/* Content based on view mode */}
      {!loading && (
        <>
          {viewMode === 'list' && (
            <WebhookList
              webhooks={webhooks}
              pagination={pagination}
              onPageChange={handlePageChange}
              onView={handleViewWebhook}
              onEdit={canEditWebhooks ? handleEditWebhook : undefined}
              onDelete={canDeleteWebhooks ? handleDeleteWebhook : undefined}
              onToggleStatus={canEditWebhooks ? handleToggleStatus : undefined}
              filters={filters}
              onFiltersChange={setFilters}
            />
          )}


          {viewMode === 'details' && selectedWebhook && (
            <div className="bg-theme-surface rounded-lg p-6">
              <WebhookDetails
                webhook={selectedWebhook}
                onEdit={canEditWebhooks ? () => handleEditWebhook(selectedWebhook) : undefined}
                onDelete={canDeleteWebhooks ? () => handleDeleteWebhook(selectedWebhook.id) : undefined}
                onToggleStatus={canEditWebhooks ? () => handleToggleStatus(selectedWebhook.id) : undefined}
              />
            </div>
          )}

          {viewMode === 'stats' && (
            <div className="bg-theme-surface rounded-lg p-6">
              <WebhookStats
                stats={stats}
                detailedStats={detailedStats}
                loading={!detailedStats}
              />
            </div>
          )}
        </>
      )}

      {/* Webhook Creation Modal */}
      <WebhookModal
        isOpen={showCreateModal}
        onClose={() => setShowCreateModal(false)}
        onSuccess={handleCreateModalSuccess}
        onSubmit={handleCreateWebhook}
        mode="create"
      />

      {/* Webhook Edit Modal */}
      <WebhookModal
        isOpen={showEditModal}
        onClose={() => {
          setShowEditModal(false);
          setSelectedWebhook(null);
        }}
        onSuccess={handleEditModalSuccess}
        onSubmit={(data) => handleUpdateWebhook(data)}
        webhook={selectedWebhook || undefined}
        mode="edit"
      />
      {ConfirmationDialog}
    </PageContainer>
  );
};

export default WebhookManagementPage;