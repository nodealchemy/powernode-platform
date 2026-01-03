import React, { useState, useEffect } from 'react';
import { X, Globe, AlertCircle, Server } from 'lucide-react';
import { gitProvidersApi } from '../services/gitProvidersApi';
import { GitProviderDetail, CreateProviderData, UpdateProviderData } from '../types';

interface GitProviderModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSuccess: () => void;
  provider?: GitProviderDetail | null; // If provided, we're editing
}

const PROVIDER_TYPES = [
  { value: 'github', label: 'GitHub', description: 'GitHub.com or GitHub Enterprise' },
  { value: 'gitlab', label: 'GitLab', description: 'GitLab.com or self-hosted GitLab' },
  { value: 'gitea', label: 'Gitea', description: 'Self-hosted Gitea instance' },
] as const;

export const GitProviderModal: React.FC<GitProviderModalProps> = ({
  isOpen,
  onClose,
  onSuccess,
  provider,
}) => {
  const isEditing = !!provider;
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [formData, setFormData] = useState<{
    name: string;
    provider_type: 'github' | 'gitlab' | 'gitea';
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

  // Populate form when editing
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
      // Reset form for new provider - default to GitHub (first option)
      setFormData({
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
    }
    setError(null);
  }, [provider, isOpen]);

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

  const handleTypeChange = (type: 'github' | 'gitlab' | 'gitea') => {
    setFormData((prev) => ({
      ...prev,
      provider_type: type,
      // Pre-fill default URLs for known providers
      api_base_url:
        type === 'github'
          ? 'https://api.github.com'
          : type === 'gitlab'
            ? 'https://gitlab.com/api/v4'
            : prev.api_base_url,
      web_base_url:
        type === 'github'
          ? 'https://github.com'
          : type === 'gitlab'
            ? 'https://gitlab.com'
            : prev.web_base_url,
    }));
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      {/* Backdrop */}
      <div className="absolute inset-0 bg-black/50" onClick={onClose} />

      {/* Modal */}
      <div className="relative bg-theme-surface rounded-lg shadow-xl w-full max-w-lg mx-4 border border-theme max-h-[90vh] overflow-y-auto">
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
              <div className="grid grid-cols-3 gap-2">
                {PROVIDER_TYPES.map((type) => (
                  <button
                    key={type.value}
                    type="button"
                    onClick={() => handleTypeChange(type.value)}
                    className={`p-3 rounded-lg border text-center transition-colors ${
                      formData.provider_type === type.value
                        ? 'border-theme-primary bg-theme-primary/10 text-theme-primary'
                        : 'border-theme hover:border-theme-primary/50 text-theme-secondary'
                    }`}
                  >
                    <div className="font-medium text-sm">{type.label}</div>
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
                'Use https://api.github.com for GitHub.com'}
              {formData.provider_type === 'gitlab' &&
                'Use https://gitlab.com/api/v4 for GitLab.com'}
              {formData.provider_type === 'gitea' &&
                'The API endpoint of your Gitea instance (required)'}
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
              Web interface URL for linking to repositories
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
