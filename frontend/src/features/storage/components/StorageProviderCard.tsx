import React, { useState } from 'react';
import {
  HardDrive,
  Cloud,
  Database,
  CheckCircle,
  XCircle,
  AlertCircle,
  MoreVertical,
  Star,
  Settings,
  Trash2,
  RefreshCw,
} from 'lucide-react';
import { StorageProvider } from '@/shared/types/storage';

interface StorageProviderCardProps {
  provider: StorageProvider;
  onEdit: (provider: StorageProvider) => void;
  onDelete: (provider: StorageProvider) => void;
  onTest: (provider: StorageProvider) => void;
  onSetDefault: (provider: StorageProvider) => void;
  testing?: boolean;
}

export const StorageProviderCard: React.FC<StorageProviderCardProps> = ({
  provider,
  onEdit,
  onDelete,
  onTest,
  onSetDefault,
  testing = false,
}) => {
  const [showMenu, setShowMenu] = useState(false);

  const getProviderIcon = () => {
    switch (provider.provider_type) {
      case 'local':
        return <HardDrive className="h-6 w-6 text-theme-info" />;
      case 's3':
        return <Cloud className="h-6 w-6 text-theme-warning" />;
      case 'azure_blob':
        return <Cloud className="h-6 w-6 text-blue-400" />;
      case 'gcs':
        return <Database className="h-6 w-6 text-theme-success" />;
      default:
        return <HardDrive className="h-6 w-6 text-theme-secondary" />;
    }
  };

  const getProviderLabel = () => {
    switch (provider.provider_type) {
      case 'local':
        return 'Local Storage';
      case 's3':
        return 'Amazon S3';
      case 'azure_blob':
        return 'Azure Blob Storage';
      case 'gcs':
        return 'Google Cloud Storage';
      default:
        return 'Unknown';
    }
  };

  const getStatusIcon = () => {
    switch (provider.status) {
      case 'active':
        return <CheckCircle className="h-5 w-5 text-theme-success" />;
      case 'inactive':
        return <AlertCircle className="h-5 w-5 text-yellow-500" />;
      case 'error':
        return <XCircle className="h-5 w-5 text-theme-danger" />;
      default:
        return <AlertCircle className="h-5 w-5 text-theme-secondary" />;
    }
  };

  const formatBytes = (bytes: number): string => {
    if (bytes === 0) return '0 Bytes';
    const k = 1024;
    const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return `${parseFloat((bytes / Math.pow(k, i)).toFixed(2))} ${sizes[i]}`;
  };

  return (
    <div className="bg-theme-surface border border-theme rounded-lg p-6 hover:border-theme-info transition-colors relative">
      {/* Header */}
      <div className="flex items-start justify-between mb-4">
        <div className="flex items-center gap-3">
          {getProviderIcon()}
          <div>
            <div className="flex items-center gap-2">
              <h3 className="text-lg font-semibold text-theme-primary">{provider.name}</h3>
              {provider.is_default && (
                <span className="flex items-center gap-1 px-2 py-0.5 bg-yellow-100 dark:bg-yellow-900/30 text-yellow-800 dark:text-yellow-300 text-xs rounded-full">
                  <Star className="h-3 w-3 fill-current" />
                  Default
                </span>
              )}
            </div>
            <p className="text-sm text-theme-secondary">{getProviderLabel()}</p>
          </div>
        </div>

        {/* Status and Menu */}
        <div className="flex items-center gap-2">
          {getStatusIcon()}
          <div className="relative">
            <button
              onClick={() => setShowMenu(!showMenu)}
              className="p-1 hover:bg-theme-hover rounded transition-colors"
            >
              <MoreVertical className="h-5 w-5 text-theme-secondary" />
            </button>

            {showMenu && (
              <>
                <div
                  className="fixed inset-0 z-10"
                  onClick={() => setShowMenu(false)}
                />
                <div className="absolute right-0 top-8 z-20 w-48 bg-theme-surface border border-theme rounded-lg shadow-lg py-1">
                  <button
                    onClick={() => {
                      setShowMenu(false);
                      onEdit(provider);
                    }}
                    className="w-full px-4 py-2 text-left text-sm text-theme-primary hover:bg-theme-hover flex items-center gap-2"
                  >
                    <Settings className="h-4 w-4" />
                    Configure
                  </button>
                  <button
                    onClick={() => {
                      setShowMenu(false);
                      onTest(provider);
                    }}
                    disabled={testing}
                    className="w-full px-4 py-2 text-left text-sm text-theme-primary hover:bg-theme-hover flex items-center gap-2 disabled:opacity-50"
                  >
                    <RefreshCw className={`h-4 w-4 ${testing ? 'animate-spin' : ''}`} />
                    Test Connection
                  </button>
                  {!provider.is_default && (
                    <button
                      onClick={() => {
                        setShowMenu(false);
                        onSetDefault(provider);
                      }}
                      className="w-full px-4 py-2 text-left text-sm text-theme-primary hover:bg-theme-hover flex items-center gap-2"
                    >
                      <Star className="h-4 w-4" />
                      Set as Default
                    </button>
                  )}
                  <hr className="my-1 border-theme" />
                  <button
                    onClick={() => {
                      setShowMenu(false);
                      onDelete(provider);
                    }}
                    className="w-full px-4 py-2 text-left text-sm text-theme-danger dark:text-red-400 hover:bg-red-50 dark:hover:bg-red-900/20 flex items-center gap-2"
                  >
                    <Trash2 className="h-4 w-4" />
                    Delete
                  </button>
                </div>
              </>
            )}
          </div>
        </div>
      </div>

      {/* Stats */}
      {provider.usage_stats && (
        <div className="grid grid-cols-2 gap-4 mb-4">
          <div>
            <p className="text-xs text-theme-secondary mb-1">Total Files</p>
            <p className="text-lg font-semibold text-theme-primary">
              {provider.usage_stats.total_files.toLocaleString()}
            </p>
          </div>
          <div>
            <p className="text-xs text-theme-secondary mb-1">Storage Used</p>
            <p className="text-lg font-semibold text-theme-primary">
              {formatBytes(provider.usage_stats.total_size_bytes)}
            </p>
          </div>
        </div>
      )}

      {/* Configuration Details */}
      <div className="space-y-2 text-sm">
        {provider.max_file_size_mb && (
          <div className="flex items-center justify-between">
            <span className="text-theme-secondary">Max File Size</span>
            <span className="text-theme-primary font-medium">{provider.max_file_size_mb} MB</span>
          </div>
        )}
        {provider.last_tested_at && (
          <div className="flex items-center justify-between">
            <span className="text-theme-secondary">Last Tested</span>
            <span className="text-theme-primary">
              {new Date(provider.last_tested_at).toLocaleDateString()}
            </span>
          </div>
        )}
        {provider.allowed_file_types && provider.allowed_file_types.length > 0 && (
          <div className="flex items-start justify-between">
            <span className="text-theme-secondary">Allowed Types</span>
            <span className="text-theme-primary text-right max-w-[200px]">
              {provider.allowed_file_types.slice(0, 3).join(', ')}
              {provider.allowed_file_types.length > 3 && ` +${provider.allowed_file_types.length - 3}`}
            </span>
          </div>
        )}
      </div>
    </div>
  );
};

