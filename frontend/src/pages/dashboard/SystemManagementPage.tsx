import React, { useEffect, useState, useCallback } from 'react';
import { Routes, Route, Navigate } from 'react-router-dom';
import { useSelector } from 'react-redux';
import { RootState } from '../../store';
import { TabNavigation, MobileTabNavigation } from '../../components/ui/TabNavigation';
import { Breadcrumb } from '../../components/ui/Breadcrumb';
import { hasAdminAccess } from '../../utils/permissionUtils';
import { ServicesPage } from './ServicesPage';
import PaymentGatewaysPage from './PaymentGatewaysPage';
import { AdminSettingsPage } from './AdminSettingsPage';
import { auditLogsApi, AuditLog } from '../../services/auditLogsApi';
import { webhooksApi } from '../../services/webhooksApi';
import { apiKeysApi } from '../../services/apiKeysApi';
import { LoadingSpinner } from '../../components/common/LoadingSpinner';

const tabs = [
  { id: 'services', label: 'Services', path: '/dashboard/system/services', icon: '⚡' },
  { id: 'gateways', label: 'Payment Gateways', path: '/dashboard/system/gateways', icon: '💳' },
  { id: 'admin', label: 'Admin Config', path: '/dashboard/system/admin', icon: '🔧' },
  { id: 'audit', label: 'Audit Logs', path: '/dashboard/system/audit', icon: '📝' },
  { id: 'webhooks', label: 'Webhooks', path: '/dashboard/system/webhooks', icon: '🔗' },
  { id: 'api', label: 'API Keys', path: '/dashboard/system/api', icon: '🔑' },
];

