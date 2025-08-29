import React, { useState, useEffect, useCallback } from 'react';
import { Button } from '@/shared/components/ui/Button';
// Removed unused FormField import
import { 
  Key, Plus, Copy, Eye, Trash2, RotateCcw, 
  Shield, Clock, Activity, AlertTriangle,
  Search
} from 'lucide-react';
import { apiKeysApi, ApiKey, DetailedApiKey, ApiKeyFormData, ApiKeyStats } from '@/features/api-keys/services/apiKeysApi';
import { useNotification } from '@/shared/hooks/useNotification';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';

interface ApiKeysManagerProps {
  showStats?: boolean;
  showFilters?: boolean;
}

interface CreateApiKeyModalProps {
  isOpen: boolean;
  onClose: () => void;
  onApiKeyCreated: (apiKey: DetailedApiKey) => void;
}

interface ApiKeyDetailsModalProps {
  apiKey: DetailedApiKey | null;
  isOpen: boolean;
  onClose: () => void;
  onApiKeyUpdated: () => void;
}

const CreateApiKeyModal: React.FC<CreateApiKeyModalProps> = ({
  isOpen,
  onClose,
  onApiKeyCreated
}) => {
  const [formData, setFormData] = useState<ApiKeyFormData>(apiKeysApi.getDefaultFormData());
  const [availableScopes, setAvailableScopes] = useState<string[]>([]);
  const [scopeDescriptions, setScopeDescriptions] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(false);
  const [errors, setErrors] = useState<string[]>([]);
  
  const { showNotification } = useNotification();

  useEffect(() => {
    if (isOpen) {
      loadAvailableScopes();
    }
  }, [isOpen]);

  const loadAvailableScopes = async () => {
    try {
      const response = await apiKeysApi.getAvailableScopes();
      if (response.success) {
        setAvailableScopes(response.data.scopes);
        setScopeDescriptions(response.data.scope_descriptions);
      }
    } catch (error) {
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    
    const validationErrors = apiKeysApi.validateApiKeyData(formData);
    if (validationErrors.length > 0) {
      setErrors(validationErrors);
      return;
    }

    try {
      setLoading(true);
      setErrors([]);
      const response = await apiKeysApi.createApiKey(formData);
      
      if (response.success && response.data) {
        showNotification('API key created successfully', 'success');
        onApiKeyCreated(response.data);
        onClose();
        setFormData(apiKeysApi.getDefaultFormData());
      } else {
        setErrors([response.error || 'Failed to create API key']);
      }
    } catch (error) {
      setErrors(['Failed to create API key']);
    } finally {
      setLoading(false);
    }
  };

  const toggleScope = (scope: string) => {
    setFormData(prev => ({
      ...prev,
      scopes: prev.scopes.includes(scope)
        ? prev.scopes.filter(s => s !== scope)
        : [...prev.scopes, scope]
    }));
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4 z-50">
      <div className="bg-theme-surface rounded-lg shadow-xl max-w-2xl w-full max-h-[90vh] overflow-hidden">
        <div className="px-6 py-4 border-b border-theme">
          <h3 className="text-lg font-semibold text-theme-primary">Create API Key</h3>
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
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Name *
                </label>
                <input
                  type="text"
                  value={formData.name}
                  onChange={(e) => setFormData(prev => ({ ...prev, name: e.target.value }))}
                  className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                  placeholder="My API Key"
                  required
                />
              </div>
              
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Expires At
                </label>
                <input
                  type="datetime-local"
                  value={formData.expires_at || ''}
                  onChange={(e) => setFormData(prev => ({ ...prev, expires_at: e.target.value || undefined }))}
                  className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                />
              </div>
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
                placeholder="Optional description of what this key is used for"
              />
            </div>

            {/* Rate Limits */}
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Hourly Rate Limit
                </label>
                <input
                  type="number"
                  value={formData.rate_limit_per_hour || ''}
                  onChange={(e) => setFormData(prev => ({ ...prev, rate_limit_per_hour: parseInt(e.target.value) || undefined }))}
                  className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                  placeholder="1000"
                  min="1"
                  max="10000"
                />
              </div>
              
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Daily Rate Limit
                </label>
                <input
                  type="number"
                  value={formData.rate_limit_per_day || ''}
                  onChange={(e) => setFormData(prev => ({ ...prev, rate_limit_per_day: parseInt(e.target.value) || undefined }))}
                  className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                  placeholder="10000"
                  min="1"
                  max="1000000"
                />
              </div>
            </div>

            {/* Scopes */}
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-3">
                Permissions (Scopes) *
              </label>
              <div className="space-y-3 max-h-60 overflow-y-auto border border-theme rounded-lg p-3">
                {availableScopes.map((scope) => (
                  <label key={scope} className="flex items-start gap-3 cursor-pointer">
                    <input
                      type="checkbox"
                      checked={formData.scopes.includes(scope)}
                      onChange={() => toggleScope(scope)}
                      className="mt-1 w-4 h-4 text-theme-interactive-primary border-theme rounded focus:ring-theme-interactive-primary"
                    />
                    <div className="flex-1">
                      <div className="flex items-center gap-2">
                        <span className="font-medium text-theme-primary">
                          {apiKeysApi.formatScope(scope)}
                        </span>
                        <span className={`px-2 py-1 text-xs rounded-full ${apiKeysApi.getScopeCategoryColor(scope)}`}>
                          {apiKeysApi.getScopeCategory(scope)}
                        </span>
                      </div>
                      {scopeDescriptions && Object.prototype.hasOwnProperty.call(scopeDescriptions, scope) && scopeDescriptions[scope as keyof typeof scopeDescriptions] && (
                        <p className="text-sm text-theme-secondary mt-1">
                          {Object.prototype.hasOwnProperty.call(scopeDescriptions, scope) ? scopeDescriptions[scope as keyof typeof scopeDescriptions] : ''}
                        </p>
                      )}
                    </div>
                  </label>
                ))}
              </div>
            </div>

            {/* IP Restrictions */}
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Allowed IP Addresses (Optional)
              </label>
              <textarea
                value={formData.allowed_ips?.join('\n') || ''}
                onChange={(e) => setFormData(prev => ({ 
                  ...prev, 
                  allowed_ips: e.target.value.split('\n').filter(ip => ip.trim()) 
                }))}
                className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                rows={3}
                placeholder="192.168.1.1&#10;10.0.0.0/8&#10;Leave empty to allow all IPs"
              />
              <p className="text-xs text-theme-secondary mt-1">
                Enter one IP address or CIDR block per line. Leave empty to allow all IPs.
              </p>
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
                <Key className="w-4 h-4" />
                Create API Key
              </>
            )}
          </Button>
        </div>
      </div>
    </div>
  );
};

