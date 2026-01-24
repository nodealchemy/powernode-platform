import React, { useState } from 'react';
import { Server, CheckCircle, RefreshCw, Trash2, Edit, Plus, Download } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import type { DevopsProvider, DevopsProviderType, DevopsProviderFormData } from '@/types/devops-pipelines';

interface ProviderSettingsProps {
  providers: DevopsProvider[];
  loading: boolean;
  onAdd: (data: DevopsProviderFormData) => void;
  onEdit: (id: string, data: Partial<DevopsProviderFormData>) => void;
  onDelete: (id: string) => void;
  onTestConnection: (id: string) => void;
  onImportRepositories?: (id: string) => void;
}

const getProviderIcon = (type: DevopsProviderType): string => {
  const icons: Record<DevopsProviderType, string> = {
    gitea: '🐙',
    github: '🐙',
    gitlab: '🦊',
    jenkins: '🔧',
  };
  return icons[type] || '🔧';
};

const ProviderCard: React.FC<{
  provider: DevopsProvider;
  onEdit: () => void;
  onDelete: () => void;
  onTestConnection: () => void;
  onImportRepositories?: () => void;
}> = ({ provider, onEdit, onDelete, onTestConnection, onImportRepositories }) => {
  const [testing, setTesting] = useState(false);

  const handleTest = async () => {
    setTesting(true);
    await onTestConnection();
    setTesting(false);
  };

  return (
    <div className="bg-theme-surface rounded-lg border border-theme p-4">
      <div className="flex items-start justify-between">
        <div className="flex items-center gap-3">
          <div className="text-2xl">{getProviderIcon(provider.provider_type)}</div>
          <div>
            <h3 className="font-medium text-theme-primary">{provider.name}</h3>
            <p className="text-sm text-theme-tertiary">{provider.base_url}</p>
          </div>
        </div>
        <span
          className={`inline-flex items-center px-2 py-1 rounded-full text-xs font-medium ${
            provider.is_active
              ? 'bg-theme-success/10 text-theme-success'
              : 'bg-theme-secondary/10 text-theme-secondary'
          }`}
        >
          {provider.is_active ? 'Active' : 'Inactive'}
        </span>
      </div>

      <div className="mt-4 flex items-center gap-4 text-xs text-theme-tertiary">
        <span className="capitalize">{provider.provider_type}</span>
        <span>{provider.repository_count} repositories</span>
        {provider.last_sync_at && (
          <span>Last synced: {new Date(provider.last_sync_at).toLocaleDateString()}</span>
        )}
      </div>

      <div className="mt-4 pt-4 border-t border-theme flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Button
            onClick={handleTest}
            variant="secondary"
            size="sm"
            disabled={testing}
          >
            {testing ? (
              <RefreshCw className="w-4 h-4 mr-1 animate-spin" />
            ) : (
              <CheckCircle className="w-4 h-4 mr-1" />
            )}
            Test
          </Button>
          {onImportRepositories && (
            <Button
              onClick={onImportRepositories}
              variant="secondary"
              size="sm"
            >
              <Download className="w-4 h-4 mr-1" />
              Import
            </Button>
          )}
        </div>

        <div className="flex items-center gap-2">
          <Button onClick={onEdit} variant="ghost" size="sm">
            <Edit className="w-4 h-4" />
          </Button>
          <Button onClick={onDelete} variant="ghost" size="sm">
            <Trash2 className="w-4 h-4 text-theme-error" />
          </Button>
        </div>
      </div>
    </div>
  );
};

interface ProviderFormProps {
  provider?: DevopsProvider;
  onSubmit: (data: DevopsProviderFormData) => void;
  onCancel: () => void;
}