const AuditLogsPage: React.FC = () => {
  const [auditLogs, setAuditLogs] = useState<AuditLog[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [filters, setFilters] = useState({
    action_type: 'all',
    date_from: '',
    date_to: ''
  });
  const [pagination, setPagination] = useState({
    page: 1,
    limit: 10,
    total: 0
  });

  const loadAuditLogs = useCallback(async () => {
    try {
      setLoading(true);
      const response = await auditLogsApi.getAuditLogs({
        page: pagination.page,
        limit: pagination.limit,
        ...filters
      });
      
      if (response.success) {
        setAuditLogs(response.data.logs);
        setPagination(prev => ({
          ...prev,
          total: response.data.pagination.total_count
        }));
      } else {
        setError(response.error || 'Failed to load audit logs');
      }
    } catch (err) {
      setError('Failed to load audit logs');
      console.error('Audit logs error:', err);
    } finally {
      setLoading(false);
    }
  }, [pagination.page, pagination.limit, filters]);

  useEffect(() => {
    loadAuditLogs();
  }, [pagination.page, filters, loadAuditLogs]);

  const handleFilterChange = (key: string, value: string) => {
    setFilters(prev => ({ ...prev, [key]: value }));
    setPagination(prev => ({ ...prev, page: 1 }));
  };

  const formatTimestamp = (timestamp: string) => {
    return new Date(timestamp).toLocaleString();
  };

  return (
    <div className="space-y-6">
      <div className="bg-theme-surface rounded-lg p-6">
        <div className="flex justify-between items-center mb-6">
          <div>
            <h2 className="text-xl font-semibold text-theme-primary">Audit Logs</h2>
            <p className="text-theme-secondary mt-1">Track all system activities and changes</p>
          </div>
          <div className="flex space-x-3">
            <select 
              className="px-3 py-2 border border-theme rounded-lg text-theme-primary bg-theme-background"
              value={filters.action_type}
              onChange={(e) => handleFilterChange('action_type', e.target.value)}
            >
              <option value="all">All Actions</option>
              <option value="authentication">Authentication</option>
              <option value="user_management">User Management</option>
              <option value="billing">Billing</option>
              <option value="system_changes">System Changes</option>
            </select>
            <input
              type="date"
              className="px-3 py-2 border border-theme rounded-lg text-theme-primary bg-theme-background"
              value={filters.date_from}
              onChange={(e) => handleFilterChange('date_from', e.target.value)}
            />
            <input
              type="date"
              className="px-3 py-2 border border-theme rounded-lg text-theme-primary bg-theme-background"
              value={filters.date_to}
              onChange={(e) => handleFilterChange('date_to', e.target.value)}
              min={filters.date_from}
            />
            <button 
              className="btn-theme btn-theme-secondary"
              onClick={() => auditLogsApi.exportLogs(filters)}
            >
              Export Logs
            </button>
          </div>
        </div>

        {loading ? (
          <div className="flex items-center justify-center py-8">
            <LoadingSpinner />
          </div>
        ) : error ? (
          <div className="bg-theme-error bg-opacity-10 border border-theme-error rounded-lg p-4">
            <p className="text-theme-error">{error}</p>
            <button 
              onClick={loadAuditLogs}
              className="mt-2 btn-theme btn-theme-secondary"
            >
              Retry
            </button>
          </div>
        ) : (
          <div className="bg-theme-background rounded-lg overflow-hidden">
            <table className="w-full">
              <thead className="bg-theme-surface border-b border-theme">
                <tr>
                  <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Action</th>
                  <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">User</th>
                  <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">IP Address</th>
                  <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Timestamp</th>
                  <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Status</th>
                  <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Details</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-theme">
                {auditLogs.length === 0 ? (
                  <tr>
                    <td colSpan={6} className="py-8 px-4 text-center text-theme-secondary">
                      No audit logs found
                    </td>
                  </tr>
                ) : (
                  auditLogs.map((log) => (
                    <tr key={log.id} className="hover:bg-theme-surface-hover">
                      <td className="py-3 px-4 text-theme-primary font-medium">{log.action}</td>
                      <td className="py-3 px-4 text-theme-secondary">{log.user?.email || 'System'}</td>
                      <td className="py-3 px-4 text-theme-secondary font-mono text-xs">{log.ip_address || 'N/A'}</td>
                      <td className="py-3 px-4 text-theme-secondary text-sm">{formatTimestamp(log.created_at)}</td>
                      <td className="py-3 px-4">
                        <span className={`text-xs px-2 py-1 rounded-full ${
                          log.status === 'success'
                            ? 'bg-theme-success bg-opacity-10 text-theme-success' 
                            : log.status === 'warning'
                            ? 'bg-yellow-500 bg-opacity-10 text-yellow-600'
                            : 'bg-theme-error bg-opacity-10 text-theme-error'
                        }`}>
                          {log.status || 'unknown'}
                        </span>
                      </td>
                      <td className="py-3 px-4">
                        <button 
                          className="text-theme-link hover:text-theme-link-hover text-sm"
                          title={log.message}
                        >
                          View
                        </button>
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        )}

        {!loading && !error && auditLogs.length > 0 && (
          <div className="mt-4 flex items-center justify-between">
            <p className="text-sm text-theme-secondary">
              Showing {((pagination.page - 1) * pagination.limit) + 1} to {Math.min(pagination.page * pagination.limit, pagination.total)} of {pagination.total} entries
            </p>
            <div className="flex space-x-2">
              <button 
                className="px-3 py-1 border border-theme rounded text-theme-primary hover:bg-theme-surface-hover disabled:opacity-50"
                onClick={() => setPagination(prev => ({ ...prev, page: prev.page - 1 }))}
                disabled={pagination.page <= 1}
              >
                Previous
              </button>
              
              {Array.from({ length: Math.min(5, Math.ceil(pagination.total / pagination.limit)) }, (_, i) => {
                const pageNum = pagination.page <= 3 ? i + 1 : pagination.page - 2 + i;
                return (
                  <button 
                    key={pageNum}
                    className={`px-3 py-1 rounded ${
                      pageNum === pagination.page
                        ? 'bg-theme-interactive-primary text-white'
                        : 'border border-theme text-theme-primary hover:bg-theme-surface-hover'
                    }`}
                    onClick={() => setPagination(prev => ({ ...prev, page: pageNum }))}
                  >
                    {pageNum}
                  </button>
                );
              })}
              
              <button 
                className="px-3 py-1 border border-theme rounded text-theme-primary hover:bg-theme-surface-hover disabled:opacity-50"
                onClick={() => setPagination(prev => ({ ...prev, page: prev.page + 1 }))}
                disabled={pagination.page >= Math.ceil(pagination.total / pagination.limit)}
              >
                Next
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

interface Webhook {
  id: string;
  url: string;
  event_types: string[];
  status: 'active' | 'inactive';
  last_delivery_at?: string;
  created_at: string;
}

const WebhooksPage: React.FC = () => {
  const [webhooks, setWebhooks] = useState<Webhook[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [showAddModal, setShowAddModal] = useState(false);

  const loadWebhooks = async () => {
    try {
      setLoading(true);
      const response = await webhooksApi.getWebhooks();
      
      if (response.success) {
        setWebhooks(response.data.webhooks);
      } else {
        setError(response.error || 'Failed to load webhooks');
      }
    } catch (err) {
      setError('Failed to load webhooks');
      console.error('Webhooks error:', err);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadWebhooks();
  }, []);

  const handleToggleStatus = async (webhookId: string, newStatus: 'active' | 'inactive') => {
    try {
      const response = await webhooksApi.updateWebhook(webhookId, { status: newStatus });
      if (response.success) {
        setWebhooks(prev => prev.map(w => 
          w.id === webhookId ? { ...w, status: newStatus } : w
        ));
      }
    } catch (err) {
      console.error('Failed to update webhook status:', err);
    }
  };

  const handleDelete = async (webhookId: string) => {
    if (!window.confirm('Are you sure you want to delete this webhook?')) return;
    
    try {
      const response = await webhooksApi.deleteWebhook(webhookId);
      if (response.success) {
        setWebhooks(prev => prev.filter(w => w.id !== webhookId));
      }
    } catch (err) {
      console.error('Failed to delete webhook:', err);
    }
  };

  return (
    <div className="space-y-6">
      <div className="bg-theme-surface rounded-lg p-6">
        <div className="flex justify-between items-center mb-6">
          <div>
            <h2 className="text-xl font-semibold text-theme-primary">Webhook Management</h2>
            <p className="text-theme-secondary mt-1">Configure webhook endpoints and event subscriptions</p>
          </div>
          <button 
            className="btn-theme btn-theme-primary"
            onClick={() => setShowAddModal(true)}
          >
            Add Webhook
          </button>
        </div>

        {loading ? (
          <div className="flex items-center justify-center py-8">
            <LoadingSpinner />
          </div>
        ) : error ? (
          <div className="bg-theme-error bg-opacity-10 border border-theme-error rounded-lg p-4">
            <p className="text-theme-error">{error}</p>
            <button 
              onClick={loadWebhooks}
              className="mt-2 btn-theme btn-theme-secondary"
            >
              Retry
            </button>
          </div>
        ) : webhooks.length === 0 ? (
          <div className="text-center py-8">
            <p className="text-theme-secondary mb-4">No webhooks configured</p>
            <button 
              className="btn-theme btn-theme-primary"
              onClick={() => setShowAddModal(true)}
            >
              Add Your First Webhook
            </button>
          </div>
        ) : (
          <div className="space-y-4">
            {webhooks.map((webhook) => (
              <div key={webhook.id} className="bg-theme-background rounded-lg p-4 border border-theme">
                <div className="flex items-start justify-between">
                  <div className="flex-1">
                    <div className="flex items-center space-x-3 mb-2">
                      <h3 className="font-medium text-theme-primary">{webhook.url}</h3>
                      <span className={`text-xs px-2 py-1 rounded-full ${
                        webhook.status === 'active' 
                          ? 'bg-theme-success bg-opacity-10 text-theme-success' 
                          : 'bg-theme-surface text-theme-tertiary'
                      }`}>
                        {webhook.status}
                      </span>
                    </div>
                    <div className="flex flex-wrap gap-2 mb-2">
                      {webhook.event_types.map((event) => (
                        <span key={event} className="text-xs bg-theme-surface px-2 py-1 rounded text-theme-secondary">
                          {event}
                        </span>
                      ))}
                    </div>
                    <p className="text-xs text-theme-tertiary">
                      Last triggered: {webhook.last_delivery_at ? new Date(webhook.last_delivery_at).toLocaleString() : 'Never'}
                    </p>
                  </div>
                  <div className="flex space-x-2">
                    <button 
                      className="text-theme-link hover:text-theme-link-hover text-sm"
                      onClick={() => webhooksApi.testWebhook(webhook.id)}
                    >
                      Test
                    </button>
                    <button 
                      className="text-theme-link hover:text-theme-link-hover text-sm"
                      onClick={() => handleToggleStatus(webhook.id, webhook.status === 'active' ? 'inactive' : 'active')}
                    >
                      {webhook.status === 'active' ? 'Disable' : 'Enable'}
                    </button>
                    <button 
                      className="text-theme-error hover:text-theme-error-hover text-sm"
                      onClick={() => handleDelete(webhook.id)}
                    >
                      Delete
                    </button>
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}

        <div className="mt-6 bg-theme-background rounded-lg p-4 border border-theme">
          <h3 className="font-medium text-theme-primary mb-3">Webhook Events</h3>
          <div className="grid grid-cols-2 md:grid-cols-3 gap-3">
            {[
              'payment.success', 'payment.failed', 'payment.refunded',
              'subscription.created', 'subscription.updated', 'subscription.cancelled',
              'user.created', 'user.updated', 'user.deleted',
              'invoice.created', 'invoice.paid', 'invoice.overdue'
            ].map((event) => (
              <label key={event} className="flex items-center space-x-2 text-sm">
                <input type="checkbox" className="rounded border-theme text-theme-interactive-primary" />
                <span className="text-theme-secondary">{event}</span>
              </label>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
};

const ApiKeysPage: React.FC = () => {
  const [apiKeys, setApiKeys] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [stats, setStats] = useState({
    requestsToday: 0,
    apiUptime: '99.9%',
    avgResponseTime: '45ms'
  });

  useEffect(() => {
    loadApiKeys();
  }, []);

  const loadApiKeys = async () => {
    try {
      setLoading(true);
      setError(null);
      const response = await apiKeysApi.getApiKeys();
      
      if (response.success) {
        setApiKeys(response.data.api_keys);
        setStats({
          requestsToday: response.data.stats.requests_today,
          apiUptime: '99.9%', // TODO: Get from backend
          avgResponseTime: '45ms' // TODO: Get from backend
        });
      } else {
        setError(response.error || 'Failed to load API keys');
      }
    } catch (err) {
      setError('Failed to load API keys');
      console.error('API keys error:', err);
    } finally {
      setLoading(false);
    }
  };

  const handleGenerateKey = async () => {
    // TODO: Implement create API key modal/functionality
    alert('Generate new key functionality coming soon!');
  };

  const handleRegenerateKey = async (id: string) => {
    if (!window.confirm('Are you sure you want to regenerate this API key? This will invalidate the current key.')) return;
    
    try {
      const response = await apiKeysApi.regenerateApiKey(id);
      if (response.success) {
        loadApiKeys();
        alert('API key regenerated successfully');
      } else {
        alert(response.error || 'Failed to regenerate API key');
      }
    } catch (err) {
      alert('Failed to regenerate API key');
      console.error('Regenerate API key error:', err);
    }
  };

  const handleToggleStatus = async (id: string) => {
    try {
      const response = await apiKeysApi.toggleStatus(id);
      if (response.success) {
        loadApiKeys();
      } else {
        alert(response.error || 'Failed to update API key status');
      }
    } catch (err) {
      alert('Failed to update API key status');
      console.error('Toggle status error:', err);
    }
  };

  const handleCopyKey = (key: string) => {
    apiKeysApi.copyToClipboard(key).then(success => {
      if (success) {
        alert('API key copied to clipboard');
      } else {
        alert('Failed to copy API key');
      }
    });
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <LoadingSpinner />
      </div>
    );
  }

  if (error) {
    return (
      <div className="bg-theme-error bg-opacity-10 border border-theme-error border-opacity-30 rounded-lg p-6">
        <h3 className="font-medium text-theme-error mb-2">Error Loading API Keys</h3>
        <p className="text-theme-error opacity-80">{error}</p>
        <button 
          onClick={loadApiKeys}
          className="mt-4 btn-theme btn-theme-secondary"
        >
          Retry
        </button>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="bg-theme-surface rounded-lg p-6">
        <div className="flex justify-between items-center mb-6">
          <div>
            <h2 className="text-xl font-semibold text-theme-primary">API Key Management</h2>
            <p className="text-theme-secondary mt-1">Manage API keys for external integrations</p>
          </div>
          <button 
            className="btn-theme btn-theme-primary"
            onClick={handleGenerateKey}
          >
            Generate New Key
          </button>
        </div>

        <div className="bg-theme-warning bg-opacity-10 border border-theme-warning border-opacity-30 rounded-lg p-4 mb-6">
          <div className="flex items-start space-x-3">
            <span className="text-theme-warning text-xl">⚠️</span>
            <div>
              <h3 className="font-medium text-theme-warning">Security Notice</h3>
              <p className="text-sm text-theme-warning opacity-80 mt-1">
                API keys provide full access to your account. Keep them secure and never share them publicly.
                Rotate keys regularly and revoke unused keys immediately.
              </p>
            </div>
          </div>
        </div>

        <div className="space-y-4">
          {apiKeys.length === 0 ? (
            <div className="text-center py-8">
              <div className="text-4xl mb-4">🔑</div>
              <h3 className="text-lg font-medium text-theme-primary mb-2">No API Keys</h3>
              <p className="text-theme-secondary mb-4">Get started by generating your first API key</p>
              <button 
                className="btn-theme btn-theme-primary"
                onClick={handleGenerateKey}
              >
                Generate Your First Key
              </button>
            </div>
          ) : (
            apiKeys.map((apiKey) => (
              <div key={apiKey.id} className="bg-theme-background rounded-lg p-4 border border-theme">
                <div className="flex items-start justify-between">
                  <div className="flex-1">
                    <div className="flex items-center space-x-3 mb-2">
                      <h3 className="font-medium text-theme-primary">{apiKey.name}</h3>
                      <span className={`text-xs px-2 py-1 rounded-full ${apiKeysApi.getStatusColor(apiKey.status)}`}>
                        {apiKeysApi.getStatusText(apiKey.status)}
                      </span>
                    </div>
                    <div className="flex items-center space-x-4 mb-2">
                      <code className="text-sm bg-theme-surface px-2 py-1 rounded font-mono text-theme-secondary">
                        {apiKey.masked_key || apiKeysApi.generateKeyPreview()}
                      </code>
                      <button 
                        className="text-theme-link hover:text-theme-link-hover text-sm"
                        onClick={() => handleCopyKey(apiKey.masked_key)}
                      >
                        Copy
                      </button>
                    </div>
                    <div className="flex space-x-4 text-xs text-theme-tertiary">
                      <span>Created: {new Date(apiKey.created_at).toLocaleDateString()}</span>
                      <span>Last used: {apiKey.last_used_at ? new Date(apiKey.last_used_at).toLocaleString() : 'Never'}</span>
                      <span>Usage: {apiKeysApi.formatUsageCount(apiKey.usage_count)}</span>
                    </div>
                    {apiKey.description && (
                      <p className="text-sm text-theme-secondary mt-2">{apiKey.description}</p>
                    )}
                    {apiKey.scopes && apiKey.scopes.length > 0 && (
                      <div className="flex flex-wrap gap-1 mt-2">
                        {apiKey.scopes.slice(0, 3).map((scope: string) => (
                          <span 
                            key={scope} 
                            className={`text-xs px-2 py-1 rounded ${apiKeysApi.getScopeCategoryColor(scope)}`}
                          >
                            {apiKeysApi.formatScope(scope)}
                          </span>
                        ))}
                        {apiKey.scopes.length > 3 && (
                          <span className="text-xs px-2 py-1 rounded bg-theme-surface text-theme-secondary">
                            +{apiKey.scopes.length - 3} more
                          </span>
                        )}
                      </div>
                    )}
                  </div>
                  <div className="flex space-x-2">
                    <button 
                      className="text-theme-link hover:text-theme-link-hover text-sm"
                      onClick={() => handleRegenerateKey(apiKey.id)}
                    >
                      Regenerate
                    </button>
                    <button 
                      className={`text-sm ${
                        apiKey.status === 'active' 
                          ? 'text-theme-error hover:text-theme-error-hover' 
                          : 'text-theme-success hover:text-theme-success-hover'
                      }`}
                      onClick={() => handleToggleStatus(apiKey.id)}
                    >
                      {apiKey.status === 'active' ? 'Revoke' : 'Activate'}
                    </button>
                  </div>
                </div>
              </div>
            ))
          )}
        </div>

        <div className="mt-6 grid grid-cols-1 md:grid-cols-3 gap-4">
          <div className="bg-theme-background rounded-lg p-4 border border-theme">
            <h3 className="text-2xl font-bold text-theme-primary">
              {apiKeysApi.formatUsageCount(stats.requestsToday)}
            </h3>
            <p className="text-sm text-theme-secondary">API Calls Today</p>
          </div>
          <div className="bg-theme-background rounded-lg p-4 border border-theme">
            <h3 className="text-2xl font-bold text-theme-primary">{stats.apiUptime}</h3>
            <p className="text-sm text-theme-secondary">API Uptime</p>
          </div>
          <div className="bg-theme-background rounded-lg p-4 border border-theme">
            <h3 className="text-2xl font-bold text-theme-primary">{stats.avgResponseTime}</h3>
            <p className="text-sm text-theme-secondary">Avg Response Time</p>
          </div>
        </div>
      </div>
    </div>
  );
};

export const SystemManagementPage: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  const isAdmin = hasAdminAccess(user);

  // Redirect non-admins to dashboard
  if (!isAdmin) {
    return <Navigate to="/dashboard" replace />;
  }

  const breadcrumbItems = [
    { label: 'Dashboard', path: '/dashboard', icon: '🏠' },
    { label: 'System Management', icon: '⚙️' }
  ];

  return (
    <div className="space-y-6">
      <div>
        <Breadcrumb items={breadcrumbItems} className="mb-4" />
        <h1 className="text-2xl font-bold text-theme-primary">System Management</h1>
        <p className="text-theme-secondary mt-1">
          Configure system services, integrations, and administrative settings.
        </p>
      </div>

      <div>
        <div className="hidden sm:block">
          <TabNavigation tabs={tabs} basePath="/dashboard/system" />
        </div>
        <MobileTabNavigation tabs={tabs} basePath="/dashboard/system" />
      </div>

      <div>
        <Routes>
          <Route path="/" element={<Navigate to="/dashboard/system/services" replace />} />
          <Route path="/services" element={<ServicesPage />} />
          <Route path="/gateways" element={<PaymentGatewaysPage />} />
          <Route path="/admin" element={<AdminSettingsPage />} />
          <Route path="/audit" element={<AuditLogsPage />} />
          <Route path="/webhooks" element={<WebhooksPage />} />
          <Route path="/api" element={<ApiKeysPage />} />
        </Routes>
      </div>
    </div>
  );
};

export default SystemManagementPage;