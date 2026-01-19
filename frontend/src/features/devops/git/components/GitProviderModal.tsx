import React, { useState, useEffect } from 'react';
import { X, Globe, AlertCircle, Server } from 'lucide-react';
import { gitProvidersApi } from '../services/gitProvidersApi';
import { GitProviderDetail, CreateProviderData, UpdateProviderData } from '../types';

interface GitProviderModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSuccess: () => void;
  provider?: GitProviderDetail | null; // If provided, we're editing
  initialProviderType?: 'github' | 'gitlab' | 'gitea' | 'bitbucket'; // Pre-select provider type for new
}

const PROVIDER_TYPES = [
  { value: 'github', label: 'GitHub', description: 'GitHub.com or GitHub Enterprise' },
  { value: 'gitlab', label: 'GitLab', description: 'GitLab.com or self-hosted GitLab' },
  { value: 'gitea', label: 'Gitea', description: 'Self-hosted Gitea instance' },
  { value: 'bitbucket', label: 'Bitbucket', description: 'Bitbucket Cloud or Server' },
] as const;

export const GitProviderModal: React.FC<GitProviderModalProps> = ({
  isOpen,
  onClose,
  onSuccess,
  provider,
  initialProviderType,
}) => {
  const isEditing = !!provider;
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [formData, setFormData] = useState<{
    name: string;
    provider_type: 'github' | 'gitlab' | 'gitea' | 'bitbucket';
    description: string;
    api_base_url: string;
    web_base_url: string;
    is_active: boolean;
    supports_oauth: boolean;
    supports_pat: boolean;
    supports_webhooks: boolean;
    supports_ci_cd: boolean;
  }>({
    name: '',
    provider_type: 'github',
    description: '',
    api_base_url: 'https://api.github.com',
    web_base_url: 'https://github.com',
    is_active: true,
    supports_oauth: true,
    supports_pat: true,
    supports_webhooks: true,
    supports_ci_cd: true,
  });

  // Get default URLs for a provider type
  const getDefaultUrls = (type: 'github' | 'gitlab' | 'gitea' | 'bitbucket') => {
    switch (type) {
      case 'github':
        return { api: 'https://api.github.com', web: 'https://github.com' };
      case 'gitlab':
        return { api: 'https://gitlab.com/api/v4', web: 'https://gitlab.com' };
      case 'gitea':
        return { api: 'https://gitea.com/api/v1', web: 'https://gitea.com' };
      case 'bitbucket':
        return { api: 'https://api.bitbucket.org/2.0', web: 'https://bitbucket.org' };
      default:
        return { api: '', web: '' };
    }
  };

  // Populate form when editing or set initial provider type
  useEffect(() => {
    if (provider) {
      setFormData({
        name: provider.name,
        provider_type: provider.provider_type,
        description: provider.description || '',
        api_base_url: provider.api_base_url || '',
        web_base_url: provider.web_base_url || '',
        is_active: provider.is_active,
        supports_oauth: provider.supports_oauth,
        supports_pat: provider.supports_pat,
        supports_webhooks: provider.supports_webhooks,
        supports_ci_cd: provider.supports_ci_cd,
      });
    } else {
      // Reset form for new provider - use initialProviderType or default to GitHub
      const providerType = initialProviderType || 'github';
      const urls = getDefaultUrls(providerType);
      setFormData({
        name: '',
        provider_type: providerType,
        description: '',
        api_base_url: urls.api,
        web_base_url: urls.web,
        is_active: true,
        supports_oauth: true,
        supports_pat: true,
        supports_webhooks: true,
        supports_ci_cd: true,
      });
    }
    setError(null);
  }, [provider, isOpen, initialProviderType]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    if (!formData.name.trim()) {
      setError('Provider name is required');
      return;
    }

    // Validate URLs for self-hosted providers
    if (formData.provider_type === 'gitea' && !formData.api_base_url) {
      setError('API base URL is required for Gitea');
      return;
    }

    try {
      setLoading(true);

      if (isEditing && provider) {
        const updateData: UpdateProviderData = {
          name: formData.name,
          description: formData.description || undefined,
          api_base_url: formData.api_base_url || undefined,
          web_base_url: formData.web_base_url || undefined,
          is_active: formData.is_active,
        };
        await gitProvidersApi.updateProvider(provider.id, updateData);
      } else {
        const createData: CreateProviderData = {
          name: formData.name,
          provider_type: formData.provider_type,
          description: formData.description || undefined,
          api_base_url: formData.api_base_url || undefined,
          web_base_url: formData.web_base_url || undefined,
          is_active: formData.is_active,
          supports_oauth: formData.supports_oauth,
          supports_pat: formData.supports_pat,
          supports_webhooks: formData.supports_webhooks,
          supports_ci_cd: formData.supports_ci_cd,
        };
        await gitProvidersApi.createProvider(createData);
      }

      onSuccess();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save provider');
    } finally {
      setLoading(false);
    }
  };

  const handleTypeChange = (type: 'github' | 'gitlab' | 'gitea' | 'bitbucket') => {
    const urls = getDefaultUrls(type);
    setFormData((prev) => ({
      ...prev,
      provider_type: type,
      // Pre-fill default URLs for known providers (clear for self-hosted like Gitea)
      api_base_url: urls.api,
      web_base_url: urls.web,
    }));
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      {/* Backdrop */}
      <div className="fixed inset-0 bg-black/50 z-0" onClick={onClose} />

      {/* Modal */}
      <div className="relative z-10 bg-theme-surface rounded-lg shadow-xl w-full max-w-lg mx-4 border border-theme max-h-[90vh] overflow-y-auto">
        {/* Header */}
        <div className="flex items-center justify-between p-4 border-b border-theme sticky top-0 bg-theme-surface">
          <div className="flex items-center gap-2">
            <Server className="w-5 h-5 text-theme-primary" />
            <h2 className="text-lg font-semibold text-theme-primary">
              {isEditing ? 'Edit Git Provider' : 'Add Git Provider'}
            </h2>
          </div>
          <button
            onClick={onClose}
            className="p-1 rounded-lg hover:bg-theme-hover text-theme-secondary"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Form */}
        <form onSubmit={handleSubmit} className="p-4 space-y-4">
          {error && (
            <div className="flex items-center gap-2 p-3 bg-theme-error/10 border border-theme-error/20 rounded-lg text-theme-error">
              <AlertCircle className="w-4 h-4 flex-shrink-0" />
              <p className="text-sm">{error}</p>
            </div>
          )}

          {/* Provider Type (only for new) */}
          {!isEditing && (
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Provider Type
              </label>
              <div className="grid grid-cols-4 gap-2">
                {PROVIDER_TYPES.map((type) => (
                  <button
                    key={type.value}
                    type="button"
                    onClick={() => handleTypeChange(type.value)}
                    className={`px-2 py-2 rounded-lg border text-center transition-colors ${
                      formData.provider_type === type.value
                        ? 'border-theme-primary bg-theme-primary/10 text-theme-primary'
                        : 'border-theme hover:border-theme-primary/50 text-theme-secondary'
                    }`}
                  >
                    <div className="font-medium text-xs">{type.label}</div>
                  </button>
                ))}
              </div>
            </div>
          )}

          {/* Name */}
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">
              Provider Name
            </label>
            <input
              type="text"
              value={formData.name}
              onChange={(e) =>
                setFormData({ ...formData, name: e.target.value })
              }
              className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
              placeholder="My Gitea Server"
              required
            />
            <p className="text-xs text-theme-secondary mt-1">
              A friendly name to identify this provider
            </p>
          </div>

          {/* Description */}
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">
              Description (Optional)
            </label>
            <textarea
              value={formData.description}
              onChange={(e) =>
                setFormData({ ...formData, description: e.target.value })
              }
              className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary resize-none"
              rows={2}
              placeholder="Self-hosted Git server for internal projects"
            />
          </div>

          {/* API Base URL */}
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">
              <Globe className="w-4 h-4 inline mr-1" />
              API Base URL
            </label>
            <input
              type="url"
              value={formData.api_base_url}
              onChange={(e) =>
                setFormData({ ...formData, api_base_url: e.target.value })
              }
              className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
              placeholder="https://git.example.com/api/v1"
              required={formData.provider_type === 'gitea'}
            />
            <p className="text-xs text-theme-secondary mt-1">
              {formData.provider_type === 'github' &&
                'Use https://api.github.com for GitHub.com, or your GitHub Enterprise URL'}
              {formData.provider_type === 'gitlab' &&
                'Use https://gitlab.com/api/v4 for GitLab.com, or your self-hosted GitLab URL'}
              {formData.provider_type === 'gitea' &&
                'Use https://gitea.com/api/v1 for Gitea.com, or your self-hosted Gitea URL'}
              {formData.provider_type === 'bitbucket' &&
                'Use https://api.bitbucket.org/2.0 for Bitbucket Cloud, or your Bitbucket Server URL'}
            </p>
          </div>

          {/* Web Base URL */}
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">
              Web Base URL (Optional)
            </label>
            <input
              type="url"
              value={formData.web_base_url}
              onChange={(e) =>
                setFormData({ ...formData, web_base_url: e.target.value })
              }
              className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
              placeholder="https://git.example.com"
            />
            <p className="text-xs text-theme-secondary mt-1">
              {formData.provider_type === 'github' &&
                'Use https://github.com for GitHub.com, or your GitHub Enterprise URL'}
              {formData.provider_type === 'gitlab' &&
                'Use https://gitlab.com for GitLab.com, or your self-hosted GitLab URL'}
              {formData.provider_type === 'gitea' &&
                'Use https://gitea.com for Gitea.com, or your self-hosted Gitea URL'}
              {formData.provider_type === 'bitbucket' &&
                'Use https://bitbucket.org for Bitbucket Cloud, or your Bitbucket Server URL'}
            </p>
          </div>

          {/* Features (only for new) */}
          {!isEditing && (
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Supported Features
              </label>
              <div className="grid grid-cols-2 gap-2">
                <label className="flex items-center gap-2 p-2 rounded-lg border border-theme hover:bg-theme-hover cursor-pointer">
                  <input
                    type="checkbox"
                    checked={formData.supports_pat}
                    onChange={(e) =>
                      setFormData({ ...formData, supports_pat: e.target.checked })
                    }
                    className="w-4 h-4 rounded border-theme"
                  />
                  <span className="text-sm text-theme-primary">Personal Access Tokens</span>
                </label>
                <label className="flex items-center gap-2 p-2 rounded-lg border border-theme hover:bg-theme-hover cursor-pointer">
                  <input
                    type="checkbox"
                    checked={formData.supports_oauth}
                    onChange={(e) =>
                      setFormData({ ...formData, supports_oauth: e.target.checked })
                    }
                    className="w-4 h-4 rounded border-theme"
                  />
                  <span className="text-sm text-theme-primary">OAuth</span>
                </label>
                <label className="flex items-center gap-2 p-2 rounded-lg border border-theme hover:bg-theme-hover cursor-pointer">
                  <input
                    type="checkbox"
                    checked={formData.supports_webhooks}
                    onChange={(e) =>
                      setFormData({ ...formData, supports_webhooks: e.target.checked })
                    }
                    className="w-4 h-4 rounded border-theme"
                  />
                  <span className="text-sm text-theme-primary">Webhooks</span>
                </label>
                <label className="flex items-center gap-2 p-2 rounded-lg border border-theme hover:bg-theme-hover cursor-pointer">
                  <input
                    type="checkbox"
                    checked={formData.supports_ci_cd}
                    onChange={(e) =>
                      setFormData({ ...formData, supports_ci_cd: e.target.checked })
                    }
                    className="w-4 h-4 rounded border-theme"
                  />
                  <span className="text-sm text-theme-primary">CI/CD</span>
                </label>
              </div>
            </div>
          )}

          {/* Active Status */}
          <div className="flex items-center gap-2">
            <input
              type="checkbox"
              id="is_active"
              checked={formData.is_active}
              onChange={(e) =>
                setFormData({ ...formData, is_active: e.target.checked })
              }
              className="w-4 h-4 rounded border-theme text-theme-primary focus:ring-theme-primary"
            />
            <label
              htmlFor="is_active"
              className="text-sm text-theme-primary cursor-pointer"
            >
              Provider is active and available for use
            </label>
          </div>

          {/* Actions */}
          <div className="flex gap-3 pt-4">
            <button
              type="button"
              onClick={onClose}
              className="flex-1 btn-theme btn-theme-outline"
              disabled={loading}
            >
              Cancel
            </button>
            <button
              type="submit"
              className="flex-1 btn-theme btn-theme-primary"
              disabled={loading}
            >
              {loading
                ? 'Saving...'
                : isEditing
                  ? 'Save Changes'
                  : 'Add Provider'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};

export default GitProviderModal;