const ApiKeyDetailsModal: React.FC<ApiKeyDetailsModalProps> = ({
  apiKey,
  isOpen,
  onClose,
  onApiKeyUpdated: _onApiKeyUpdated
}) => {
  if (!isOpen || !apiKey) return null;

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4 z-50">
      <div className="bg-theme-surface rounded-lg shadow-xl max-w-4xl w-full max-h-[90vh] overflow-hidden">
        <div className="px-6 py-4 border-b border-theme flex items-center justify-between">
          <h3 className="text-lg font-semibold text-theme-primary">{apiKey.name}</h3>
          <Button onClick={onClose} variant="outline">
            <Eye className="w-5 h-5" />
          </Button>
        </div>
        
        <div className="overflow-auto max-h-[calc(90vh-140px)] p-6">
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            {/* Key Info */}
            <div className="space-y-4">
              <div>
                <h4 className="font-medium text-theme-primary mb-3">Key Information</h4>
                <div className="space-y-3">
                  <div>
                    <label className="text-sm text-theme-secondary">Status</label>
                    <div className={`inline-flex px-2 py-1 text-xs rounded-full ${apiKeysApi.getStatusColor(apiKey.status)}`}>
                      {apiKeysApi.getStatusText(apiKey.status)}
                    </div>
                  </div>
                  
                  <div>
                    <label className="text-sm text-theme-secondary">Created</label>
                    <p className="text-theme-primary">{new Date(apiKey.created_at).toLocaleString()}</p>
                  </div>
                  
                  {apiKey.expires_at && (
                    <div>
                      <label className="text-sm text-theme-secondary">Expires</label>
                      <p className="text-theme-primary">{new Date(apiKey.expires_at).toLocaleString()}</p>
                    </div>
                  )}
                  
                  {apiKey.last_used_at && (
                    <div>
                      <label className="text-sm text-theme-secondary">Last Used</label>
                      <p className="text-theme-primary">{new Date(apiKey.last_used_at).toLocaleString()}</p>
                    </div>
                  )}
                  
                  <div>
                    <label className="text-sm text-theme-secondary">Total Usage</label>
                    <p className="text-theme-primary">{apiKeysApi.formatUsageCount(apiKey.usage_count)} requests</p>
                  </div>
                </div>
              </div>

              {/* Scopes */}
              <div>
                <h4 className="font-medium text-theme-primary mb-3">Permissions</h4>
                <div className="space-y-2">
                  {apiKey.scopes.map((scope) => (
                    <div key={scope} className={`inline-flex px-2 py-1 text-xs rounded-full mr-2 mb-2 ${apiKeysApi.getScopeCategoryColor(scope)}`}>
                      {apiKeysApi.formatScope(scope)}
                    </div>
                  ))}
                </div>
              </div>
            </div>

            {/* Usage Stats */}
            <div className="space-y-4">
              <div>
                <h4 className="font-medium text-theme-primary mb-3">Usage Statistics</h4>
                {apiKey.usage_stats && (
                  <div className="grid grid-cols-2 gap-4">
                    <div className="bg-theme-background p-3 rounded-lg">
                      <div className="text-sm text-theme-secondary">Today</div>
                      <div className="text-lg font-semibold text-theme-primary">
                        {apiKey.usage_stats.requests_today}
                      </div>
                    </div>
                    
                    <div className="bg-theme-background p-3 rounded-lg">
                      <div className="text-sm text-theme-secondary">This Week</div>
                      <div className="text-lg font-semibold text-theme-primary">
                        {apiKey.usage_stats.requests_this_week}
                      </div>
                    </div>
                    
                    <div className="bg-theme-background p-3 rounded-lg">
                      <div className="text-sm text-theme-secondary">This Month</div>
                      <div className="text-lg font-semibold text-theme-primary">
                        {apiKey.usage_stats.requests_this_month}
                      </div>
                    </div>
                    
                    <div className="bg-theme-background p-3 rounded-lg">
                      <div className="text-sm text-theme-secondary">Daily Average</div>
                      <div className="text-lg font-semibold text-theme-primary">
                        {Math.round(apiKey.usage_stats.average_requests_per_day)}
                      </div>
                    </div>
                  </div>
                )}
              </div>

              {/* Rate Limits */}
              {(apiKey.rate_limit_per_hour || apiKey.rate_limit_per_day) && (
                <div>
                  <h4 className="font-medium text-theme-primary mb-3">Rate Limits</h4>
                  <div className="space-y-2">
                    {apiKey.rate_limit_per_hour && (
                      <div className="flex justify-between">
                        <span className="text-theme-secondary">Per Hour</span>
                        <span className="text-theme-primary">{apiKey.rate_limit_per_hour.toLocaleString()}</span>
                      </div>
                    )}
                    {apiKey.rate_limit_per_day && (
                      <div className="flex justify-between">
                        <span className="text-theme-secondary">Per Day</span>
                        <span className="text-theme-primary">{apiKey.rate_limit_per_day.toLocaleString()}</span>
                      </div>
                    )}
                  </div>
                </div>
              )}

              {/* IP Restrictions */}
              {apiKey.allowed_ips && apiKey.allowed_ips.length > 0 && (
                <div>
                  <h4 className="font-medium text-theme-primary mb-3">Allowed IPs</h4>
                  <div className="space-y-1">
                    {apiKey.allowed_ips.map((ip, index) => (
                      <div key={index} className="text-sm text-theme-secondary font-mono bg-theme-background px-2 py-1 rounded">
                        {ip}
                      </div>
                    ))}
                  </div>
                </div>
              )}
            </div>
          </div>

          {/* Recent Usage */}
          {apiKey.recent_usage && apiKey.recent_usage.length > 0 && (
            <div className="mt-6">
              <h4 className="font-medium text-theme-primary mb-3">Recent Activity</h4>
              <div className="overflow-x-auto">
                <table className="w-full">
                  <thead>
                    <tr className="border-b border-theme">
                      <th className="text-left text-sm text-theme-secondary pb-2">Endpoint</th>
                      <th className="text-left text-sm text-theme-secondary pb-2">Method</th>
                      <th className="text-left text-sm text-theme-secondary pb-2">Status</th>
                      <th className="text-left text-sm text-theme-secondary pb-2">Requests</th>
                      <th className="text-left text-sm text-theme-secondary pb-2">Time</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-theme">
                    {apiKey.recent_usage.slice(0, 10).map((usage) => (
                      <tr key={usage.id}>
                        <td className="py-2 text-sm text-theme-primary font-mono">{usage.endpoint}</td>
                        <td className="py-2 text-sm text-theme-secondary">{usage.method}</td>
                        <td className="py-2">
                          <span className={`text-xs px-2 py-1 rounded ${
                            usage.status_code < 300 ? 'bg-theme-success-background text-theme-success' :
                            usage.status_code < 400 ? 'bg-theme-warning-background text-theme-warning' :
                            'bg-theme-error-background text-theme-error'
                          }`}>
                            {usage.status_code}
                          </span>
                        </td>
                        <td className="py-2 text-sm text-theme-primary">{usage.request_count}</td>
                        <td className="py-2 text-sm text-theme-secondary">
                          {new Date(usage.created_at).toLocaleString()}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
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

export const ApiKeysManager: React.FC<ApiKeysManagerProps> = ({
  showStats = true,
  showFilters: _showFilters = true
}) => {
  const [apiKeys, setApiKeys] = useState<ApiKey[]>([]);
  const [stats, setStats] = useState<ApiKeyStats | null>(null);
  const [loading, setLoading] = useState(true);
  const [actionLoading, setActionLoading] = useState<Record<string, boolean>>({});
  const [currentPage, setCurrentPage] = useState(1);
  const [totalPages, setTotalPages] = useState(1);
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedApiKey, setSelectedApiKey] = useState<DetailedApiKey | null>(null);
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [showDetailsModal, setShowDetailsModal] = useState(false);
  const [showSecretApiKey, setShowSecretApiKey] = useState<DetailedApiKey | null>(null);
  
  const { showNotification } = useNotification();
  const perPage = 20;

  const loadApiKeys = useCallback(async () => {
    try {
      setLoading(true);
      const response = await apiKeysApi.getApiKeys(currentPage, perPage);
      
      if (response.success) {
        setApiKeys(response.data.api_keys);
        setTotalPages(response.data.pagination.total_pages);
        if (showStats) {
          setStats(response.data.stats);
        }
      } else {
        showNotification(response.error || 'Failed to load API keys', 'error');
      }
    } catch (error) {
      showNotification('Failed to load API keys', 'error');
    } finally {
      setLoading(false);
    }
  }, [currentPage, perPage, showStats, showNotification]);

  useEffect(() => {
    loadApiKeys();
  }, [loadApiKeys]);

  const handleAction = async (action: string, apiKeyId: string) => {
    try {
      setActionLoading(prev => ({ ...prev, [apiKeyId]: true }));
      let response;
      
      switch (action) {
        case 'toggle':
          response = await apiKeysApi.toggleStatus(apiKeyId);
          break;
        case 'regenerate':
          if (!window.confirm('This will invalidate the existing key. Continue?')) {
            return;
          }
          response = await apiKeysApi.regenerateApiKey(apiKeyId);
          if (response.success && response.data) {
            setShowSecretApiKey(response.data);
          }
          break;
        case 'delete':
          if (!window.confirm('Are you sure you want to delete this API key? This cannot be undone.')) {
            return;
          }
          response = await apiKeysApi.deleteApiKey(apiKeyId);
          break;
        default:
          throw new Error('Unknown action');
      }
      
      if (response.success) {
        showNotification(response.message || 'Action completed successfully', 'success');
        await loadApiKeys();
      } else {
        showNotification(response.error || 'Action failed', 'error');
      }
    } catch (error) {
      showNotification('Action failed', 'error');
    } finally {
      setActionLoading(prev => ({ ...prev, [apiKeyId]: false }));
    }
  };

  const handleViewDetails = async (apiKey: ApiKey) => {
    try {
      const response = await apiKeysApi.getApiKey(apiKey.id);
      if (response.success && response.data) {
        setSelectedApiKey(response.data);
        setShowDetailsModal(true);
      } else {
        showNotification('Failed to load API key details', 'error');
      }
    } catch (error) {
      showNotification('Failed to load API key details', 'error');
    }
  };

  const copyApiKey = async (apiKey: string) => {
    const success = await apiKeysApi.copyToClipboard(apiKey);
    if (success) {
      showNotification('API key copied to clipboard', 'success');
    } else {
      showNotification('Failed to copy API key', 'error');
    }
  };

  const filteredApiKeys = apiKeys.filter(apiKey =>
    searchTerm === '' || 
    apiKey.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
    apiKey.description?.toLowerCase().includes(searchTerm.toLowerCase()) ||
    apiKey.masked_key.includes(searchTerm)
  );

  return (
    <div className="space-y-6">
      {/* Stats Cards */}
      {showStats && stats && (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          <div className="bg-theme-surface rounded-lg border border-theme p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-secondary">Total Keys</p>
                <p className="text-2xl font-semibold text-theme-primary">{stats.total_keys}</p>
              </div>
              <Key className="w-8 h-8 text-theme-secondary" />
            </div>
          </div>
          
          <div className="bg-theme-surface rounded-lg border border-theme p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-secondary">Active</p>
                <p className="text-2xl font-semibold text-theme-success">{stats.active_keys}</p>
              </div>
              <Shield className="w-8 h-8 text-theme-success" />
            </div>
          </div>
          
          <div className="bg-theme-surface rounded-lg border border-theme p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-secondary">Requests Today</p>
                <p className="text-2xl font-semibold text-theme-primary">
                  {apiKeysApi.formatUsageCount(stats.requests_today)}
                </p>
              </div>
              <Activity className="w-8 h-8 text-theme-info" />
            </div>
          </div>
          
          <div className="bg-theme-surface rounded-lg border border-theme p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-secondary">Revoked</p>
                <p className="text-2xl font-semibold text-theme-error">{stats.revoked_keys}</p>
              </div>
              <AlertTriangle className="w-8 h-8 text-theme-error" />
            </div>
          </div>
        </div>
      )}

      {/* Header and Controls */}
      <div className="flex flex-col sm:flex-row gap-4 justify-between">
        <div>
          <h3 className="text-lg font-semibold text-theme-primary">API Keys</h3>
          <p className="text-sm text-theme-secondary">
            Manage API keys for programmatic access
          </p>
        </div>
        
        <div className="flex items-center gap-2">
          {/* Search */}
          <div className="relative">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 w-4 h-4 text-theme-secondary" />
            <input
              type="text"
              placeholder="Search API keys..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="pl-10 pr-4 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
            />
          </div>
          
          <Button 
            variant="outline" 
            onClick={() => setShowCreateModal(true)}
            className="px-4 py-2 bg-theme-interactive-primary text-white rounded-md hover:bg-theme-interactive-primary-hover transition-colors flex items-center gap-2"
          >
            <Plus className="w-4 h-4" />
            Create API Key
          </Button>
        </div>
      </div>

      {/* API Keys Table */}
      <div className="bg-theme-surface rounded-lg border border-theme overflow-hidden">
        {loading ? (
          <div className="flex items-center justify-center py-12">
            <LoadingSpinner size="lg" />
          </div>
        ) : filteredApiKeys.length === 0 ? (
          <div className="text-center py-12">
            <Key className="w-12 h-12 text-theme-secondary mx-auto mb-4" />
            <h4 className="text-lg font-medium text-theme-primary mb-2">No API Keys Found</h4>
            <p className="text-theme-secondary mb-4">
              {searchTerm ? 'No API keys match your search criteria.' : 'Create your first API key to get started.'}
            </p>
            {!searchTerm && (
              <Button 
                variant="outline" 
                onClick={() => setShowCreateModal(true)}
                className="px-4 py-2 bg-theme-interactive-primary text-white rounded-md hover:bg-theme-interactive-primary-hover transition-colors"
              >
                Create Your First API Key
              </Button>
            )}
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead className="bg-theme-background">
                <tr>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    Name
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    Key
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    Status
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    Usage
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    Last Used
                  </th>
                  <th className="px-6 py-3 text-right text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody className="divide-y divide-theme">
                {filteredApiKeys.map((apiKey) => (
                  <tr key={apiKey.id} className="hover:bg-theme-background transition-colors">
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div>
                        <div className="text-sm font-medium text-theme-primary">
                          {apiKey.name}
                        </div>
                        {apiKey.description && (
                          <div className="text-sm text-theme-secondary">
                            {apiKey.description}
                          </div>
                        )}
                        <div className="flex flex-wrap gap-1 mt-1">
                          {apiKey.scopes.slice(0, 2).map((scope) => (
                            <span key={scope} className={`text-xs px-2 py-1 rounded ${apiKeysApi.getScopeCategoryColor(scope)}`}>
                              {scope.split(':')[0]}
                            </span>
                          ))}
                          {apiKey.scopes.length > 2 && (
                            <span className="text-xs px-2 py-1 rounded bg-theme-surface text-theme-secondary">
                              +{apiKey.scopes.length - 2}
                            </span>
                          )}
                        </div>
                      </div>
                    </td>
                    
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="flex items-center gap-2">
                        <code className="text-sm font-mono text-theme-secondary bg-theme-background px-2 py-1 rounded">
                          {apiKey.masked_key}
                        </code>
                        <Button 
                          variant="outline" 
                          onClick={() => copyApiKey(apiKey.masked_key)}
                          className="p-1 text-theme-secondary hover:text-theme-primary transition-colors"
                          title="Copy Key"
                        >
                          <Copy className="w-4 h-4" />
                        </Button>
                      </div>
                    </td>
                    
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="space-y-1">
                        <span className={`inline-flex px-2 py-1 text-xs font-semibold rounded-full ${apiKeysApi.getStatusColor(apiKey.status)}`}>
                          {apiKeysApi.getStatusText(apiKey.status)}
                        </span>
                        {apiKeysApi.isKeyExpiringSoon(apiKey) && (
                          <div className="flex items-center gap-1 text-xs text-theme-warning">
                            <Clock className="w-3 h-3" />
                            Expires soon
                          </div>
                        )}
                      </div>
                    </td>
                    
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-primary">
                      {apiKeysApi.formatUsageCount(apiKey.usage_count)} requests
                    </td>
                    
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-secondary">
                      {apiKey.last_used_at 
                        ? new Date(apiKey.last_used_at).toLocaleDateString()
                        : 'Never'
                      }
                    </td>
                    
                    <td className="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                      <div className="flex items-center justify-end gap-2">
                        <Button 
                          variant="outline" 
                          onClick={() => handleViewDetails(apiKey)}
                          className="p-2 text-theme-secondary hover:text-theme-primary transition-colors"
                          title="View Details"
                        >
                          <Eye className="w-4 h-4" />
                        </Button>
                        
                        <Button 
                          variant="outline" 
                          onClick={() => handleAction('toggle', apiKey.id)}
                          disabled={actionLoading[apiKey.id]}
                          className="p-2 text-theme-secondary hover:text-theme-primary transition-colors disabled:opacity-50"
                          title={apiKey.status === 'active' ? 'Revoke' : 'Activate'}
                        >
                          {actionLoading[apiKey.id] ? (
                            <LoadingSpinner size="sm" />
                          ) : (
                            <Shield className="w-4 h-4" />
                          )}
                        </Button>
                        
                        <Button 
                          variant="outline" 
                          onClick={() => handleAction('regenerate', apiKey.id)}
                          disabled={actionLoading[apiKey.id]}
                          className="p-2 text-theme-secondary hover:text-theme-primary transition-colors disabled:opacity-50"
                          title="Regenerate"
                        >
                          <RotateCcw className="w-4 h-4" />
                        </Button>
                        
                        <Button 
                          variant="outline" 
                          onClick={() => handleAction('delete', apiKey.id)}
                          disabled={actionLoading[apiKey.id]}
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
            <Button 
              variant="outline" 
              onClick={() => setCurrentPage(prev => Math.max(1, prev - 1))}
              disabled={currentPage === 1}
              className="px-3 py-2 border border-theme rounded-md text-theme-primary hover:bg-theme-surface disabled:opacity-50 disabled:cursor-not-allowed"
            >
              Previous
            </Button>
            <Button 
              variant="outline" 
              onClick={() => setCurrentPage(prev => Math.min(totalPages, prev + 1))}
              disabled={currentPage === totalPages}
              className="px-3 py-2 border border-theme rounded-md text-theme-primary hover:bg-theme-surface disabled:opacity-50 disabled:cursor-not-allowed"
            >
              Next
            </Button>
          </div>
        </div>
      )}

      {/* Modals */}
      <CreateApiKeyModal
        isOpen={showCreateModal}
        onClose={() => setShowCreateModal(false)}
        onApiKeyCreated={(apiKey) => {
          setShowSecretApiKey(apiKey);
          loadApiKeys();
        }}
      />

      <ApiKeyDetailsModal
        apiKey={selectedApiKey}
        isOpen={showDetailsModal}
        onClose={() => {
          setShowDetailsModal(false);
          setSelectedApiKey(null);
        }}
        onApiKeyUpdated={loadApiKeys}
      />

      {/* Secret API Key Modal */}
      {showSecretApiKey && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4 z-50">
          <div className="bg-theme-surface rounded-lg shadow-xl max-w-md w-full">
            <div className="px-6 py-4 border-b border-theme">
              <h3 className="text-lg font-semibold text-theme-primary">API Key Created</h3>
            </div>
            
            <div className="px-6 py-4">
              <div className="mb-4">
                <div className="bg-theme-warning-background border border-theme-warning rounded-lg p-4 mb-4">
                  <div className="flex items-center gap-2 mb-2">
                    <AlertTriangle className="w-5 h-5 text-theme-warning" />
                    <span className="font-medium text-theme-warning">Important!</span>
                  </div>
                  <p className="text-sm text-theme-warning">
                    This is the only time you'll be able to see this API key. Make sure to copy it now.
                  </p>
                </div>
                
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  API Key
                </label>
                <div className="flex items-center gap-2">
                  <input
                    type="text"
                    value={showSecretApiKey.key_value || ''}
                    readOnly
                    className="flex-1 px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary"
                  />
                  <Button 
                    variant="outline" 
                    onClick={() => copyApiKey(showSecretApiKey.key_value || '')}
                    className="px-3 py-2 bg-theme-interactive-primary text-white rounded-md hover:bg-theme-interactive-primary-hover transition-colors flex items-center gap-2"
                  >
                    <Copy className="w-4 h-4" />
                    Copy
                  </Button>
                </div>
              </div>
            </div>

            <div className="px-6 py-4 border-t border-theme flex justify-end">
              <Button 
                variant="outline" 
                onClick={() => setShowSecretApiKey(null)}
                className="px-4 py-2 bg-theme-interactive-primary text-white rounded-md hover:bg-theme-interactive-primary-hover transition-colors"
              >
                I've Copied It
              </Button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default ApiKeysManager;