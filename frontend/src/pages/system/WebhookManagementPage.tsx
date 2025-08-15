import React, { useState, useEffect, useCallback } from 'react';
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
import webhooksApi, { 
  WebhookEndpoint, 
  WebhookStats as WebhookStatsType, 
  WebhookFormData,
  DetailedWebhookStats
} from '../../services/webhooksApi';
import WebhookForm from '../../components/webhooks/WebhookForm';
import WebhookList from '../../components/webhooks/WebhookList';
import WebhookDetails from '../../components/webhooks/WebhookDetails';
import WebhookStats from '../../components/webhooks/WebhookStats';
import { LoadingSpinner } from '../../components/ui/LoadingSpinner';
import ErrorAlert from '../../components/common/ErrorAlert';
import SuccessAlert from '../../components/common/SuccessAlert';

type ViewMode = 'list' | 'create' | 'edit' | 'details' | 'stats';

const WebhookManagementPage: React.FC = () => {
  // State
  const [viewMode, setViewMode] = useState<ViewMode>('list');
  const [webhooks, setWebhooks] = useState<WebhookEndpoint[]>([]);
  const [selectedWebhook, setSelectedWebhook] = useState<WebhookEndpoint | null>(null);
  const [stats, setStats] = useState<WebhookStatsType | null>(null);
  const [detailedStats, setDetailedStats] = useState<DetailedWebhookStats | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
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
    setLoading(true);
    setError(null);

    try {
      const response = await webhooksApi.getWebhooks(page, pagination.per_page);
      
      if (response.success && response.data) {
        setWebhooks(response.data.webhooks);
        setPagination(response.data.pagination);
        setStats(response.data.stats);
      } else {
        setError(response.error || 'Failed to load webhooks');
      }
    } catch (err) {
      setError('An unexpected error occurred while loading webhooks');
    } finally {
      setLoading(false);
    }
  }, [pagination.per_page]);

  // Load detailed stats
  const loadDetailedStats = useCallback(async () => {
    try {
      const response = await webhooksApi.getStats();
      if (response.success && response.data) {
        setDetailedStats(response.data);
      }
    } catch (err) {
      console.error('Failed to load detailed stats:', err);
    }
  }, []);

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
    try {
      const response = await webhooksApi.createWebhook(webhookData);
      
      if (response.success) {
        setSuccess(response.message || 'Webhook created successfully');
        setViewMode('list');
        loadWebhooks(pagination.current_page);
      } else {
        setError(response.error || 'Failed to create webhook');
      }
    } catch (err) {
      setError('An unexpected error occurred while creating the webhook');
    }
  };

  // Handle webhook update
  const handleUpdateWebhook = async (webhookData: Partial<WebhookFormData>) => {
    if (!selectedWebhook) return;

    try {
      const response = await webhooksApi.updateWebhook(selectedWebhook.id, webhookData);
      
      if (response.success) {
        setSuccess(response.message || 'Webhook updated successfully');
        setViewMode('list');
        loadWebhooks(pagination.current_page);
        setSelectedWebhook(null);
      } else {
        setError(response.error || 'Failed to update webhook');
      }
    } catch (err) {
      setError('An unexpected error occurred while updating the webhook');
    }
  };

  // Handle webhook deletion
  const handleDeleteWebhook = async (webhookId: string) => {
    if (!window.confirm('Are you sure you want to delete this webhook? This action cannot be undone.')) {
      return;
    }

    try {
      const response = await webhooksApi.deleteWebhook(webhookId);
      
      if (response.success) {
        setSuccess(response.message || 'Webhook deleted successfully');
        loadWebhooks(pagination.current_page);
      } else {
        setError(response.error || 'Failed to delete webhook');
      }
    } catch (err) {
      setError('An unexpected error occurred while deleting the webhook');
    }
  };

  // Handle webhook status toggle
  const handleToggleStatus = async (webhookId: string) => {
    try {
      const response = await webhooksApi.toggleWebhookStatus(webhookId);
      
      if (response.success) {
        setSuccess(response.message || 'Webhook status updated successfully');
        loadWebhooks(pagination.current_page);
      } else {
        setError(response.error || 'Failed to update webhook status');
      }
    } catch (err) {
      setError('An unexpected error occurred while updating webhook status');
    }
  };

  // Handle retry failed deliveries
  const handleRetryFailed = async () => {
    try {
      const response = await webhooksApi.retryFailed();
      
      if (response.success && response.data) {
        setSuccess(`Queued ${response.data.retry_count} failed deliveries for retry`);
      } else {
        setError(response.error || 'Failed to retry failed deliveries');
      }
    } catch (err) {
      setError('An unexpected error occurred while retrying failed deliveries');
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
    setViewMode('edit');
  };

  // Clear messages
  useEffect(() => {
    if (success) {
      const timer = setTimeout(() => setSuccess(null), 5000);
      return () => clearTimeout(timer);
    }
  }, [success]);

  useEffect(() => {
    if (error) {
      const timer = setTimeout(() => setError(null), 10000);
      return () => clearTimeout(timer);
    }
  }, [error]);

  // Render page header following SystemManagement template
  const renderPageHeader = () => (
    <div>
      <div className="flex justify-between items-center mb-6">
        <div>
          <h1 className="text-3xl font-bold text-theme-primary">Webhook Management</h1>
          <p className="text-theme-secondary mt-2">Configure and monitor webhook endpoints for real-time notifications</p>
        </div>
        <div className="flex items-center gap-3">
          <button
            onClick={() => setViewMode('stats')}
            className={`px-4 py-2 rounded-lg border transition-all duration-200 ${
              viewMode === 'stats'
                ? 'bg-theme-interactive-primary text-white border-theme-interactive-primary'
                : 'bg-theme-surface text-theme-secondary border-theme hover:bg-theme-surface-hover'
            }`}
          >
            <BarChart3 className="w-4 h-4 mr-2 inline" />
            Statistics
          </button>

          <button
            onClick={() => setViewMode('create')}
            className="bg-theme-interactive-primary text-white px-4 py-2 rounded-lg hover:bg-theme-interactive-primary-hover transition-all duration-200 flex items-center gap-2"
          >
            <Plus className="w-4 h-4" />
            Add Webhook
          </button>
        </div>
      </div>

      {/* Stats overview when in list mode */}
      {viewMode === 'list' && (
        <div className="bg-theme-surface rounded-lg p-6 mb-6">
          {renderStatsOverview()}
          {renderActionButtons()}
        </div>
      )}
    </div>
  );

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

  // Render action buttons
  const renderActionButtons = () => (
    <div className="flex flex-wrap items-center gap-3 pt-4 border-t border-theme">
      <button
        onClick={() => loadWebhooks(pagination.current_page)}
        disabled={loading}
        className="bg-theme-surface text-theme-secondary px-4 py-2 rounded-lg border border-theme hover:bg-theme-surface-hover transition-all duration-200 flex items-center gap-2 disabled:opacity-50"
      >
        <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
        Refresh
      </button>

      {stats && stats.failed_deliveries_today > 0 && (
        <button
          onClick={handleRetryFailed}
          className="bg-theme-warning bg-opacity-10 text-theme-warning px-4 py-2 rounded-lg border border-theme-warning hover:bg-theme-warning hover:bg-opacity-20 transition-all duration-200 flex items-center gap-2"
        >
          <RefreshCw className="w-4 h-4" />
          Retry Failed ({stats.failed_deliveries_today})
        </button>
      )}
    </div>
  );

  // Main render
  return (
    <div className="space-y-6">
      {/* Success/Error Messages */}
      {success && <SuccessAlert message={success} onClose={() => setSuccess(null)} />}
      {error && <ErrorAlert message={error} onClose={() => setError(null)} />}

      {/* Page Header with integrated stats and actions for list view */}
      {renderPageHeader()}

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
              onEdit={handleEditWebhook}
              onDelete={handleDeleteWebhook}
              onToggleStatus={handleToggleStatus}
              filters={filters}
              onFiltersChange={setFilters}
            />
          )}

          {viewMode === 'create' && (
            <div className="bg-theme-surface rounded-lg p-6">
              <div className="mb-6">
                <button
                  onClick={() => setViewMode('list')}
                  className="text-theme-link hover:text-theme-link-hover transition-colors duration-200"
                >
                  ← Back to Webhooks
                </button>
                <h2 className="text-xl font-semibold text-theme-primary mt-2">
                  Create New Webhook
                </h2>
              </div>
              <WebhookForm
                onSubmit={handleCreateWebhook}
                onCancel={() => setViewMode('list')}
              />
            </div>
          )}

          {viewMode === 'edit' && selectedWebhook && (
            <div className="bg-theme-surface rounded-lg p-6">
              <div className="mb-6">
                <button
                  onClick={() => setViewMode('list')}
                  className="text-theme-link hover:text-theme-link-hover transition-colors duration-200"
                >
                  ← Back to Webhooks
                </button>
                <h2 className="text-xl font-semibold text-theme-primary mt-2">
                  Edit Webhook
                </h2>
              </div>
              <WebhookForm
                webhook={selectedWebhook}
                onSubmit={handleUpdateWebhook}
                onCancel={() => setViewMode('list')}
              />
            </div>
          )}

          {viewMode === 'details' && selectedWebhook && (
            <div className="bg-theme-surface rounded-lg p-6">
              <div className="mb-6">
                <button
                  onClick={() => setViewMode('list')}
                  className="text-theme-link hover:text-theme-link-hover transition-colors duration-200"
                >
                  ← Back to Webhooks
                </button>
                <h2 className="text-xl font-semibold text-theme-primary mt-2">
                  Webhook Details
                </h2>
              </div>
              <WebhookDetails
                webhook={selectedWebhook}
                onEdit={() => handleEditWebhook(selectedWebhook)}
                onDelete={() => handleDeleteWebhook(selectedWebhook.id)}
                onToggleStatus={() => handleToggleStatus(selectedWebhook.id)}
              />
            </div>
          )}

          {viewMode === 'stats' && (
            <div className="bg-theme-surface rounded-lg p-6">
              <div className="mb-6">
                <button
                  onClick={() => setViewMode('list')}
                  className="text-theme-link hover:text-theme-link-hover transition-colors duration-200"
                >
                  ← Back to Webhooks
                </button>
                <h2 className="text-xl font-semibold text-theme-primary mt-2">
                  Webhook Statistics
                </h2>
              </div>
              <WebhookStats
                stats={stats}
                detailedStats={detailedStats}
                loading={!detailedStats}
              />
            </div>
          )}
        </>
      )}
    </div>
  );
};

export default WebhookManagementPage;