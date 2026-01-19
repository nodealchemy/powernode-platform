import React, { useState, useEffect } from 'react';
import { X, Eye, EyeOff, Copy, CheckCircle, AlertTriangle } from 'lucide-react';
import { ApiKeyFormData, apiKeysApi } from '../services/apiKeysApi';
import { useNotifications } from '@/shared/hooks/useNotifications';

interface ApiKeyModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSuccess: () => void;
}

interface AvailableScope {
  id: string;
  name: string;
  description: string;
  category: string;
}

export const ApiKeyModal: React.FC<ApiKeyModalProps> = ({
  isOpen,
  onClose,
  onSuccess
}) => {
  const [formData, setFormData] = useState<ApiKeyFormData>(apiKeysApi.getDefaultFormData());
  const [availableScopes, setAvailableScopes] = useState<AvailableScope[]>([]);
  const [loading, setLoading] = useState(false);
  const [createdApiKey, setCreatedApiKey] = useState<{ key_value: string; name: string } | null>(null);
  const [showApiKey, setShowApiKey] = useState(false);
  const [copied, setCopied] = useState(false);
  const [errors, setErrors] = useState<string[]>([]);

  const { showNotification } = useNotifications();

  // Load available scopes when modal opens
  useEffect(() => {
    if (isOpen) {
      loadAvailableScopes();
      setCreatedApiKey(null);
      setFormData(apiKeysApi.getDefaultFormData());
      setErrors([]);
    }
  }, [isOpen]);

  const loadAvailableScopes = async () => {
    try {
      const response = await apiKeysApi.getAvailableScopes();
      if (response.success && response.data) {
        const scopes = response.data.scopes.map(scope => ({
          id: scope,
          name: apiKeysApi.formatScope(scope),
          description: response.data.scope_descriptions[scope] || '',
          category: apiKeysApi.getScopeCategory(scope)
        }));
        setAvailableScopes(scopes);
      }
    } catch (error) {
      console.error('Failed to load scopes:', error);
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    
    // Validate form data
    const validationErrors = apiKeysApi.validateApiKeyData(formData);
    if (validationErrors.length > 0) {
      setErrors(validationErrors);
      return;
    }

    setLoading(true);
    setErrors([]);

    try {
      const response = await apiKeysApi.createApiKey(formData);
      
      if (response.success && response.data) {
        setCreatedApiKey({
          key_value: response.data.key_value || '',
          name: response.data.name
        });
        showNotification('API key created successfully', 'success');
      } else {
        setErrors([response.error || 'Failed to create API key']);
        showNotification('Failed to create API key', 'error');
      }
    } catch (error) {
      setErrors(['An unexpected error occurred']);
      showNotification('Failed to create API key', 'error');
    } finally {
      setLoading(false);
    }
  };

  const handleCopyKey = async () => {
    if (createdApiKey?.key_value) {
      const success = await apiKeysApi.copyToClipboard(createdApiKey.key_value);
      if (success) {
        setCopied(true);
        showNotification('API key copied to clipboard', 'success');
        setTimeout(() => setCopied(false), 2000);
      } else {
        showNotification('Failed to copy API key', 'error');
      }
    }
  };

  const handleClose = () => {
    if (createdApiKey) {
      onSuccess(); // Refresh the API keys list
    }
    onClose();
    setCreatedApiKey(null);
    setFormData(apiKeysApi.getDefaultFormData());
    setErrors([]);
    setCopied(false);
    setShowApiKey(false);
  };

  const handleScopeChange = (scopeId: string, checked: boolean) => {
    setFormData(prev => ({
      ...prev,
      scopes: checked 
        ? [...prev.scopes, scopeId]
        : prev.scopes.filter(id => id !== scopeId)
    }));
  };

  if (!isOpen) return null;

  // Show success screen if API key was created
  if (createdApiKey) {
    return (
      <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4 z-50">
        <div className="bg-theme-surface rounded-lg shadow-xl max-w-md w-full">
          <div className="flex items-center justify-between p-6 border-b border-theme">
            <h2 className="text-xl font-semibold text-theme-primary">API Key Created</h2>
            <button
              onClick={handleClose}
              className="text-theme-secondary hover:text-theme-primary"
            >
              <X className="w-5 h-5" />
            </button>
          </div>

          <div className="p-6">
            <div className="bg-theme-success bg-opacity-10 border border-theme-success border-opacity-30 rounded-lg p-4 mb-6">
              <div className="flex items-start space-x-3">
                <CheckCircle className="w-5 h-5 text-theme-success mt-0.5" />
                <div>
                  <h3 className="font-medium text-theme-success">API Key Created Successfully</h3>
                  <p className="text-sm text-theme-success opacity-80 mt-1">
                    Your API key "{createdApiKey.name}" has been generated.
                  </p>
                </div>
              </div>
            </div>

            <div className="bg-theme-warning bg-opacity-10 border border-theme-warning border-opacity-30 rounded-lg p-4 mb-6">
              <div className="flex items-start space-x-3">
                <AlertTriangle className="w-5 h-5 text-theme-warning mt-0.5" />
                <div>
                  <h3 className="font-medium text-theme-warning">Important Security Notice</h3>
                  <p className="text-sm text-theme-warning opacity-80 mt-1">
                    This is the only time you'll see the full API key. Copy it now and store it securely.
                  </p>
                </div>
              </div>
            </div>

            <div className="space-y-4">
              <label className="block text-sm font-medium text-theme-primary">
                Your API Key
              </label>
              <div className="relative">
                <input
                  type={showApiKey ? 'text' : 'password'}
                  value={createdApiKey.key_value}
                  readOnly
                  className="w-full px-4 py-2 bg-theme-background border border-theme rounded-lg text-theme-primary font-mono text-sm pr-20"
                />
                <div className="absolute inset-y-0 right-0 flex items-center space-x-1 pr-2">
                  <button
                    type="button"
                    onClick={() => setShowApiKey(!showApiKey)}
                    className="p-1 text-theme-secondary hover:text-theme-primary"
                    title={showApiKey ? 'Hide API key' : 'Show API key'}
                  >
                    {showApiKey ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                  </button>
                  <button
                    type="button"
                    onClick={handleCopyKey}
                    className={`p-1 ${copied ? 'text-theme-success' : 'text-theme-secondary hover:text-theme-primary'}`}
                    title="Copy to clipboard"
                  >
                    {copied ? <CheckCircle className="w-4 h-4" /> : <Copy className="w-4 h-4" />}
                  </button>
                </div>
              </div>
            </div>
          </div>

          <div className="flex justify-end p-6 border-t border-theme">
            <button
              onClick={handleClose}
              className="btn-theme btn-theme-primary"
            >
              Done
            </button>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4 z-50">
      <div className="bg-theme-surface rounded-lg shadow-xl max-w-2xl w-full max-h-[90vh] overflow-y-auto">
        <div className="flex items-center justify-between p-6 border-b border-theme">
          <h2 className="text-xl font-semibold text-theme-primary">Generate New API Key</h2>
          <button
            onClick={handleClose}
            className="text-theme-secondary hover:text-theme-primary"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="p-6 space-y-6">
          {errors.length > 0 && (
            <div className="bg-theme-error bg-opacity-10 border border-theme-error border-opacity-30 rounded-lg p-4">
              <div className="flex items-start space-x-3">
                <AlertTriangle className="w-5 h-5 text-theme-error mt-0.5" />
                <div>
                  <h3 className="font-medium text-theme-error">Please correct the following errors:</h3>
                  <ul className="text-sm text-theme-error opacity-80 mt-1 list-disc list-inside">
                    {errors.map((error, index) => (
                      <li key={index}>{error}</li>
                    ))}
                  </ul>
                </div>
              </div>
            </div>
          )}

          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Name <span className="text-theme-error">*</span>
              </label>
              <input
                type="text"
                required
                value={formData.name}
                onChange={(e) => setFormData(prev => ({ ...prev, name: e.target.value }))}
                className="w-full px-4 py-2 bg-theme-background border border-theme rounded-lg text-theme-primary placeholder-theme-tertiary focus:border-theme-interactive-primary focus:ring-2 focus:ring-theme-interactive-primary focus:ring-opacity-20 outline-none"
                placeholder="e.g., Production API, Mobile App"
              />
            </div>

            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Expires At
              </label>
              <input
                type="datetime-local"
                value={formData.expires_at}
                onChange={(e) => setFormData(prev => ({ ...prev, expires_at: e.target.value }))}
                className="w-full px-4 py-2 bg-theme-background border border-theme rounded-lg text-theme-primary focus:border-theme-interactive-primary focus:ring-2 focus:ring-theme-interactive-primary focus:ring-opacity-20 outline-none"
              />
            </div>
          </div>

          <div>
            <label className="block text-sm font-medium text-theme-primary mb-2">
              Description
            </label>
            <textarea
              value={formData.description}
              onChange={(e) => setFormData(prev => ({ ...prev, description: e.target.value }))}
              rows={3}
              className="w-full px-4 py-2 bg-theme-background border border-theme rounded-lg text-theme-primary placeholder-theme-tertiary focus:border-theme-interactive-primary focus:ring-2 focus:ring-theme-interactive-primary focus:ring-opacity-20 outline-none"
              placeholder="Optional description for this API key"
            />
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Rate Limit (per hour)
              </label>
              <input
                type="number"
                min="1"
                max="10000"
                value={formData.rate_limit_per_hour}
                onChange={(e) => setFormData(prev => ({ ...prev, rate_limit_per_hour: parseInt(e.target.value) || undefined }))}
                className="w-full px-4 py-2 bg-theme-background border border-theme rounded-lg text-theme-primary focus:border-theme-interactive-primary focus:ring-2 focus:ring-theme-interactive-primary focus:ring-opacity-20 outline-none"
                placeholder="1000"
              />
            </div>

            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Rate Limit (per day)
              </label>
              <input
                type="number"
                min="1"
                max="1000000"
                value={formData.rate_limit_per_day}
                onChange={(e) => setFormData(prev => ({ ...prev, rate_limit_per_day: parseInt(e.target.value) || undefined }))}
                className="w-full px-4 py-2 bg-theme-background border border-theme rounded-lg text-theme-primary focus:border-theme-interactive-primary focus:ring-2 focus:ring-theme-interactive-primary focus:ring-opacity-20 outline-none"
                placeholder="10000"
              />
            </div>
          </div>

          <div>
            <label className="block text-sm font-medium text-theme-primary mb-2">
              Allowed IP Addresses (optional)
            </label>
            <input
              type="text"
              value={formData.allowed_ips?.join(', ')}
              onChange={(e) => setFormData(prev => ({ 
                ...prev, 
                allowed_ips: e.target.value.split(',').map(ip => ip.trim()).filter(Boolean)
              }))}
              className="w-full px-4 py-2 bg-theme-background border border-theme rounded-lg text-theme-primary placeholder-theme-tertiary focus:border-theme-interactive-primary focus:ring-2 focus:ring-theme-interactive-primary focus:ring-opacity-20 outline-none"
              placeholder="192.168.1.1, 10.0.0.0/8"
            />
            <p className="text-sm text-theme-tertiary mt-1">
              Leave empty to allow all IP addresses. Separate multiple IPs with commas.
            </p>
          </div>

          <div>
            <label className="block text-sm font-medium text-theme-primary mb-3">
              Permissions <span className="text-theme-error">*</span>
            </label>
            <div className="space-y-3 max-h-60 overflow-y-auto border border-theme rounded-lg p-4 bg-theme-background">
              {availableScopes.map((scope) => (
                <div key={scope.id} className="flex items-start space-x-3">
                  <input
                    type="checkbox"
                    id={`scope-${scope.id}`}
                    checked={formData.scopes.includes(scope.id)}
                    onChange={(e) => handleScopeChange(scope.id, e.target.checked)}
                    className="mt-1 h-4 w-4 text-theme-interactive-primary focus:ring-theme-interactive-primary border-theme-tertiary rounded"
                  />
                  <div className="flex-1">
                    <label
                      htmlFor={`scope-${scope.id}`}
                      className="block text-sm font-medium text-theme-primary cursor-pointer"
                    >
                      {scope.name}
                      <span className={`inline-block ml-2 px-2 py-1 text-xs rounded ${apiKeysApi.getScopeCategoryColor(scope.id)}`}>
                        {scope.category}
                      </span>
                    </label>
                    <p className="text-sm text-theme-secondary">{scope.description}</p>
                  </div>
                </div>
              ))}
            </div>
            <p className="text-sm text-theme-tertiary mt-2">
              Select the permissions this API key should have. Choose only what's necessary for security.
            </p>
          </div>
        </form>

        <div className="flex justify-end space-x-3 p-6 border-t border-theme">
          <button
            type="button"
            onClick={handleClose}
            className="btn-theme btn-theme-secondary"
            disabled={loading}
          >
            Cancel
          </button>
          <button
            type="submit"
            onClick={handleSubmit}
            className="btn-theme btn-theme-primary"
            disabled={loading}
          >
            {loading ? 'Creating...' : 'Generate API Key'}
          </button>
        </div>
      </div>
    </div>
  );
};