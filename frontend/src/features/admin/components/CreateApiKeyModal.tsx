import React, { useState, useEffect } from 'react';
import { Button } from '@/shared/components/ui/Button';
import { Key, AlertTriangle } from 'lucide-react';
import { apiKeysApi, DetailedApiKey, ApiKeyFormData } from '@/features/devops/api-keys/services/apiKeysApi';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';

export interface CreateApiKeyModalProps {
  isOpen: boolean;
  onClose: () => void;
  onApiKeyCreated: (apiKey: DetailedApiKey) => void;
}

export const CreateApiKeyModal: React.FC<CreateApiKeyModalProps> = ({
  isOpen,
  onClose,
  onApiKeyCreated
}) => {
  const [formData, setFormData] = useState<ApiKeyFormData>(apiKeysApi.getDefaultFormData());
  const [availableScopes, setAvailableScopes] = useState<string[]>([]);
  const [scopeDescriptions, setScopeDescriptions] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(false);
  const [errors, setErrors] = useState<string[]>([]);

  const { showNotification } = useNotifications();

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
    } catch (_error) {
      // Silently handle - not critical
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
    } catch (_error) {
      setErrors(['Failed to create API key']);
    } finally {
      setLoading(false);
    }
  };

  const toggleScope = (scope: string) => {
    setFormData((prev: ApiKeyFormData) => ({
      ...prev,
      scopes: prev.scopes.includes(scope)
        ? prev.scopes.filter((s: string) => s !== scope)
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
                  onChange={(e) => setFormData((prev: ApiKeyFormData) => ({ ...prev, name: e.target.value }))}
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
                  onChange={(e) => setFormData((prev: ApiKeyFormData) => ({ ...prev, expires_at: e.target.value || undefined }))}
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
                onChange={(e) => setFormData((prev: ApiKeyFormData) => ({ ...prev, description: e.target.value }))}
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
                  onChange={(e) => setFormData((prev: ApiKeyFormData) => ({ ...prev, rate_limit_per_hour: parseInt(e.target.value) || undefined }))}
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
                  onChange={(e) => setFormData((prev: ApiKeyFormData) => ({ ...prev, rate_limit_per_day: parseInt(e.target.value) || undefined }))}
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
                onChange={(e) => setFormData((prev: ApiKeyFormData) => ({
                  ...prev,
                  allowed_ips: e.target.value.split('\n').filter((ip: string) => ip.trim())
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
