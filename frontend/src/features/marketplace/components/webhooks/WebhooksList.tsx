import React, { useState, useEffect } from 'react';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { WebhookCard } from './WebhookCard';
import { WebhookFormModal } from './WebhookFormModal';
import { WebhookTestModal } from './WebhookTestModal';
import { WebhookAnalyticsModal } from './WebhookAnalyticsModal';
import { WebhookDeliveriesModal } from './WebhookDeliveriesModal';
import { useAppWebhooks } from '../../hooks/useWebhooks';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { AppWebhook, AppWebhookFilters } from '../../types';
import { Plus, Search, Filter, RefreshCw } from 'lucide-react';

interface WebhooksListProps {
  appId: string;
  onWebhookAction?: (action: string, webhookId: string) => void;
  showCreateButton?: boolean;
  filters?: AppWebhookFilters;
}

export const WebhooksList: React.FC<WebhooksListProps> = ({ 
  appId,
  onWebhookAction,
  showCreateButton = true,
  filters = {}
}) => {
  const [searchTerm, setSearchTerm] = useState(filters.search || '');
  const [eventTypeFilter, setEventTypeFilter] = useState(filters.event_type || '');
  const [activeFilter, setActiveFilter] = useState<boolean | undefined>(filters.active);
  const [currentPage, setCurrentPage] = useState(filters.page || 1);
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [selectedWebhook, setSelectedWebhook] = useState<AppWebhook | null>(null);
  const [modalType, setModalType] = useState<'edit' | 'test' | 'analytics' | 'deliveries' | null>(null);

  const { showNotification } = useNotifications();
  const { confirm, ConfirmationDialog } = useConfirmation();

  // Combine local filters with prop filters
  const combinedFilters: AppWebhookFilters = {
    ...filters,
    search: searchTerm || filters.search,
    event_type: eventTypeFilter || filters.event_type,
    active: activeFilter !== undefined ? activeFilter : filters.active,
    page: currentPage,
    per_page: 20
  };

  const {
    webhooks,
    loading,
    error,
    pagination,
    activateWebhook,
    deactivateWebhook,
    regenerateSecret,
    refresh
  } = useAppWebhooks(appId, combinedFilters);

  // Listen for external webhook action events
  useEffect(() => {
    const handleWebhookAction = (event: CustomEvent) => {
      const { action } = event.detail;
      
      switch (action) {
        case 'create':
          setShowCreateModal(true);
          break;
        case 'refresh':
          refresh();
          break;
        default:
          break;
      }
    };

    window.addEventListener('webhook-action', handleWebhookAction as EventListener);
    return () => {
      window.removeEventListener('webhook-action', handleWebhookAction as EventListener);
    };
  }, [refresh]);

  const handleCreateWebhook = () => {
    setSelectedWebhook(null);
    setModalType(null);
    setShowCreateModal(true);
  };

  const handleEditWebhook = (webhook: AppWebhook) => {
    setSelectedWebhook(webhook);
    setModalType('edit');
    setShowCreateModal(true);
  };

  const handleTestWebhook = (webhook: AppWebhook) => {
    setSelectedWebhook(webhook);
    setModalType('test');
  };

  const handleViewAnalytics = (webhook: AppWebhook) => {
    setSelectedWebhook(webhook);
    setModalType('analytics');
  };

  const handleViewDeliveries = (webhook: AppWebhook) => {
    setSelectedWebhook(webhook);
    setModalType('deliveries');
  };

  const handleToggleStatus = async (webhook: AppWebhook) => {
    try {
      if (webhook.is_active) {
        await deactivateWebhook(webhook.id);
        showNotification(`Webhook "${webhook.name}" deactivated`, 'success');
      } else {
        await activateWebhook(webhook.id);
        showNotification(`Webhook "${webhook.name}" activated`, 'success');
      }
      onWebhookAction?.('toggle-status', webhook.id);
    } catch (error: unknown) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error occurred';
      showNotification(`Failed to toggle webhook status: ${errorMessage}`, 'error');
    }
  };

  const handleRegenerateSecret = async (webhook: AppWebhook) => {
    confirm({
      title: 'Regenerate Secret Token',
      message: 'Are you sure you want to regenerate the secret token? This will invalidate the current secret and may cause webhook deliveries to fail until you update your endpoint.',
      confirmLabel: 'Regenerate',
      variant: 'warning',
      onConfirm: async () => {
        try {
          await regenerateSecret(webhook.id);
          showNotification(`Secret regenerated for "${webhook.name}". Update your endpoint with the new secret.`, 'warning');
          onWebhookAction?.('regenerate-secret', webhook.id);
        } catch (error: unknown) {
          const errorMessage = error instanceof Error ? error.message : 'Unknown error occurred';
          showNotification(`Failed to regenerate secret: ${errorMessage}`, 'error');
        }
      }
    });
  };

  const handleWebhookCreated = (webhook: AppWebhook) => {
    setShowCreateModal(false);
    setSelectedWebhook(null);
    setModalType(null);
    showNotification(`Webhook "${webhook.name}" created successfully`, 'success');
    onWebhookAction?.('create', webhook.id);
    refresh();
  };

  const handleWebhookUpdated = (webhook: AppWebhook) => {
    setShowCreateModal(false);
    setSelectedWebhook(null);
    setModalType(null);
    showNotification(`Webhook "${webhook.name}" updated successfully`, 'success');
    onWebhookAction?.('update', webhook.id);
    refresh();
  };


  const handleSearch = (e: React.FormEvent) => {
    e.preventDefault();
    setCurrentPage(1); // Reset to first page when searching
    refresh();
  };

  const handleClearFilters = () => {
    setSearchTerm('');
    setEventTypeFilter('');
    setActiveFilter(undefined);
    setCurrentPage(1);
  };

  const handlePreviousPage = () => {
    if (pagination && pagination.current_page > 1) {
      setCurrentPage(pagination.current_page - 1);
    }
  };

  const handleNextPage = () => {
    if (pagination && pagination.current_page < pagination.total_pages) {
      setCurrentPage(pagination.current_page + 1);
    }
  };

  const eventTypes = [
    'app.installed',
    'app.uninstalled', 
    'subscription.created',
    'subscription.updated',
    'subscription.cancelled',
    'payment.succeeded',
    'payment.failed',
    'invoice.created',
    'invoice.paid'
  ];

  if (loading) {
    return (
      <div className="flex justify-center py-12">
        <LoadingSpinner />
      </div>
    );
  }

  if (error) {
    return (
      <Card className="p-6">
        <div className="text-center text-theme-error">
          <div className="text-6xl mb-4">⚠️</div>
          <h3 className="text-lg font-semibold mb-2">Failed to load webhooks</h3>
          <p className="text-sm text-theme-secondary mb-4">{error}</p>
          <Button onClick={refresh} variant="primary">
            <RefreshCw className="w-4 h-4 mr-2" />
            Try Again
          </Button>
        </div>
      </Card>
    );
  }

  return (
    <div className="space-y-6">
      {/* Filters and Search */}
      <Card className="p-4">
        <form onSubmit={handleSearch} className="space-y-4">
          <div className="flex flex-col md:flex-row md:items-end md:space-x-4 space-y-4 md:space-y-0">
            <div className="flex-1">
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Search webhooks
              </label>
              <div className="relative">
                <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-theme-tertiary w-4 h-4" />
                <input
                  type="text"
                  value={searchTerm}
                  onChange={(e) => setSearchTerm(e.target.value)}
                  placeholder="Search by name, URL, or event type..."
                  className="input-theme pl-10 w-full"
                />
              </div>
            </div>
            
            <div className="w-full md:w-48">
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Event Type
              </label>
              <select
                value={eventTypeFilter}
                onChange={(e) => setEventTypeFilter(e.target.value)}
                className="input-theme w-full"
              >
                <option value="">All Events</option>
                {eventTypes.map((eventType) => (
                  <option key={eventType} value={eventType}>
                    {eventType.replace(/\./g, ' ').replace(/\b\w/g, l => l.toUpperCase())}
                  </option>
                ))}
              </select>
            </div>
            
            <div className="w-full md:w-32">
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Status
              </label>
              <select
                value={activeFilter === undefined ? '' : activeFilter.toString()}
                onChange={(e) => setActiveFilter(
                  e.target.value === '' ? undefined : e.target.value === 'true'
                )}
                className="input-theme w-full"
              >
                <option value="">All</option>
                <option value="true">Active</option>
                <option value="false">Inactive</option>
              </select>
            </div>
            
            <div className="flex space-x-2">
              <Button type="submit" variant="primary">
                <Search className="w-4 h-4" />
              </Button>
              <Button type="button" variant="outline" onClick={handleClearFilters}>
                <Filter className="w-4 h-4" />
              </Button>
            </div>
          </div>
        </form>
      </Card>

      {/* Webhooks Header */}
      <div className="flex items-center justify-between">
        <div>
          <h3 className="text-lg font-semibold text-theme-primary">
            Webhooks {webhooks.length > 0 && `(${webhooks.length})`}
          </h3>
          <p className="text-theme-secondary text-sm">
            Configure webhooks to receive real-time notifications about events
          </p>
        </div>
        {showCreateButton && (
          <Button variant="primary" onClick={handleCreateWebhook}>
            <Plus className="w-4 h-4 mr-2" />
            Add Webhook
          </Button>
        )}
      </div>

      {/* Webhooks List */}
      {webhooks.length === 0 ? (
        <Card className="p-12 text-center">
          <div className="text-6xl mb-4">🔗</div>
          <h3 className="text-xl font-semibold text-theme-primary mb-2">No webhooks found</h3>
          <p className="text-theme-secondary mb-6">
            {searchTerm || eventTypeFilter || activeFilter !== undefined
              ? 'No webhooks match your current filters. Try adjusting your search criteria.'
              : 'Webhooks allow your app to send notifications to external services when events occur.'
            }
          </p>
          {showCreateButton && (!searchTerm && !eventTypeFilter && activeFilter === undefined) && (
            <Button variant="primary" onClick={handleCreateWebhook}>
              <Plus className="w-4 h-4 mr-2" />
              Create First Webhook
            </Button>
          )}
        </Card>
      ) : (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {webhooks.map((webhook) => (
            <WebhookCard
              key={webhook.id}
              webhook={webhook}
              onEdit={handleEditWebhook}
              onToggleStatus={handleToggleStatus}
              onTest={handleTestWebhook}
              onViewAnalytics={handleViewAnalytics}
              onViewDeliveries={handleViewDeliveries}
              onRegenerateSecret={handleRegenerateSecret}
            />
          ))}
        </div>
      )}

      {/* Pagination */}
      {pagination && pagination.total_pages > 1 && (
        <div className="flex justify-center mt-8">
          <div className="flex items-center space-x-2">
            <Button
              variant="outline"
              disabled={pagination.current_page === 1}
              onClick={handlePreviousPage}
            >
              Previous
            </Button>
            <span className="text-theme-secondary text-sm px-4">
              Page {pagination.current_page} of {pagination.total_pages}
              {pagination.total_count > 0 && (
                <span className="text-theme-tertiary ml-2">
                  ({pagination.total_count} total)
                </span>
              )}
            </span>
            <Button
              variant="outline"
              disabled={pagination.current_page === pagination.total_pages}
              onClick={handleNextPage}
            >
              Next
            </Button>
          </div>
        </div>
      )}

      {/* Create/Edit Modal */}
      <WebhookFormModal
        isOpen={showCreateModal}
        onClose={() => {
          setShowCreateModal(false);
          setSelectedWebhook(null);
          setModalType(null);
        }}
        appId={appId}
        webhook={modalType === 'edit' ? selectedWebhook : null}
        onSuccess={modalType === 'edit' ? handleWebhookUpdated : handleWebhookCreated}
      />

      {/* Test Modal */}
      {modalType === 'test' && selectedWebhook && (
        <WebhookTestModal
          isOpen={true}
          onClose={() => {
            setSelectedWebhook(null);
            setModalType(null);
          }}
          appId={appId}
          webhook={selectedWebhook}
        />
      )}

      {/* Analytics Modal */}
      {modalType === 'analytics' && selectedWebhook && (
        <WebhookAnalyticsModal
          isOpen={true}
          onClose={() => {
            setSelectedWebhook(null);
            setModalType(null);
          }}
          appId={appId}
          webhook={selectedWebhook}
        />
      )}

      {/* Deliveries Modal */}
      {modalType === 'deliveries' && selectedWebhook && (
        <WebhookDeliveriesModal
          isOpen={true}
          onClose={() => {
            setSelectedWebhook(null);
            setModalType(null);
          }}
          appId={appId}
          webhook={selectedWebhook}
        />
      )}
      {ConfirmationDialog}
    </div>
  );
};