import React, { useState, useEffect, useCallback } from 'react';
import { X, Save, Key, Plus, TestTube, Trash2, Star } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';
import { Modal } from '@/shared/components/ui/Modal';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { dataSourcesApi } from '@/shared/services/ai/DataSourcesApiService';
import {
  SUGGESTED_SOURCE_TYPE_OPTIONS,
  DATA_SOURCE_PROTOCOL_OPTIONS,
  SUGGESTED_CATEGORIES,
} from './sourceTypeLabels';
import type { AiDataSource, AiDataSourceCredential, DataSourceProtocol } from '@/shared/types/ai';

interface EditDataSourceModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSuccess: () => void;
  dataSourceId: string;
}

// Narrow the free-form backend protocol string to a known option, defaulting to
// 'rest' so the selector always has a valid value even for legacy/unknown rows.
function normalizeProtocol(protocol: string | null | undefined): DataSourceProtocol {
  const match = DATA_SOURCE_PROTOCOL_OPTIONS.find((opt) => opt.value === protocol);
  return match ? match.value : 'rest';
}

export const EditDataSourceModal: React.FC<EditDataSourceModalProps> = ({
  isOpen,
  onClose,
  onSuccess,
  dataSourceId
}) => {
  const [submitting, setSubmitting] = useState(false);
  const [initialLoading, setInitialLoading] = useState(true);
  const [credentials, setCredentials] = useState<AiDataSourceCredential[]>([]);
  const [credentialLoading, setCredentialLoading] = useState(false);
  const [formData, setFormData] = useState({
    name: '',
    slug: '',
    source_type: 'custom',
    category: '',
    protocol: 'rest' as DataSourceProtocol,
    description: '',
    api_base_url: '',
    requires_auth: true,
    is_active: true,
    priority_order: 1,
    documentation_url: '',
    respect_robots: false,
    crawl_delay_seconds: '',
    rate_limit_minute: '',
    rate_limit_hour: '',
    rate_limit_day: '',
  });
  const [newCredential, setNewCredential] = useState({ name: '', api_key: '' });

  const { addNotification } = useNotifications();
  const { confirm, ConfirmationDialog } = useConfirmation();

  const loadDataSource = useCallback(async () => {
    if (!dataSourceId || !isOpen) return;
    try {
      setInitialLoading(true);
      const ds: AiDataSource = await dataSourcesApi.getDataSource(dataSourceId);
      setFormData({
        name: ds.name || '',
        slug: ds.slug || '',
        source_type: ds.source_type || 'custom',
        category: ds.category || '',
        protocol: normalizeProtocol(ds.protocol),
        description: ds.description || '',
        api_base_url: ds.api_base_url || '',
        requires_auth: ds.requires_auth ?? true,
        is_active: ds.is_active ?? true,
        priority_order: ds.priority_order ?? 1,
        documentation_url: ds.documentation_url || '',
        respect_robots: ds.respect_robots ?? false,
        crawl_delay_seconds: ds.crawl_delay_seconds != null ? String(ds.crawl_delay_seconds) : '',
        rate_limit_minute: ds.rate_limits?.requests_per_minute?.toString() || '',
        rate_limit_hour: ds.rate_limits?.requests_per_hour?.toString() || '',
        rate_limit_day: ds.rate_limits?.requests_per_day?.toString() || '',
      });
      setCredentials(ds.credentials || []);
    } catch (_error) {
      addNotification({ type: 'error', title: 'Error', message: 'Failed to load data source.' });
      onClose();
    } finally {
      setInitialLoading(false);
    }
  }, [dataSourceId, isOpen, addNotification, onClose]);

  useEffect(() => {
    if (isOpen && dataSourceId) { loadDataSource(); }
  }, [isOpen, dataSourceId, loadDataSource]);

  const handleInputChange = (field: string, value: string | boolean | number) => {
    setFormData(prev => ({ ...prev, [field]: value }));
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitting(true);
    try {
      const rateLimits: Record<string, number> = {};
      if (formData.rate_limit_minute) rateLimits.requests_per_minute = parseInt(formData.rate_limit_minute, 10);
      if (formData.rate_limit_hour) rateLimits.requests_per_hour = parseInt(formData.rate_limit_hour, 10);
      if (formData.rate_limit_day) rateLimits.requests_per_day = parseInt(formData.rate_limit_day, 10);

      await dataSourcesApi.updateDataSource(dataSourceId, {
        name: formData.name,
        source_type: formData.source_type.trim(),
        category: formData.category.trim() || null,
        protocol: formData.protocol,
        slug: formData.slug,
        description: formData.description,
        api_base_url: formData.api_base_url || undefined,
        requires_auth: formData.requires_auth,
        is_active: formData.is_active,
        priority_order: formData.priority_order,
        documentation_url: formData.documentation_url || undefined,
        respect_robots: formData.respect_robots,
        // null clears the per-host crawl delay override; a value sets it.
        crawl_delay_seconds: formData.crawl_delay_seconds
          ? parseInt(formData.crawl_delay_seconds, 10)
          : null,
        rate_limits: Object.keys(rateLimits).length > 0 ? rateLimits : undefined,
      });

      // Create new credential if form is filled
      if (newCredential.name && newCredential.api_key) {
        await dataSourcesApi.createCredential(dataSourceId, {
          name: newCredential.name,
          api_key: newCredential.api_key,
          is_active: true,
        });
        setNewCredential({ name: '', api_key: '' });
      }

      addNotification({
        type: 'success',
        title: 'Data Source Updated',
        message: `${formData.name} has been updated successfully`
      });
      onSuccess();
      onClose();
    } catch (_error) {
      addNotification({
        type: 'error',
        title: 'Update Failed',
        message: 'Failed to update data source. Please try again.'
      });
    } finally {
      setSubmitting(false);
    }
  };

  const handleDeleteCredential = (credentialId: string, credentialName: string) => {
    confirm({
      title: 'Delete Credential',
      message: `Are you sure you want to delete credential "${credentialName}"?`,
      confirmLabel: 'Delete',
      variant: 'danger',
      onConfirm: async () => {
        try {
          setCredentialLoading(true);
          await dataSourcesApi.deleteCredential(dataSourceId, credentialId);
          setCredentials(prev => prev.filter(c => c.id !== credentialId));
          addNotification({ type: 'success', title: 'Credential Deleted', message: `${credentialName} has been deleted.` });
        } catch (_error) {
          addNotification({ type: 'error', title: 'Delete Failed', message: 'Failed to delete credential.' });
        } finally {
          setCredentialLoading(false);
        }
      }
    });
  };

  const handleTestCredential = async (credentialId: string) => {
    try {
      setCredentialLoading(true);
      const result = await dataSourcesApi.testCredential(dataSourceId, credentialId);
      addNotification({
        type: result.success ? 'success' : 'error',
        title: 'Credential Test',
        message: result.success ? 'Credential test passed' : `Test failed: ${result.error || 'Unknown error'}`
      });
    } catch (_error) {
      addNotification({ type: 'error', title: 'Test Failed', message: 'Failed to test credential.' });
    } finally {
      setCredentialLoading(false);
    }
  };

  const handleMakeDefault = async (credentialId: string) => {
    try {
      setCredentialLoading(true);
      await dataSourcesApi.makeDefaultCredential(dataSourceId, credentialId);
      setCredentials(prev => prev.map(c => ({ ...c, is_default: c.id === credentialId })));
      addNotification({ type: 'success', title: 'Default Updated', message: 'Default credential updated.' });
    } catch (_error) {
      addNotification({ type: 'error', title: 'Update Failed', message: 'Failed to update default credential.' });
    } finally {
      setCredentialLoading(false);
    }
  };

  const handleClose = () => {
    setNewCredential({ name: '', api_key: '' });
    onClose();
  };

  if (initialLoading) {
    return (
      <Modal isOpen={isOpen} onClose={handleClose} size="lg">
        <div className="flex items-center justify-between p-6 border-b border-theme">
          <h2 className="text-xl font-semibold text-theme-primary">Loading Data Source...</h2>
          <Button variant="ghost" size="sm" onClick={handleClose} className="h-8 w-8 p-0">
            <X className="h-4 w-4" />
          </Button>
        </div>
        <LoadingSpinner className="p-6" />
      </Modal>
    );
  }

  return (
    <Modal isOpen={isOpen} onClose={handleClose} size="lg">
      <div className="flex items-center justify-between p-6 border-b border-theme">
        <h2 className="text-xl font-semibold text-theme-primary">Edit Data Source</h2>
        <Button variant="ghost" size="sm" onClick={handleClose} className="h-8 w-8 p-0">
          <X className="h-4 w-4" />
        </Button>
      </div>

      <form onSubmit={handleSubmit} className="p-6 space-y-6">
        {/* Basic Fields */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <label className="block text-sm font-medium text-theme-secondary mb-1">Name *</label>
            <Input value={formData.name} onChange={(e) => handleInputChange('name', e.target.value)} required />
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-secondary mb-1">Slug</label>
            <Input value={formData.slug} onChange={(e) => handleInputChange('slug', e.target.value)} />
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <label className="block text-sm font-medium text-theme-secondary mb-1">Source Type *</label>
            <Input
              value={formData.source_type}
              onChange={(e) => handleInputChange('source_type', e.target.value)}
              list="edit-source-type-suggestions"
              placeholder="e.g., open_meteo or crypto_coingecko"
              description="Free-form. Pick a suggestion or type any lowercase token."
              required
            />
            <datalist id="edit-source-type-suggestions">
              {SUGGESTED_SOURCE_TYPE_OPTIONS.map(({ value, label }) => (
                <option key={value} value={value}>{label}</option>
              ))}
            </datalist>
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-secondary mb-1">Category</label>
            <Input
              value={formData.category}
              onChange={(e) => handleInputChange('category', e.target.value)}
              list="edit-category-suggestions"
              placeholder="e.g., weather"
              description="Optional grouping label."
            />
            <datalist id="edit-category-suggestions">
              {SUGGESTED_CATEGORIES.map((category) => (
                <option key={category} value={category} />
              ))}
            </datalist>
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <label className="block text-sm font-medium text-theme-secondary mb-1">Protocol *</label>
            <Select value={formData.protocol} onChange={(value) => handleInputChange('protocol', value)}>
              {DATA_SOURCE_PROTOCOL_OPTIONS.map(({ value, label }) => (
                <option key={value} value={value}>{label}</option>
              ))}
            </Select>
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-secondary mb-1">Priority Order</label>
            <Input type="number" value={formData.priority_order} onChange={(e) => handleInputChange('priority_order', parseInt(e.target.value, 10) || 1)} />
          </div>
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-1">Description</label>
          <textarea
            value={formData.description}
            onChange={(e) => handleInputChange('description', e.target.value)}
            rows={3}
            className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary placeholder-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-info focus:border-transparent"
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-1">API Base URL</label>
          <Input value={formData.api_base_url} onChange={(e) => handleInputChange('api_base_url', e.target.value)} type="url" />
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-1">Documentation URL</label>
          <Input value={formData.documentation_url} onChange={(e) => handleInputChange('documentation_url', e.target.value)} type="url" />
        </div>

        <div className="flex items-center gap-6">
          <label className="flex items-center space-x-2">
            <input type="checkbox" checked={formData.requires_auth} onChange={(e) => handleInputChange('requires_auth', e.target.checked)} className="rounded border-theme-300 text-theme-info focus:ring-theme-info" />
            <span className="text-sm text-theme-secondary">Requires Authentication</span>
          </label>
          <label className="flex items-center space-x-2">
            <input type="checkbox" checked={formData.is_active} onChange={(e) => handleInputChange('is_active', e.target.checked)} className="rounded border-theme-300 text-theme-info focus:ring-theme-info" />
            <span className="text-sm text-theme-secondary">Active</span>
          </label>
        </div>

        {/* Crawl politeness — off by default. */}
        <div className="space-y-3 rounded-lg border border-dashed border-theme p-4">
          <label className="flex items-center space-x-2">
            <input
              type="checkbox"
              checked={formData.respect_robots}
              onChange={(e) => handleInputChange('respect_robots', e.target.checked)}
              className="rounded border-theme-300 text-theme-info focus:ring-theme-info"
            />
            <span className="text-sm text-theme-secondary">Respect robots.txt</span>
          </label>
          <p className="text-xs text-theme-tertiary">
            When enabled, the background monitor honors the host&apos;s robots.txt and paces
            requests per host. Off by default.
          </p>
          <div>
            <label className="block text-xs text-theme-tertiary mb-1">Crawl Delay (seconds)</label>
            <Input
              value={formData.crawl_delay_seconds}
              onChange={(e) => handleInputChange('crawl_delay_seconds', e.target.value)}
              type="number"
              min={0}
              placeholder="e.g., 5"
            />
            <p className="mt-1 text-xs text-theme-tertiary">
              Minimum seconds between requests to the same host. A robots.txt Crawl-delay may
              raise it. Leave blank for no per-host delay.
            </p>
          </div>
        </div>

        {/* Rate Limits */}
        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-2">Rate Limits</label>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div>
              <label className="block text-xs text-theme-tertiary mb-1">Per Minute</label>
              <Input value={formData.rate_limit_minute} onChange={(e) => handleInputChange('rate_limit_minute', e.target.value)} type="number" placeholder="e.g., 60" />
            </div>
            <div>
              <label className="block text-xs text-theme-tertiary mb-1">Per Hour</label>
              <Input value={formData.rate_limit_hour} onChange={(e) => handleInputChange('rate_limit_hour', e.target.value)} type="number" placeholder="e.g., 1000" />
            </div>
            <div>
              <label className="block text-xs text-theme-tertiary mb-1">Per Day</label>
              <Input value={formData.rate_limit_day} onChange={(e) => handleInputChange('rate_limit_day', e.target.value)} type="number" placeholder="e.g., 10000" />
            </div>
          </div>
        </div>

        {/* Credentials Management */}
        <div className="space-y-4">
          <div className="border-t border-theme pt-4">
            <h4 className="text-sm font-semibold text-theme-primary flex items-center gap-2">
              <Key className="h-4 w-4" />
              Credentials Management
            </h4>
          </div>

          {/* Existing Credentials */}
          {credentials.length > 0 && (
            <div className="space-y-2">
              <h5 className="text-sm font-medium text-theme-secondary">Existing Credentials ({credentials.length})</h5>
              <div className="space-y-2">
                {credentials.map((credential) => (
                  <div key={credential.id} className="flex items-center justify-between p-3 border border-theme rounded-lg">
                    <div className="flex items-center gap-3">
                      <div className={`h-3 w-3 rounded-full ${
                        credential.last_test_status === 'success' ? 'bg-theme-success' :
                        credential.last_test_status === 'failed' ? 'bg-theme-error' :
                        'bg-theme-background-secondary'
                      }`} />
                      <div>
                        <p className="text-sm font-medium text-theme-primary">
                          {credential.name}
                          {credential.is_default && (
                            <span className="ml-2 px-2 py-1 text-xs bg-theme-info/10 text-theme-info rounded">Default</span>
                          )}
                        </p>
                        <div className="flex items-center gap-4 text-xs text-theme-tertiary">
                          {credential.is_active ? (
                            <Badge variant="success" size="sm">Active</Badge>
                          ) : (
                            <Badge variant="secondary" size="sm">Inactive</Badge>
                          )}
                          {credential.last_used_at && (
                            <span>Last used: {new Date(credential.last_used_at).toLocaleDateString()}</span>
                          )}
                          {credential.consecutive_failures > 0 && (
                            <span className="text-theme-error">{credential.consecutive_failures} failures</span>
                          )}
                        </div>
                      </div>
                    </div>
                    <div className="flex items-center gap-1">
                      {!credential.is_default && (
                        <Button variant="ghost" size="sm" onClick={() => handleMakeDefault(credential.id)} disabled={credentialLoading} title="Make Default">
                          <Star className="h-3 w-3" />
                        </Button>
                      )}
                      <Button variant="ghost" size="sm" onClick={() => handleTestCredential(credential.id)} disabled={credentialLoading} title="Test">
                        <TestTube className="h-3 w-3" />
                      </Button>
                      <Button variant="ghost" size="sm" onClick={() => handleDeleteCredential(credential.id, credential.name)} disabled={credentialLoading} title="Delete">
                        <Trash2 className="h-3 w-3 text-theme-error" />
                      </Button>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Add New Credential */}
          <div className="space-y-3 p-4 border border-dashed border-theme rounded-lg">
            <h5 className="text-sm font-medium text-theme-secondary flex items-center gap-2">
              <Plus className="h-4 w-4" />
              Add New Credential
            </h5>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label className="block text-xs text-theme-tertiary mb-1">Credential Name</label>
                <Input
                  value={newCredential.name}
                  onChange={(e) => setNewCredential(prev => ({ ...prev, name: e.target.value }))}
                  placeholder="e.g., Production Key"
                />
              </div>
              <div>
                <label className="block text-xs text-theme-tertiary mb-1">API Key</label>
                <Input
                  value={newCredential.api_key}
                  onChange={(e) => setNewCredential(prev => ({ ...prev, api_key: e.target.value }))}
                  placeholder="Enter API key"
                  type="password"
                />
              </div>
            </div>
            <p className="text-xs text-theme-tertiary">New credential will be created when you save changes.</p>
          </div>
        </div>

        <div className="flex items-center justify-end space-x-3 pt-4 border-t border-theme">
          <Button type="button" variant="outline" onClick={handleClose} disabled={submitting}>
            Cancel
          </Button>
          <Button type="submit" disabled={submitting || !formData.name} className="flex items-center gap-2">
            <Save className="h-4 w-4" />
            {submitting ? 'Updating...' : 'Update Data Source'}
          </Button>
        </div>
      </form>
      {ConfirmationDialog}
    </Modal>
  );
};
