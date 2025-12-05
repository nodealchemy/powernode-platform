import React, { useState, useEffect } from 'react';
import { HardDrive, Cloud, Database } from 'lucide-react';
import Modal from '@/shared/components/ui/Modal';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';
import {
  StorageProvider,
  StorageProviderType,
  StorageProviderFormData,
  LocalStorageConfig,
  S3StorageConfig,
  AzureBlobStorageConfig,
  GCSStorageConfig,
} from '@/shared/types/storage';

interface StorageProviderModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSave: (data: StorageProviderFormData) => Promise<void>;
  provider?: StorageProvider | null;
  saving?: boolean;
}

export const StorageProviderModal: React.FC<StorageProviderModalProps> = ({
  isOpen,
  onClose,
  onSave,
  provider,
  saving = false,
}) => {
  const isEditMode = !!provider;

  const [formData, setFormData] = useState<StorageProviderFormData>({
    name: '',
    provider_type: 'local',
    status: 'active',
    is_default: false,
    max_file_size_mb: 100,
    allowed_file_types: [],
    configuration: {
      base_path: '/var/storage',
      create_directories: true,
    },
  });

  const [fileTypesInput, setFileTypesInput] = useState('');

  useEffect(() => {
    if (provider) {
      setFormData({
        name: provider.name,
        provider_type: provider.provider_type,
        status: provider.status,
        is_default: provider.is_default,
        max_file_size_mb: provider.max_file_size_mb,
        allowed_file_types: provider.allowed_file_types,
        configuration: provider.configuration,
      });
      setFileTypesInput(provider.allowed_file_types?.join(', ') || '');
    } else {
      // Reset form for new provider
      setFormData({
        name: '',
        provider_type: 'local',
        status: 'active',
        is_default: false,
        max_file_size_mb: 100,
        allowed_file_types: [],
        configuration: {
          base_path: '/var/storage',
          create_directories: true,
        },
      });
      setFileTypesInput('');
    }
  }, [provider, isOpen]);

  const handleProviderTypeChange = (type: StorageProviderType) => {
    let defaultConfiguration;
    switch (type) {
      case 'local':
        defaultConfiguration = {
          base_path: '/var/storage',
          create_directories: true,
        };
        break;
      case 's3':
        defaultConfiguration = {
          bucket: '',
          region: 'us-east-1',
          access_key_id: '',
          secret_access_key: '',
          path_prefix: '',
        };
        break;
      case 'azure_blob':
        defaultConfiguration = {
          account_name: '',
          account_key: '',
          container: '',
        };
        break;
      case 'gcs':
        defaultConfiguration = {
          project_id: '',
          bucket: '',
          credentials_json: '',
          path_prefix: '',
        };
        break;
    }

    setFormData({
      ...formData,
      provider_type: type,
      configuration: defaultConfiguration,
    });
  };

  const handleConfigChange = (field: string, value: string | boolean) => {
    setFormData({
      ...formData,
      configuration: {
        ...formData.configuration,
        [field]: value,
      },
    });
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    const fileTypes = fileTypesInput
      .split(',')
      .map((type) => type.trim())
      .filter((type) => type.length > 0);

    await onSave({
      ...formData,
      allowed_file_types: fileTypes.length > 0 ? fileTypes : undefined,
    });
  };

  const renderConfigFields = () => {
    switch (formData.provider_type) {
      case 'local':
        const localConfig = formData.configuration as LocalStorageConfig;
        return (
          <>
            <Input
              label="Base Path"
              type="text"
              value={localConfig.base_path}
              onChange={(e) => handleConfigChange('base_path', e.target.value)}
              required
              placeholder="/var/storage"
            />
            <div className="flex items-center gap-2">
              <input
                type="checkbox"
                id="create_directories"
                checked={localConfig.create_directories}
                onChange={(e) => handleConfigChange('create_directories', e.target.checked)}
                className="rounded border-theme-secondary"
              />
              <label htmlFor="create_directories" className="text-sm text-theme-primary">
                Auto-create directories
              </label>
            </div>
          </>
        );

      case 's3':
        const s3Config = formData.configuration as S3StorageConfig;
        return (
          <>
            <Input
              label="Bucket Name"
              type="text"
              value={s3Config.bucket}
              onChange={(e) => handleConfigChange('bucket', e.target.value)}
              required
              placeholder="my-bucket"
            />
            <Input
              label="Region"
              type="text"
              value={s3Config.region}
              onChange={(e) => handleConfigChange('region', e.target.value)}
              required
              placeholder="us-east-1"
            />
            <Input
              label="Access Key ID"
              type="text"
              value={s3Config.access_key_id}
              onChange={(e) => handleConfigChange('access_key_id', e.target.value)}
              required
              placeholder="AKIAIOSFODNN7EXAMPLE"
            />
            <Input
              label="Secret Access Key"
              type="password"
              value={s3Config.secret_access_key}
              onChange={(e) => handleConfigChange('secret_access_key', e.target.value)}
              required
              placeholder="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
            />
            <Input
              label="Custom Endpoint (Optional)"
              type="text"
              value={s3Config.endpoint || ''}
              onChange={(e) => handleConfigChange('endpoint', e.target.value)}
              placeholder="https://s3-compatible.example.com"
            />
            <Input
              label="Path Prefix (Optional)"
              type="text"
              value={s3Config.path_prefix || ''}
              onChange={(e) => handleConfigChange('path_prefix', e.target.value)}
              placeholder="uploads/"
            />
          </>
        );

      case 'azure_blob':
        const azureConfig = formData.configuration as AzureBlobStorageConfig;
        return (
          <>
            <Input
              label="Account Name"
              type="text"
              value={azureConfig.account_name}
              onChange={(e) => handleConfigChange('account_name', e.target.value)}
              required
              placeholder="mystorageaccount"
            />
            <Input
              label="Account Key"
              type="password"
              value={azureConfig.account_key}
              onChange={(e) => handleConfigChange('account_key', e.target.value)}
              required
              placeholder="••••••••••••••••"
            />
            <Input
              label="Container Name"
              type="text"
              value={azureConfig.container}
              onChange={(e) => handleConfigChange('container', e.target.value)}
              required
              placeholder="uploads"
            />
            <Input
              label="Custom Endpoint (Optional)"
              type="text"
              value={azureConfig.endpoint || ''}
              onChange={(e) => handleConfigChange('endpoint', e.target.value)}
              placeholder="https://mystorageaccount.blob.core.windows.net"
            />
          </>
        );

      case 'gcs':
        const gcsConfig = formData.configuration as GCSStorageConfig;
        return (
          <>
            <Input
              label="Project ID"
              type="text"
              value={gcsConfig.project_id}
              onChange={(e) => handleConfigChange('project_id', e.target.value)}
              required
              placeholder="my-project-12345"
            />
            <Input
              label="Bucket Name"
              type="text"
              value={gcsConfig.bucket}
              onChange={(e) => handleConfigChange('bucket', e.target.value)}
              required
              placeholder="my-bucket"
            />
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">
                Service Account JSON
              </label>
              <textarea
                value={gcsConfig.credentials_json}
                onChange={(e) => handleConfigChange('credentials_json', e.target.value)}
                required
                rows={4}
                className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-blue-500 font-mono text-xs"
                placeholder='{"type":"service_account","project_id":"..."}'
              />
            </div>
            <Input
              label="Path Prefix (Optional)"
              type="text"
              value={gcsConfig.path_prefix || ''}
              onChange={(e) => handleConfigChange('path_prefix', e.target.value)}
              placeholder="uploads/"
            />
          </>
        );
    }
  };

  const getProviderIcon = () => {
    switch (formData.provider_type) {
      case 'local':
        return <HardDrive className="h-5 w-5" />;
      case 's3':
        return <Cloud className="h-5 w-5" />;
      case 'azure_blob':
        return <Cloud className="h-5 w-5" />;
      case 'gcs':
        return <Database className="h-5 w-5" />;
    }
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={
        <div className="flex items-center gap-2">
          {getProviderIcon()}
          {isEditMode ? 'Edit Storage Provider' : 'Add Storage Provider'}
        </div>
      }
      size="lg"
    >
      <form onSubmit={handleSubmit} className="space-y-4">
        {/* Basic Information */}
        <div className="space-y-4">
          <Input
            label="Provider Name"
            type="text"
            value={formData.name}
            onChange={(e) => setFormData({ ...formData, name: e.target.value })}
            required
            placeholder="Production Storage"
          />

          <Select
            label="Provider Type"
            value={formData.provider_type}
            onChange={(value) => handleProviderTypeChange(value as StorageProviderType)}
            disabled={isEditMode}
          >
            <option value="local">Local Storage</option>
            <option value="s3">Amazon S3</option>
            <option value="azure_blob">Azure Blob Storage</option>
            <option value="gcs">Google Cloud Storage</option>
          </Select>

          <Select
            label="Status"
            value={formData.status}
            onChange={(value) => setFormData({ ...formData, status: value as 'active' | 'inactive' | 'error' })}
          >
            <option value="active">Active</option>
            <option value="inactive">Inactive</option>
          </Select>
        </div>

        {/* Provider-specific Configuration */}
        <div className="border-t border-theme pt-4 space-y-4">
          <h4 className="text-sm font-medium text-theme-primary">Configuration</h4>
          {renderConfigFields()}
        </div>

        {/* Optional Settings */}
        <div className="border-t border-theme pt-4 space-y-4">
          <h4 className="text-sm font-medium text-theme-primary">Optional Settings</h4>

          <Input
            label="Max File Size (MB)"
            type="number"
            value={formData.max_file_size_mb || ''}
            onChange={(e) => setFormData({ ...formData, max_file_size_mb: parseInt(e.target.value) || undefined })}
            placeholder="100"
          />

          <Input
            label="Allowed File Types (comma-separated)"
            type="text"
            value={fileTypesInput}
            onChange={(e) => setFileTypesInput(e.target.value)}
            placeholder="jpg, png, pdf, doc"
          />

          <div className="flex items-center gap-2">
            <input
              type="checkbox"
              id="is_default"
              checked={formData.is_default}
              onChange={(e) => setFormData({ ...formData, is_default: e.target.checked })}
              className="rounded border-theme-secondary"
            />
            <label htmlFor="is_default" className="text-sm text-theme-primary">
              Set as default storage provider
            </label>
          </div>
        </div>

        {/* Actions */}
        <div className="flex items-center justify-end gap-3 pt-4 border-t border-theme">
          <button
            type="button"
            onClick={onClose}
            disabled={saving}
            className="px-4 py-2 text-sm text-theme-primary hover:bg-theme-hover rounded-lg transition-colors disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={saving}
            className="px-4 py-2 text-sm bg-theme-info text-white rounded-lg hover:bg-blue-700 transition-colors disabled:opacity-50 flex items-center gap-2"
          >
            {saving ? (
              <>
                <div className="animate-spin h-4 w-4 border-2 border-white border-t-transparent rounded-full" />
                Saving...
              </>
            ) : (
              isEditMode ? 'Update Provider' : 'Create Provider'
            )}
          </button>
        </div>
      </form>
    </Modal>
  );
};

