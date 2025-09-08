import React, { useEffect, useState } from 'react';
import { apiKeysApi } from '@/features/api-keys/services/apiKeysApi';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { ApiKeyModal } from '@/features/api-keys/components/ApiKeyModal';
import { Key, RefreshCw } from 'lucide-react';

export const ApiKeysPage: React.FC = () => {
  const [apiKeys, setApiKeys] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [showModal, setShowModal] = useState(false);
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
    } finally {
      setLoading(false);
    }
  };

  const handleGenerateKey = () => {
    setShowModal(true);
  };

  const handleModalClose = () => {
    setShowModal(false);
  };

  const handleModalSuccess = () => {
    setShowModal(false);
    loadApiKeys(); // Refresh the API keys list
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

  const pageActions: PageAction[] = [
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: loadApiKeys,
      variant: 'secondary',
      icon: RefreshCw,
      disabled: loading
    },
    {
      id: 'generate-key',
      label: 'Generate New Key',
      onClick: handleGenerateKey,
      variant: 'primary',
      icon: Key
    }
  ];

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app', icon: '🏠' },
    { label: 'System', icon: '⚙️' },
    { label: 'API Keys', icon: '🔑' }
  ];

  const getPageDescription = () => {
    if (loading) return "Loading API keys...";
    if (error) return "Error loading API keys";
    return "Manage API keys for external integrations";
  };

  const getPageActions = () => {
    if (error) {
      return [{
        id: 'retry',
        label: 'Retry',
        onClick: loadApiKeys,
        variant: 'primary' as const
      }];
    }
    return pageActions;
  };

  return (
    <PageContainer
      title="API Key Management"
      description={getPageDescription()}
      breadcrumbs={breadcrumbs}
      actions={getPageActions()}
    >
      {loading ? (
        <div className="flex items-center justify-center h-64">
          <LoadingSpinner />
        </div>
      ) : error ? (
        <div className="bg-theme-error bg-opacity-10 border border-theme-error border-opacity-30 rounded-lg p-6">
          <h3 className="font-medium text-theme-error mb-2">Error Loading API Keys</h3>
          <p className="text-theme-error opacity-80">{error}</p>
        </div>
      ) : (
        <>
          <div className="bg-theme-surface rounded-lg p-6">

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
        </>
      )}
      
      <ApiKeyModal
        isOpen={showModal}
        onClose={handleModalClose}
        onSuccess={handleModalSuccess}
      />
    </PageContainer>
  );
};