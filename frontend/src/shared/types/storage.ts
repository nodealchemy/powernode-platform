// Storage Provider Types

export type StorageProviderType = 'local' | 's3' | 'azure_blob' | 'gcs';

export type StorageProviderStatus = 'active' | 'inactive' | 'error';

export interface StorageProviderBase {
  id: string;
  name: string;
  provider_type: StorageProviderType;
  status: StorageProviderStatus;
  is_default: boolean;
  max_file_size_mb?: number;
  allowed_file_types?: string[];
  created_at: string;
  updated_at: string;
  last_tested_at?: string;
  usage_stats?: {
    total_files: number;
    total_size_bytes: number;
    total_size_mb: number;
  };
}

export interface LocalStorageConfig {
  base_path: string;
  create_directories: boolean;
}

export interface S3StorageConfig {
  bucket: string;
  region: string;
  access_key_id: string;
  secret_access_key: string;
  endpoint?: string; // For S3-compatible services
  path_prefix?: string;
}

export interface AzureBlobStorageConfig {
  account_name: string;
  account_key: string;
  container: string;
  endpoint?: string;
}

export interface GCSStorageConfig {
  project_id: string;
  bucket: string;
  credentials_json: string;
  path_prefix?: string;
}

export type StorageProviderConfig =
  | { provider_type: 'local'; configuration: LocalStorageConfig }
  | { provider_type: 's3'; configuration: S3StorageConfig }
  | { provider_type: 'azure_blob'; configuration: AzureBlobStorageConfig }
  | { provider_type: 'gcs'; configuration: GCSStorageConfig };

export interface StorageProvider extends StorageProviderBase {
  configuration: LocalStorageConfig | S3StorageConfig | AzureBlobStorageConfig | GCSStorageConfig;
}

export interface StorageProviderFormData {
  name: string;
  provider_type: StorageProviderType;
  status: StorageProviderStatus;
  is_default: boolean;
  max_file_size_mb?: number;
  allowed_file_types?: string[];
  configuration: LocalStorageConfig | S3StorageConfig | AzureBlobStorageConfig | GCSStorageConfig;
}

export interface StorageConnectionTestResult {
  success: boolean;
  message: string;
  details?: {
    readable?: boolean;
    writable?: boolean;
    deletable?: boolean;
    latency_ms?: number;
    error?: string;
  };
}
