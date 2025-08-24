import React, { useState, useEffect } from 'react';
import { Button } from '@/shared/components/ui/Button';
import { FormField } from '@/shared/components/ui/FormField';
import { 
  Webhook, Plus, Play, Pause, Trash2, Settings, 
  Activity, CheckCircle, XCircle, AlertTriangle,
  Copy, Eye, RotateCcw, Zap, TrendingUp, Search,
  RefreshCw
} from 'lucide-react';
import { webhooksApi, WebhookEndpoint, DetailedWebhookEndpoint, WebhookDelivery, WebhookFormData, DetailedWebhookStats } from '@/features/webhooks/services/webhooksApi';
import { useNotification } from '@/shared/hooks/useNotification';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';

interface EnhancedWebhookConsoleProps {
  showStats?: boolean;
  showDeliveryHistory?: boolean;
}

interface CreateWebhookModalProps {
  isOpen: boolean;
  onClose: () => void;
  onWebhookCreated: (webhook: DetailedWebhookEndpoint) => void;
}

interface WebhookDetailsModalProps {
  webhook: DetailedWebhookEndpoint | null;
  isOpen: boolean;
  onClose: () => void;
  onWebhookUpdated: () => void;
}

const CreateWebhookModal: React.FC<CreateWebhookModalProps> = ({
  isOpen,
  onClose,
  onWebhookCreated
}) => {
  const [formData, setFormData] = useState<WebhookFormData>(webhooksApi.getDefaultFormData());
  // Removed unused availableEvents state
  const [eventCategories, setEventCategories] = useState<{ [key: string]: string[] }>({});
  const [loading, setLoading] = useState(false);
  const [errors, setErrors] = useState<string[]>([]);
  const [showAdvanced, setShowAdvanced] = useState(false);
  
  const { showNotification } = useNotification();

  useEffect(() => {
    if (isOpen) {
      loadAvailableEvents();
    }
  }, [isOpen]);

  const loadAvailableEvents = async () => {
    try {
      const response = await webhooksApi.getAvailableEvents();
      if (response.success && response.data) {
        setEventCategories(response.data.categories);
      }
    } catch (error) {
      console.error('Failed to load available events:', error);
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    
    const validationErrors = webhooksApi.validateWebhookData(formData);
    if (validationErrors.length > 0) {
      setErrors(validationErrors);
      return;
    }

    try {
      setLoading(true);
      setErrors([]);
      const response = await webhooksApi.createWebhook(formData);
      
      if (response.success && response.data) {
        showNotification('Webhook created successfully', 'success');
        onWebhookCreated(response.data);
        onClose();
        setFormData(webhooksApi.getDefaultFormData());
      } else {
        setErrors([response.error || 'Failed to create webhook']);
      }
    } catch (error: any) {
      setErrors(['Failed to create webhook']);
    } finally {
      setLoading(false);
    }
  };

  const toggleEventType = (eventType: string) => {
    setFormData(prev => ({
      ...prev,
      event_types: prev.event_types.includes(eventType)
        ? prev.event_types.filter(e => e !== eventType)
        : [...prev.event_types, eventType]
    }));
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4 z-50">
      <div className="bg-theme-surface rounded-lg shadow-xl max-w-3xl w-full max-h-[90vh] overflow-hidden">
        <div className="px-6 py-4 border-b border-theme">
          <h3 className="text-lg font-semibold text-theme-primary">Create Webhook Endpoint</h3>
        </div>
        
        <form onSubmit={handleSubmit} className="overflow-auto max-h-[calc(90vh-140px)]">
          <div className="px-6 py-4 space-y-6">
            {/* Errors */}
            {errors.length > 0 && (
              <div className="bg-theme-error-background border border-theme-error rounded-lg p-4">
                <div className="flex items-center gap-2 mb-2">
                  <AlertTriangle className="w-5 h-5 text-theme-error" />
                  <span className="font-medium text-theme-error">Please fix the following errors:</span>
                </div>
                <ul className="list-disc list-inside text-sm text-theme-error space-y-1">
                  {errors.map((error, index) => (
                    <li key={index}>{error}</li>
                  ))}
                </ul>
              </div>
            )}

            {/* Basic Info */}
            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Endpoint URL *
                </label>
                <input
                  type="url"
                  value={formData.url}
                  onChange={(e) => setFormData(prev => ({ ...prev, url: e.target.value }))}
                  className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                  placeholder="https://your-app.com/webhooks"
                  required
                />
              </div>
              
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Description
                </label>
                <textarea
                  value={formData.description || ''}
                  onChange={(e) => setFormData(prev => ({ ...prev, description: e.target.value }))}
                  className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                  rows={3}
                  placeholder="Optional description of what this webhook does"
                />
              </div>
            </div>

            {/* Event Types */}
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-3">
                Event Types *
              </label>
              <div className="space-y-4 max-h-60 overflow-y-auto border border-theme rounded-lg p-3">
                {Object.entries(eventCategories).map(([category, events]) => (
                  <div key={category}>
                    <h4 className="font-medium text-theme-primary mb-2 capitalize">
                      {category.replace('_', ' ')}
                    </h4>
                    <div className="space-y-2 ml-2">
                      {events.map((eventType) => (
                        <label key={eventType} className="flex items-center gap-2 cursor-pointer">
                          <input
                            type="checkbox"
                            checked={formData.event_types.includes(eventType)}
                            onChange={() => toggleEventType(eventType)}
                            className="w-4 h-4 text-theme-interactive-primary border-theme rounded focus:ring-theme-interactive-primary"
                          />
                          <span className="text-sm text-theme-secondary">{webhooksApi.formatEventType(eventType)}</span>
                        </label>
                      ))}
                    </div>
                  </div>
                ))}
              </div>
            </div>

            {/* Advanced Settings */}
            <div>
              <Button type="button" variant="outline" onClick={() => setShowAdvanced(!showAdvanced)}
                className="flex items-center gap-2 text-theme-link hover:text-theme-link-hover"
              >
                <Settings className="w-4 h-4" />
                {showAdvanced ? 'Hide' : 'Show'} Advanced Settings
              </Button>
              
              {showAdvanced && (
                <div className="mt-4 space-y-4 p-4 bg-theme-background rounded-lg border border-theme">
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <div>
                      <label className="block text-sm font-medium text-theme-primary mb-2">
                        Content Type
                      </label>
                      <select
                        value={formData.content_type || 'application/json'}
                        onChange={(e) => setFormData(prev => ({ ...prev, content_type: e.target.value }))}
                        className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                      >
                        <option value="application/json">application/json</option>
                        <option value="application/x-www-form-urlencoded">application/x-www-form-urlencoded</option>
                      </select>
                    </div>
                    
                    <div>
                      <label className="block text-sm font-medium text-theme-primary mb-2">
                        Timeout (seconds)
                      </label>
                      <input
                        type="number"
                        min="1"
                        max="300"
                        value={formData.timeout_seconds || 30}
                        onChange={(e) => setFormData(prev => ({ ...prev, timeout_seconds: parseInt(e.target.value) }))}
                        className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                      />
                    </div>
                    
                    <div>
                      <label className="block text-sm font-medium text-theme-primary mb-2">
                        Retry Limit
                      </label>
                      <input
                        type="number"
                        min="0"
                        max="10"
                        value={formData.retry_limit || 3}
                        onChange={(e) => setFormData(prev => ({ ...prev, retry_limit: parseInt(e.target.value) }))}
                        className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                      />
                    </div>
                    
                    <div>
                      <label className="block text-sm font-medium text-theme-primary mb-2">
                        Retry Strategy
                      </label>
                      <select
                        value={formData.retry_backoff || 'exponential'}
                        onChange={(e) => setFormData(prev => ({ ...prev, retry_backoff: e.target.value as 'linear' | 'exponential' }))}
                        className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                      >
                        <option value="exponential">Exponential Backoff</option>
                        <option value="linear">Linear Backoff</option>
                      </select>
                    </div>
                  </div>
                </div>
              )}
            </div>
          </div>
        </form>

        <div className="px-6 py-4 border-t border-theme flex justify-end gap-3">
          <Button onClick={onClose} type="button" variant="outline">
            Cancel
          </Button>
          <Button onClick={handleSubmit} disabled={loading} variant="primary">
            {loading ? (
              <>
                <LoadingSpinner size="sm" />
                Creating...
              </>
            ) : (
              <>
                <Webhook className="w-4 h-4" />
                Create Webhook
              </>
            )}
          </Button>
        </div>
      </div>
    </div>
  );
};

const WebhookDetailsModal: React.FC<WebhookDetailsModalProps> = ({
  webhook,
  isOpen,
  onClose,
  onWebhookUpdated
}) => {
  const [activeTab, setActiveTab] = useState<'details' | 'deliveries'>('details');
  const [deliveries, setDeliveries] = useState<WebhookDelivery[]>([]);
  const [deliveriesLoading, setDeliveriesLoading] = useState(false);
  
  const { showNotification } = useNotification();

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
            <Button variant="outline" onClick={() => setActiveTab('deliveries')}
              className={`py-2 px-1 border-b-2 font-medium text-sm ${
                activeTab === 'deliveries'
                  ? 'border-theme-interactive-primary text-theme-interactive-primary'
                  : 'border-transparent text-theme-secondary hover:text-theme-primary'
              }`}
            >
              Delivery History
            </Button>
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

          {activeTab === 'deliveries' && (
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
                          <div>{new Date(delivery.created_at).toLocaleString()}</div>
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
                          <span>Next retry: {new Date(delivery.next_retry_at).toLocaleString()}</span>
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

export const EnhancedWebhookConsole: React.FC<EnhancedWebhookConsoleProps> = ({
EnhancedWebhookConsole.displayName = 'EnhancedWebhookConsole';
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
  
  const { showNotification } = useNotification();
  const perPage = 20;

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
    } catch (error: any) {
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
      console.error('Failed to load webhook stats:', error);
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
    } catch (error: any) {
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

  const filteredWebhooks = webhooks.filter(webhook =>
    searchTerm === '' || 
    webhook.url.toLowerCase().includes(searchTerm.toLowerCase()) ||
    webhook.description?.toLowerCase().includes(searchTerm.toLowerCase()) ||
    webhook.event_types.some(event => event.toLowerCase().includes(searchTerm.toLowerCase()))
  );

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
                        ? new Date(webhook.last_delivery_at).toLocaleDateString()
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
      <CreateWebhookModal
        isOpen={showCreateModal}
        onClose={() => setShowCreateModal(false)}
        onWebhookCreated={(webhook) => {
          loadWebhooks();
          if (showStats) loadStats();
        }}
      />

      <WebhookDetailsModal
        webhook={selectedWebhook}
        isOpen={showDetailsModal}
        onClose={() => {
          setShowDetailsModal(false);
          setSelectedWebhook(null);
        }}
        onWebhookUpdated={() => {
          loadWebhooks();
          if (showStats) loadStats();
        }}
      />
    </div>
  );
};

export default EnhancedWebhookConsole;