const ProviderForm: React.FC<ProviderFormProps> = ({ provider, onSubmit, onCancel }) => {
  const [formData, setFormData] = useState<DevopsProviderFormData>({
    name: provider?.name || '',
    provider_type: provider?.provider_type || 'gitea',
    base_url: provider?.base_url || '',
    api_token: '',
    webhook_secret: '',
    is_active: provider?.is_active ?? true,
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    onSubmit(formData);
  };

  return (
    <form onSubmit={handleSubmit} className="bg-theme-surface rounded-lg border border-theme p-4">
      <h3 className="font-medium text-theme-primary mb-4">
        {provider ? 'Edit Provider' : 'Add Provider'}
      </h3>

      <div className="space-y-4">
        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-1">
            Name
          </label>
          <input
            type="text"
            value={formData.name}
            onChange={(e) => setFormData({ ...formData, name: e.target.value })}
            className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
            required
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-1">
            Provider Type
          </label>
          <select
            value={formData.provider_type}
            onChange={(e) => setFormData({ ...formData, provider_type: e.target.value as DevopsProviderType })}
            className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
          >
            <option value="gitea">Gitea</option>
            <option value="github">GitHub</option>
            <option value="gitlab">GitLab</option>
            <option value="jenkins">Jenkins</option>
          </select>
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-1">
            Base URL
          </label>
          <input
            type="url"
            value={formData.base_url}
            onChange={(e) => setFormData({ ...formData, base_url: e.target.value })}
            placeholder="https://git.example.com"
            className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
            required
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-1">
            API Token {provider && <span className="text-theme-tertiary">(leave empty to keep existing)</span>}
          </label>
          <input
            type="password"
            value={formData.api_token}
            onChange={(e) => setFormData({ ...formData, api_token: e.target.value })}
            className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
            required={!provider}
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-1">
            Webhook Secret (optional)
          </label>
          <input
            type="password"
            value={formData.webhook_secret}
            onChange={(e) => setFormData({ ...formData, webhook_secret: e.target.value })}
            className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
          />
        </div>

        <div className="flex items-center gap-2">
          <input
            type="checkbox"
            id="is_active"
            checked={formData.is_active}
            onChange={(e) => setFormData({ ...formData, is_active: e.target.checked })}
            className="rounded border-theme text-theme-primary focus:ring-theme-primary"
          />
          <label htmlFor="is_active" className="text-sm text-theme-secondary">
            Active
          </label>
        </div>
      </div>

      <div className="mt-4 flex items-center justify-end gap-2">
        <Button onClick={onCancel} variant="secondary" type="button">
          Cancel
        </Button>
        <Button type="submit" variant="primary">
          {provider ? 'Update' : 'Create'}
        </Button>
      </div>
    </form>
  );
};

export const ProviderSettings: React.FC<ProviderSettingsProps> = ({
  providers,
  loading,
  onAdd,
  onEdit,
  onDelete,
  onTestConnection,
  onImportRepositories,
}) => {
  const [showForm, setShowForm] = useState(false);
  const [editingProvider, setEditingProvider] = useState<DevopsProvider | null>(null);

  const handleSubmit = (data: DevopsProviderFormData) => {
    if (editingProvider) {
      onEdit(editingProvider.id, data);
    } else {
      onAdd(data);
    }
    setShowForm(false);
    setEditingProvider(null);
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <LoadingSpinner size="lg" />
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {!showForm && !editingProvider && (
        <div className="flex justify-end">
          <Button onClick={() => setShowForm(true)} variant="primary">
            <Plus className="w-4 h-4 mr-1" />
            Add Provider
          </Button>
        </div>
      )}

      {(showForm || editingProvider) && (
        <ProviderForm
          provider={editingProvider || undefined}
          onSubmit={handleSubmit}
          onCancel={() => {
            setShowForm(false);
            setEditingProvider(null);
          }}
        />
      )}

      {providers.length === 0 && !showForm ? (
        <div className="bg-theme-surface rounded-lg p-8 border border-theme text-center">
          <Server className="w-12 h-12 text-theme-secondary mx-auto mb-4" />
          <h3 className="text-lg font-medium text-theme-primary mb-2">
            No Git Providers Configured
          </h3>
          <p className="text-theme-secondary mb-4">
            Add a Git provider to connect repositories and enable DevOps pipelines.
          </p>
          <Button onClick={() => setShowForm(true)} variant="primary">
            <Plus className="w-4 h-4 mr-1" />
            Add Provider
          </Button>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {providers.map((provider) => (
            <ProviderCard
              key={provider.id}
              provider={provider}
              onEdit={() => setEditingProvider(provider)}
              onDelete={() => onDelete(provider.id)}
              onTestConnection={() => onTestConnection(provider.id)}
              onImportRepositories={onImportRepositories ? () => onImportRepositories(provider.id) : undefined}
            />
          ))}
        </div>
      )}
    </div>
  );
};

export default ProviderSettings;
