import React, { useState, useEffect, useCallback } from 'react';
import { 
  Globe,
  Edit,
  Trash2,
  Power,
  PowerOff,
  TestTube,
  Activity,
  Clock,
  CheckCircle,
  AlertTriangle,
  ExternalLink,
  Copy,
  Eye,
  EyeOff,
  Settings,
  TrendingUp,
  Calendar,
  RefreshCw,
  X
} from 'lucide-react';
import webhooksApi, { 
  WebhookEndpoint, 
  DetailedWebhookEndpoint, 
  WebhookDelivery 
} from '../../services/webhooksApi';
import WebhookTest from './WebhookTest';
import { LoadingSpinner } from '../ui/LoadingSpinner';
import ErrorAlert from '../common/ErrorAlert';
import SuccessAlert from '../common/SuccessAlert';
import Pagination from '../common/Pagination';

interface WebhookDetailsProps {
  webhook: WebhookEndpoint;
  onEdit: () => void;
  onDelete: () => void;
  onToggleStatus: () => void;
}

const WebhookDetails: React.FC<WebhookDetailsProps> = ({
  webhook,
  onEdit,
  onDelete,
  onToggleStatus
}) => {
  const [detailedWebhook, setDetailedWebhook] = useState<DetailedWebhookEndpoint | null>(null);
  const [deliveries, setDeliveries] = useState<WebhookDelivery[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadingDeliveries, setLoadingDeliveries] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [showSecretToken, setShowSecretToken] = useState(false);
  const [showTestModal, setShowTestModal] = useState(false);
  const [activeTab, setActiveTab] = useState<'overview' | 'deliveries' | 'test'>('overview');
  
  const [deliveryFilters, setDeliveryFilters] = useState({
    status: 'all',
    page: 1,
    per_page: 20
  });

  const [deliveryPagination, setDeliveryPagination] = useState({
    current_page: 1,
    per_page: 20,
    total_pages: 0,
    total_count: 0
  });

  // Load detailed webhook data
  useEffect(() => {
    const loadWebhookDetails = async () => {
      setLoading(true);
      setError(null);

      try {
        const response = await webhooksApi.getWebhook(webhook.id);
        
        if (response.success && response.data) {
          setDetailedWebhook(response.data);
        } else {
          setError(response.error || 'Failed to load webhook details');
        }
      } catch (err) {
        setError('An unexpected error occurred while loading webhook details');
      } finally {
        setLoading(false);
      }
    };

    loadWebhookDetails();
  }, [webhook.id]);

  // Load delivery history
  const loadDeliveries = useCallback(async (page = 1) => {
    setLoadingDeliveries(true);
    
    try {
      const response = await webhooksApi.getDeliveryHistory(
        webhook.id, 
        page, 
        deliveryFilters.per_page
      );
      
      if (response.success && response.data) {
        setDeliveries(response.data.deliveries);
        setDeliveryPagination(response.data.pagination);
      } else {
        setError(response.error || 'Failed to load delivery history');
      }
    } catch (err) {
      setError('Failed to load delivery history');
    } finally {
      setLoadingDeliveries(false);
    }
  }, [webhook.id, deliveryFilters.per_page]);

  // Load deliveries when tab changes or filters change
  useEffect(() => {
    if (activeTab === 'deliveries') {
      loadDeliveries(deliveryFilters.page);
    }
  }, [activeTab, deliveryFilters, webhook.id, loadDeliveries]);

  // Copy secret token to clipboard
  const copySecretToken = async () => {
    if (!detailedWebhook?.secret_token) return;
    
    try {
      await navigator.clipboard.writeText(detailedWebhook.secret_token);
      setSuccess('Secret token copied to clipboard');
    } catch (err) {
      setError('Failed to copy secret token');
    }
  };

  // Handle delivery page change
  const handleDeliveryPageChange = (page: number) => {
    setDeliveryFilters(prev => ({ ...prev, page }));
    loadDeliveries(page);
  };

  if (loading) {
    return (
      <div className="bg-theme-surface rounded-lg border border-theme p-8">
        <div className="flex justify-center">
          <LoadingSpinner size="lg" />
        </div>
      </div>
    );
  }

  if (!detailedWebhook) {
    return (
      <div className="bg-theme-surface rounded-lg border border-theme p-8">
        <ErrorAlert message="Failed to load webhook details" />
      </div>
    );
  }

  const successRate = webhooksApi.getSuccessRate(webhook);

  return (
    <div className="space-y-6">
      {/* Success/Error Messages */}
      {success && <SuccessAlert message={success} onClose={() => setSuccess(null)} />}
      {error && <ErrorAlert message={error} onClose={() => setError(null)} />}

      {/* Header */}
      <div className="bg-theme-background rounded-lg border border-theme p-6">
        <div className="flex flex-col lg:flex-row lg:items-start lg:justify-between gap-4">
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-3 mb-2">
              <Globe className="w-6 h-6 text-theme-interactive-primary flex-shrink-0" />
              <h2 className="text-xl font-semibold text-theme-primary truncate">
                {webhook.url}
              </h2>
              <a 
                href={webhook.url} 
                target="_blank" 
                rel="noopener noreferrer"
                className="text-theme-link hover:text-theme-link-hover transition-colors duration-200"
                title="Open webhook URL"
              >
                <ExternalLink className="w-4 h-4" />
              </a>
            </div>
            
            {webhook.description && (
              <p className="text-theme-secondary mb-4">{webhook.description}</p>
            )}

            <div className="flex flex-wrap items-center gap-4">
              <span className={`inline-flex items-center px-3 py-1 rounded-full text-sm font-medium ${
                webhooksApi.getStatusColor(webhook.status)
              }`}>
                {webhook.status === 'active' ? (
                  <CheckCircle className="w-4 h-4 mr-2" />
                ) : (
                  <Clock className="w-4 h-4 mr-2" />
                )}
                {webhook.status.charAt(0).toUpperCase() + webhook.status.slice(1)}
              </span>

              <div className="flex items-center gap-2 text-sm text-theme-secondary">
                <Calendar className="w-4 h-4" />
                Created {new Date(webhook.created_at).toLocaleDateString()}
              </div>

              {webhook.created_by && (
                <div className="text-sm text-theme-secondary">
                  by {webhook.created_by.email}
                </div>
              )}
            </div>
          </div>

          {/* Actions */}
          <div className="flex flex-wrap items-center gap-2">
            <button
              onClick={onEdit}
              className="bg-theme-interactive-primary text-white px-4 py-2 rounded-lg hover:bg-theme-interactive-primary-hover transition-all duration-200 flex items-center gap-2"
            >
              <Edit className="w-4 h-4" />
              Edit
            </button>

            <button
              onClick={onToggleStatus}
              className={`px-4 py-2 rounded-lg border transition-all duration-200 flex items-center gap-2 ${
                webhook.status === 'active'
                  ? 'bg-theme-warning bg-opacity-10 text-theme-warning border-theme-warning hover:bg-theme-warning hover:bg-opacity-20'
                  : 'bg-theme-success bg-opacity-10 text-theme-success border-theme-success hover:bg-theme-success hover:bg-opacity-20'
              }`}
            >
              {webhook.status === 'active' ? (
                <>
                  <PowerOff className="w-4 h-4" />
                  Disable
                </>
              ) : (
                <>
                  <Power className="w-4 h-4" />
                  Enable
                </>
              )}
            </button>

            <button
              onClick={() => setShowTestModal(true)}
              className="bg-theme-surface text-theme-secondary px-4 py-2 rounded-lg border border-theme hover:bg-theme-surface-hover transition-all duration-200 flex items-center gap-2"
            >
              <TestTube className="w-4 h-4" />
              Test
            </button>

            <button
              onClick={onDelete}
              className="bg-theme-error bg-opacity-10 text-theme-error px-4 py-2 rounded-lg border border-theme-error hover:bg-theme-error hover:bg-opacity-20 transition-all duration-200 flex items-center gap-2"
            >
              <Trash2 className="w-4 h-4" />
              Delete
            </button>
          </div>
        </div>
      </div>

      {/* Stats Cards */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <div className="bg-theme-surface rounded-lg border border-theme p-4">
          <div className="flex items-center gap-3">
            <div className={`p-2 rounded-lg ${
              successRate >= 95 ? 'bg-theme-success bg-opacity-10' :
              successRate >= 80 ? 'bg-theme-warning bg-opacity-10' : 'bg-theme-error bg-opacity-10'
            }`}>
              <TrendingUp className={`w-5 h-5 ${
                successRate >= 95 ? 'text-theme-success' :
                successRate >= 80 ? 'text-theme-warning' : 'text-theme-error'
              }`} />
            </div>
            <div>
              <p className="text-2xl font-bold text-theme-primary">{successRate}%</p>
              <p className="text-sm text-theme-secondary">Success Rate</p>
            </div>
          </div>
        </div>

        <div className="bg-theme-surface rounded-lg border border-theme p-4">
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-lg bg-theme-interactive-primary bg-opacity-10">
              <Activity className="w-5 h-5 text-theme-interactive-primary" />
            </div>
            <div>
              <p className="text-2xl font-bold text-theme-primary">
                {detailedWebhook.delivery_stats.total_deliveries}
              </p>
              <p className="text-sm text-theme-secondary">Total Deliveries</p>
            </div>
          </div>
        </div>

        <div className="bg-theme-surface rounded-lg border border-theme p-4">
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-lg bg-theme-success bg-opacity-10">
              <CheckCircle className="w-5 h-5 text-theme-success" />
            </div>
            <div>
              <p className="text-2xl font-bold text-theme-primary">{webhook.success_count}</p>
              <p className="text-sm text-theme-secondary">Successful</p>
            </div>
          </div>
        </div>

        <div className="bg-theme-surface rounded-lg border border-theme p-4">
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-lg bg-theme-error bg-opacity-10">
              <AlertTriangle className="w-5 h-5 text-theme-error" />
            </div>
            <div>
              <p className="text-2xl font-bold text-theme-primary">{webhook.failure_count}</p>
              <p className="text-sm text-theme-secondary">Failed</p>
            </div>
          </div>
        </div>
      </div>

      {/* Tabs */}
      <div className="bg-theme-surface rounded-lg border border-theme overflow-hidden">
        {/* Tab Headers */}
        <div className="flex border-b border-theme">
          {[
            { id: 'overview', label: 'Overview', icon: Settings },
            { id: 'deliveries', label: 'Delivery History', icon: Activity },
            { id: 'test', label: 'Test Webhook', icon: TestTube }
          ].map(tab => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id as any)}
              className={`flex items-center gap-2 px-6 py-3 font-medium transition-all duration-200 ${
                activeTab === tab.id
                  ? 'bg-theme-interactive-primary text-white border-b-2 border-theme-interactive-primary'
                  : 'text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-hover'
              }`}
            >
              <tab.icon className="w-4 h-4" />
              {tab.label}
            </button>
          ))}
        </div>

        {/* Tab Content */}
        <div className="p-6">
          {activeTab === 'overview' && (
            <div className="space-y-6">
              {/* Configuration Details */}
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div>
                  <h3 className="text-lg font-semibold text-theme-primary mb-4">Configuration</h3>
                  <div className="space-y-3">
                    <div>
                      <label className="block text-sm font-medium text-theme-secondary mb-1">
                        Content Type
                      </label>
                      <p className="text-theme-primary">{webhook.content_type}</p>
                    </div>
                    
                    <div>
                      <label className="block text-sm font-medium text-theme-secondary mb-1">
                        Timeout
                      </label>
                      <p className="text-theme-primary">{webhook.timeout_seconds} seconds</p>
                    </div>
                    
                    <div>
                      <label className="block text-sm font-medium text-theme-secondary mb-1">
                        Retry Limit
                      </label>
                      <p className="text-theme-primary">{webhook.retry_limit} attempts</p>
                    </div>
                    
                    <div>
                      <label className="block text-sm font-medium text-theme-secondary mb-1">
                        Retry Strategy
                      </label>
                      <p className="text-theme-primary capitalize">
                        {detailedWebhook.retry_backoff} backoff
                      </p>
                    </div>
                  </div>
                </div>

                <div>
                  <h3 className="text-lg font-semibold text-theme-primary mb-4">Performance</h3>
                  <div className="space-y-3">
                    <div>
                      <label className="block text-sm font-medium text-theme-secondary mb-1">
                        Average Response Time
                      </label>
                      <p className="text-theme-primary">
                        {detailedWebhook.delivery_stats.average_response_time 
                          ? `${Math.round(detailedWebhook.delivery_stats.average_response_time)}ms`
                          : 'N/A'
                        }
                      </p>
                    </div>
                    
                    <div>
                      <label className="block text-sm font-medium text-theme-secondary mb-1">
                        Last Successful Delivery
                      </label>
                      <p className="text-theme-primary">
                        {detailedWebhook.delivery_stats.last_success_at 
                          ? new Date(detailedWebhook.delivery_stats.last_success_at).toLocaleString()
                          : 'Never'
                        }
                      </p>
                    </div>
                    
                    <div>
                      <label className="block text-sm font-medium text-theme-secondary mb-1">
                        Last Failed Delivery
                      </label>
                      <p className="text-theme-primary">
                        {detailedWebhook.delivery_stats.last_failure_at 
                          ? new Date(detailedWebhook.delivery_stats.last_failure_at).toLocaleString()
                          : 'Never'
                        }
                      </p>
                    </div>
                  </div>
                </div>
              </div>

              {/* Secret Token */}
              <div>
                <h3 className="text-lg font-semibold text-theme-primary mb-4">Secret Token</h3>
                <div className="bg-theme-background rounded-lg border border-theme p-4">
                  <div className="flex items-center gap-4">
                    <div className="flex-1">
                      <div className="font-mono text-sm text-theme-primary bg-theme-surface px-3 py-2 rounded border">
                        {showSecretToken ? detailedWebhook.secret_token : '••••••••••••••••••••••••••••••••'}
                      </div>
                    </div>
                    
                    <div className="flex items-center gap-2">
                      <button
                        onClick={() => setShowSecretToken(!showSecretToken)}
                        className="p-2 text-theme-secondary hover:text-theme-primary transition-colors duration-200"
                        title={showSecretToken ? 'Hide token' : 'Show token'}
                      >
                        {showSecretToken ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                      </button>
                      
                      <button
                        onClick={copySecretToken}
                        className="p-2 text-theme-secondary hover:text-theme-primary transition-colors duration-200"
                        title="Copy to clipboard"
                      >
                        <Copy className="w-4 h-4" />
                      </button>
                    </div>
                  </div>
                  
                  <p className="text-xs text-theme-secondary mt-2">
                    Use this token to verify webhook authenticity in your application
                  </p>
                </div>
              </div>

              {/* Event Types */}
              <div>
                <h3 className="text-lg font-semibold text-theme-primary mb-4">Subscribed Events</h3>
                <div className="flex flex-wrap gap-2">
                  {webhook.event_types.map((eventType) => (
                    <span
                      key={eventType}
                      className="px-3 py-1 bg-theme-interactive-primary bg-opacity-10 text-theme-interactive-primary rounded-full text-sm"
                    >
                      {webhooksApi.formatEventType(eventType)}
                    </span>
                  ))}
                </div>
              </div>
            </div>
          )}

          {activeTab === 'deliveries' && (
            <div className="space-y-4">
              <div className="flex items-center justify-between">
                <h3 className="text-lg font-semibold text-theme-primary">Recent Deliveries</h3>
                <button
                  onClick={() => loadDeliveries(deliveryFilters.page)}
                  disabled={loadingDeliveries}
                  className="bg-theme-surface text-theme-secondary px-3 py-1.5 rounded border border-theme hover:bg-theme-surface-hover transition-all duration-200 flex items-center gap-2 disabled:opacity-50"
                >
                  <RefreshCw className={`w-4 h-4 ${loadingDeliveries ? 'animate-spin' : ''}`} />
                  Refresh
                </button>
              </div>

              {loadingDeliveries ? (
                <div className="flex justify-center py-8">
                  <LoadingSpinner size="lg" />
                </div>
              ) : deliveries.length === 0 ? (
                <div className="text-center py-8">
                  <Activity className="w-12 h-12 text-theme-tertiary mx-auto mb-4" />
                  <h4 className="text-lg font-medium text-theme-primary mb-2">No deliveries yet</h4>
                  <p className="text-theme-secondary">
                    Webhook deliveries will appear here once events are triggered
                  </p>
                </div>
              ) : (
                <>
                  <div className="space-y-2">
                    {deliveries.map((delivery) => (
                      <div key={delivery.id} className="border border-theme rounded-lg p-4 hover:bg-theme-surface-hover transition-colors duration-200">
                        <div className="flex items-start justify-between">
                          <div className="flex-1">
                            <div className="flex items-center gap-3 mb-2">
                              <span className={`inline-flex items-center px-2 py-1 rounded-full text-xs font-medium ${
                                webhooksApi.getDeliveryStatusColor(delivery.status)
                              }`}>
                                {delivery.status === 'successful' && <CheckCircle className="w-3 h-3 mr-1" />}
                                {delivery.status === 'failed' && <AlertTriangle className="w-3 h-3 mr-1" />}
                                {delivery.status === 'pending' && <Clock className="w-3 h-3 mr-1" />}
                                {delivery.status.replace('_', ' ').charAt(0).toUpperCase() + delivery.status.replace('_', ' ').slice(1)}
                              </span>
                              
                              <span className="text-sm font-medium text-theme-primary">
                                {webhooksApi.formatEventType(delivery.event_type)}
                              </span>
                              
                              {delivery.http_status && (
                                <span className={`text-sm px-2 py-0.5 rounded ${
                                  delivery.http_status >= 200 && delivery.http_status < 300
                                    ? 'bg-theme-success bg-opacity-10 text-theme-success'
                                    : delivery.http_status >= 400 && delivery.http_status < 500
                                    ? 'bg-theme-warning bg-opacity-10 text-theme-warning'
                                    : 'bg-theme-error bg-opacity-10 text-theme-error'
                                }`}>
                                  {delivery.http_status}
                                </span>
                              )}
                            </div>
                            
                            <div className="flex items-center gap-4 text-sm text-theme-secondary">
                              <span>
                                {new Date(delivery.created_at).toLocaleString()}
                              </span>
                              
                              {delivery.response_time_ms && (
                                <span>
                                  {delivery.response_time_ms}ms
                                </span>
                              )}
                              
                              <span>
                                Attempt {delivery.attempt_count}
                              </span>
                            </div>
                            
                            {delivery.error_message && (
                              <p className="text-sm text-theme-error mt-2">
                                {delivery.error_message}
                              </p>
                            )}
                          </div>
                        </div>
                      </div>
                    ))}
                  </div>

                  {deliveryPagination.total_pages > 1 && (
                    <div className="flex justify-center pt-4">
                      <Pagination
                        currentPage={deliveryPagination.current_page}
                        totalPages={deliveryPagination.total_pages}
                        onPageChange={handleDeliveryPageChange}
                      />
                    </div>
                  )}
                </>
              )}
            </div>
          )}

          {activeTab === 'test' && (
            <WebhookTest
              webhook={webhook}
              onSuccess={(message) => setSuccess(message)}
              onError={(error) => setError(error)}
            />
          )}
        </div>
      </div>

      {/* Test Modal */}
      {showTestModal && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
          <div className="bg-theme-surface rounded-lg border border-theme max-w-2xl w-full max-h-[90vh] overflow-y-auto">
            <div className="p-6">
              <div className="flex items-center justify-between mb-4">
                <h3 className="text-xl font-semibold text-theme-primary">Test Webhook</h3>
                <button
                  onClick={() => setShowTestModal(false)}
                  className="text-theme-secondary hover:text-theme-primary transition-colors duration-200"
                >
                  <X className="w-6 h-6" />
                </button>
              </div>
              
              <WebhookTest
                webhook={webhook}
                onSuccess={(message) => {
                  setSuccess(message);
                  setShowTestModal(false);
                }}
                onError={(error) => {
                  setError(error);
                  setShowTestModal(false);
                }}
              />
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default WebhookDetails;