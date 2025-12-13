// Storage Provider Types

export type StorageProviderType =
  | 'local'
  | 's3'
  | 'gcs'
  | 'azure_blob'
  | 'nfs'
  | 'smb'
  // S3-compatible providers
  | 'backblaze_b2'
  | 'digitalocean_spaces'
  | 'cloudflare_r2'
  | 'minio'
  | 'wasabi';

export type StorageProviderStatus = 'active' | 'inactive' | 'error';

// S3-compatible providers use S3StorageConfig with custom endpoints
export const S3_COMPATIBLE_PROVIDERS: StorageProviderType[] = [
  'backblaze_b2',
  'digitalocean_spaces',
  'cloudflare_r2',
  'minio',
  'wasabi',
];

export const NETWORK_FS_PROVIDERS: StorageProviderType[] = ['nfs', 'smb'];

// Provider display information
export const PROVIDER_INFO: Record<StorageProviderType, { name: string; description: string; category: string }> = {
  local: { name: 'Local Storage', description: 'Store files on the local filesystem', category: 'local' },
  s3: { name: 'Amazon S3', description: 'Amazon Simple Storage Service', category: 'cloud' },
  gcs: { name: 'Google Cloud Storage', description: 'Google Cloud Platform object storage', category: 'cloud' },
  azure_blob: { name: 'Azure Blob Storage', description: 'Microsoft Azure object storage', category: 'cloud' },
  nfs: { name: 'NFS', description: 'Network File System for Unix/Linux environments', category: 'network' },
  smb: { name: 'SMB/CIFS', description: 'Server Message Block for Windows network shares', category: 'network' },
  backblaze_b2: { name: 'Backblaze B2', description: 'Cost-effective S3-compatible cloud storage', category: 's3-compatible' },
  digitalocean_spaces: { name: 'DigitalOcean Spaces', description: 'S3-compatible object storage', category: 's3-compatible' },
  cloudflare_r2: { name: 'Cloudflare R2', description: 'S3-compatible storage with zero egress fees', category: 's3-compatible' },
  minio: { name: 'MinIO', description: 'Self-hosted S3-compatible object storage', category: 's3-compatible' },
  wasabi: { name: 'Wasabi', description: 'Hot cloud storage with no egress fees', category: 's3-compatible' },
};

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

export interface NFSStorageConfig {
  server: string;
  export_path: string;
  mount_point: string;
  mount_options?: string;
  version?: '3' | '4' | '4.1' | '4.2';
}

export interface SMBStorageConfig {
  server: string;
  share: string;
  mount_point: string;
  username?: string;
  password?: string;
  domain?: string;
  mount_options?: string;
}

export type StorageProviderConfig =
  | { provider_type: 'local'; configuration: LocalStorageConfig }
  | { provider_type: 's3'; configuration: S3StorageConfig }
  | { provider_type: 'azure_blob'; configuration: AzureBlobStorageConfig }
  | { provider_type: 'gcs'; configuration: GCSStorageConfig }
  | { provider_type: 'nfs'; configuration: NFSStorageConfig }
  | { provider_type: 'smb'; configuration: SMBStorageConfig }
  // S3-compatible providers use S3StorageConfig
  | { provider_type: 'backblaze_b2'; configuration: S3StorageConfig }
  | { provider_type: 'digitalocean_spaces'; configuration: S3StorageConfig }
  | { provider_type: 'cloudflare_r2'; configuration: S3StorageConfig }
  | { provider_type: 'minio'; configuration: S3StorageConfig }
  | { provider_type: 'wasabi'; configuration: S3StorageConfig };

export type AllStorageConfigs =
  | LocalStorageConfig
  | S3StorageConfig
  | AzureBlobStorageConfig
  | GCSStorageConfig
  | NFSStorageConfig
  | SMBStorageConfig;

export interface StorageProvider extends StorageProviderBase {
  configuration: AllStorageConfigs;
}

export interface StorageProviderFormData {
  name: string;
  provider_type: StorageProviderType;
  status: StorageProviderStatus;
  is_default: boolean;
  max_file_size_mb?: number;
  allowed_file_types?: string[];
  configuration: AllStorageConfigs;
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
