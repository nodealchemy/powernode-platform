import React, { useState, useEffect } from 'react';
import { HardDrive, Cloud, Database, Network, Server } from 'lucide-react';
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
  NFSStorageConfig,
  SMBStorageConfig,
  PROVIDER_INFO,
  S3_COMPATIBLE_PROVIDERS,
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

  const getDefaultS3Config = (type: StorageProviderType): S3StorageConfig => {
    const baseConfig = {
      bucket: '',
      region: 'us-east-1',
      access_key_id: '',
      secret_access_key: '',
      path_prefix: '',
      endpoint: '',
    };

    // Set default endpoints for S3-compatible providers
    switch (type) {
      case 'backblaze_b2':
        return { ...baseConfig, endpoint: 'https://s3.us-west-000.backblazeb2.com' };
      case 'digitalocean_spaces':
        return { ...baseConfig, endpoint: 'https://nyc3.digitaloceanspaces.com', region: 'nyc3' };
      case 'cloudflare_r2':
        return { ...baseConfig, endpoint: 'https://<account_id>.r2.cloudflarestorage.com', region: 'auto' };
      case 'minio':
        return { ...baseConfig, endpoint: 'http://localhost:9000' };
      case 'wasabi':
        return { ...baseConfig, endpoint: 'https://s3.wasabisys.com', region: 'us-east-1' };
      default:
        return baseConfig;
    }
  };

  const handleProviderTypeChange = (type: StorageProviderType) => {
    let defaultConfiguration;

    // S3-compatible providers use S3 config
    if (S3_COMPATIBLE_PROVIDERS.includes(type) || type === 's3') {
      defaultConfiguration = getDefaultS3Config(type);
    } else {
      switch (type) {
        case 'local':
          defaultConfiguration = {
            base_path: '/var/storage',
            create_directories: true,
          };
          break;
        case 'azure_blob':
          defaultConfiguration = {
            account_name: '',
            account_key: '',
            container: '',
            endpoint: '',
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
        case 'nfs':
          defaultConfiguration = {
            server: '',
            export_path: '/exports/data',
            mount_point: '/mnt/nfs',
            mount_options: 'rw,sync',
            version: '4' as const,
          };
          break;
        case 'smb':
          defaultConfiguration = {
            server: '',
            share: '',
            mount_point: '/mnt/smb',
            username: '',
            password: '',
            domain: '',
            mount_options: '',
          };
          break;
        default:
          // Fallback to local storage config for any unknown types
          defaultConfiguration = {
            base_path: '/var/storage',
            create_directories: true,
          };
      }
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

  const renderS3ConfigFields = (isS3Compatible: boolean = false) => {
    const s3Config = formData.configuration as S3StorageConfig;
    const providerName = PROVIDER_INFO[formData.provider_type]?.name || 'S3';

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
          label={isS3Compatible ? `${providerName} Endpoint` : 'Custom Endpoint (Optional)'}
          type="text"
          value={s3Config.endpoint || ''}
          onChange={(e) => handleConfigChange('endpoint', e.target.value)}
          required={isS3Compatible}
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
  };

  const renderConfigFields = () => {
    // S3-compatible providers
    if (S3_COMPATIBLE_PROVIDERS.includes(formData.provider_type)) {
      return renderS3ConfigFields(true);
    }

    switch (formData.provider_type) {
      case 'local': {
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
      }

      case 's3':
        return renderS3ConfigFields(false);

      case 'azure_blob': {
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
      }

      case 'gcs': {
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
                className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-info font-mono text-xs"
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

      case 'nfs': {
        const nfsConfig = formData.configuration as NFSStorageConfig;
        return (
          <>
            <Input
              label="NFS Server"
              type="text"
              value={nfsConfig.server}
              onChange={(e) => handleConfigChange('server', e.target.value)}
              required
              placeholder="nfs.example.com or 192.168.1.100"
            />
            <Input
              label="Export Path"
              type="text"
              value={nfsConfig.export_path}
              onChange={(e) => handleConfigChange('export_path', e.target.value)}
              required
              placeholder="/exports/data"
            />
            <Input
              label="Local Mount Point"
              type="text"
              value={nfsConfig.mount_point}
              onChange={(e) => handleConfigChange('mount_point', e.target.value)}
              required
              placeholder="/mnt/nfs"
            />
            <Select
              label="NFS Version"
              value={nfsConfig.version || '4'}
              onChange={(value) => handleConfigChange('version', value)}
            >
              <option value="3">NFSv3</option>
              <option value="4">NFSv4</option>
              <option value="4.1">NFSv4.1</option>
              <option value="4.2">NFSv4.2</option>
            </Select>
            <Input
              label="Mount Options (Optional)"
              type="text"
              value={nfsConfig.mount_options || ''}
              onChange={(e) => handleConfigChange('mount_options', e.target.value)}
              placeholder="rw,sync,hard,intr"
            />
          </>
        );
      }

      case 'smb': {
        const smbConfig = formData.configuration as SMBStorageConfig;
        return (
          <>
            <Input
              label="SMB Server"
              type="text"
              value={smbConfig.server}
              onChange={(e) => handleConfigChange('server', e.target.value)}
              required
              placeholder="fileserver.example.com or 192.168.1.100"
            />
            <Input
              label="Share Name"
              type="text"
              value={smbConfig.share}
              onChange={(e) => handleConfigChange('share', e.target.value)}
              required
              placeholder="shared_files"
            />
            <Input
              label="Local Mount Point"
              type="text"
              value={smbConfig.mount_point}
              onChange={(e) => handleConfigChange('mount_point', e.target.value)}
              required
              placeholder="/mnt/smb"
            />
            <Input
              label="Username (Optional)"
              type="text"
              value={smbConfig.username || ''}
              onChange={(e) => handleConfigChange('username', e.target.value)}
              placeholder="domain\\username or username"
            />
            <Input
              label="Password (Optional)"
              type="password"
              value={smbConfig.password || ''}
              onChange={(e) => handleConfigChange('password', e.target.value)}
              placeholder="••••••••••••••••"
            />
            <Input
              label="Domain (Optional)"
              type="text"
              value={smbConfig.domain || ''}
              onChange={(e) => handleConfigChange('domain', e.target.value)}
              placeholder="WORKGROUP"
            />
            <Input
              label="Mount Options (Optional)"
              type="text"
              value={smbConfig.mount_options || ''}
              onChange={(e) => handleConfigChange('mount_options', e.target.value)}
              placeholder="vers=3.0,sec=ntlmssp"
            />
          </>
        );
      }

      default:
        return null;
    }
  };

  const getProviderIcon = () => {
    const type = formData.provider_type;

    // Network filesystem providers
    if (type === 'nfs' || type === 'smb') {
      return <Network className="h-5 w-5" />;
    }

    // Cloud/S3-compatible providers
    if (S3_COMPATIBLE_PROVIDERS.includes(type) || type === 's3' || type === 'azure_blob') {
      return <Cloud className="h-5 w-5" />;
    }

    switch (type) {
      case 'local':
        return <HardDrive className="h-5 w-5" />;
      case 'gcs':
        return <Database className="h-5 w-5" />;
      default:
        return <Server className="h-5 w-5" />;
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
            <optgroup label="Local">
              <option value="local">Local Storage</option>
            </optgroup>
            <optgroup label="Cloud Providers">
              <option value="s3">Amazon S3</option>
              <option value="gcs">Google Cloud Storage</option>
              <option value="azure_blob">Azure Blob Storage</option>
            </optgroup>
            <optgroup label="S3-Compatible">
              <option value="backblaze_b2">Backblaze B2</option>
              <option value="cloudflare_r2">Cloudflare R2</option>
              <option value="digitalocean_spaces">DigitalOcean Spaces</option>
              <option value="minio">MinIO</option>
              <option value="wasabi">Wasabi</option>
            </optgroup>
            <optgroup label="Network Filesystems">
              <option value="nfs">NFS</option>
              <option value="smb">SMB/CIFS</option>
            </optgroup>
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
            className="px-4 py-2 text-sm bg-theme-info text-white rounded-lg hover:opacity-90 transition-colors disabled:opacity-50 flex items-center gap-2"
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

