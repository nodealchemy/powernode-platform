# File Management System - Complete Implementation

**Status**: ✅ Complete
**Date**: January 19, 2025
**Version**: 1.0.0

## Overview

The File Management System provides universal file storage capabilities across the Powernode platform with multi-provider support, AI workflow integration, and comprehensive file lifecycle management.

## Architecture

### Core Components

```
File Management System
├── Database Layer (7 tables)
│   ├── file_storages (provider configurations)
│   ├── file_objects (universal file tracking)
│   ├── file_versions (version history)
│   ├── file_shares (external sharing)
│   ├── file_processing_jobs (async processing)
│   ├── file_tags (organization)
│   └── file_object_tags (many-to-many)
│
├── Storage Provider Layer
│   ├── StorageProviders::Base (abstract interface)
│   ├── StorageProviders::LocalStorage (filesystem)
│   ├── StorageProviders::S3Storage (AWS S3)
│   ├── StorageProviders::GcsStorage (Google Cloud)
│   └── StorageProviders::AzureStorage (Azure Blob)
│
├── Service Layer
│   ├── FileStorageService (main interface)
│   └── StorageProviderFactory (dynamic instantiation)
│
├── API Layer
│   ├── Api::V1::FilesController
│   └── Api::V1::StorageProvidersController
│
└── Workflow Integration
    ├── Mcp::NodeExecutors::FileUpload
    ├── Mcp::NodeExecutors::FileDownload
    └── Mcp::NodeExecutors::FileTransform
```

## Database Schema

### file_storages
Stores storage provider configurations for each account.

```sql
CREATE TABLE file_storages (
  id UUID PRIMARY KEY,
  account_id UUID NOT NULL REFERENCES accounts(id),
  name VARCHAR(255) NOT NULL,
  provider_type VARCHAR(50) NOT NULL,  -- local, s3, gcs, azure
  configuration JSONB NOT NULL,         -- Provider-specific config
  is_default BOOLEAN DEFAULT false,
  quota_enabled BOOLEAN DEFAULT false,
  quota_bytes BIGINT,
  files_count INTEGER DEFAULT 0,
  total_size_bytes BIGINT DEFAULT 0,
  blocked_extensions TEXT[] DEFAULT '{}',
  blocked_mime_types TEXT[] DEFAULT '{}'
);

CREATE INDEX idx_file_storages_account ON file_storages(account_id);
CREATE INDEX idx_file_storages_default ON file_storages(account_id, is_default) WHERE is_default = true;
```

### file_objects
Universal file tracking across all storage providers.

```sql
CREATE TABLE file_objects (
  id UUID PRIMARY KEY,
  account_id UUID NOT NULL REFERENCES accounts(id),
  file_storage_id UUID NOT NULL REFERENCES file_storages(id),
  storage_key VARCHAR(1024) NOT NULL,   -- Unique key in storage
  filename VARCHAR(255) NOT NULL,
  content_type VARCHAR(100),
  file_size BIGINT NOT NULL,
  checksum_md5 VARCHAR(32),
  checksum_sha256 VARCHAR(64),
  visibility VARCHAR(20) DEFAULT 'private',  -- private, public, shared
  category VARCHAR(100),                      -- user_upload, workflow_output, etc.
  description TEXT,
  metadata JSONB DEFAULT '{}',
  version INTEGER DEFAULT 1,
  is_latest_version BOOLEAN DEFAULT true,
  parent_file_id UUID REFERENCES file_objects(id),
  uploaded_by_id UUID REFERENCES users(id),
  deleted_at TIMESTAMP,
  attachable_type VARCHAR(100),
  attachable_id UUID
);

CREATE INDEX idx_file_objects_account ON file_objects(account_id);
CREATE INDEX idx_file_objects_storage ON file_objects(file_storage_id);
CREATE INDEX idx_file_objects_visibility ON file_objects(visibility);
CREATE INDEX idx_file_objects_category ON file_objects(category);
CREATE INDEX idx_file_objects_attachable ON file_objects(attachable_type, attachable_id);
CREATE INDEX idx_file_objects_deleted ON file_objects(deleted_at);
```

### file_versions
Tracks complete version history of files.

```sql
CREATE TABLE file_versions (
  id UUID PRIMARY KEY,
  file_object_id UUID NOT NULL REFERENCES file_objects(id) ON DELETE CASCADE,
  version INTEGER NOT NULL,
  created_by_id UUID REFERENCES users(id),
  change_description TEXT
);
```

### file_shares
External file sharing with access control.

```sql
CREATE TABLE file_shares (
  id UUID PRIMARY KEY,
  file_object_id UUID NOT NULL REFERENCES file_objects(id) ON DELETE CASCADE,
  account_id UUID NOT NULL REFERENCES accounts(id),
  share_token VARCHAR(64) UNIQUE NOT NULL,
  password_digest VARCHAR(255),
  expires_at TIMESTAMP,
  max_downloads INTEGER,
  download_count INTEGER DEFAULT 0,
  last_accessed_at TIMESTAMP,
  allow_download BOOLEAN DEFAULT true,
  require_email BOOLEAN DEFAULT false,
  notify_on_access BOOLEAN DEFAULT false,
  access_log JSONB DEFAULT '[]',
  created_by_id UUID REFERENCES users(id)
);

CREATE INDEX idx_file_shares_token ON file_shares(share_token);
CREATE INDEX idx_file_shares_expires ON file_shares(expires_at);
```

### file_processing_jobs
Async file processing (thumbnails, OCR, transformations).

```sql
CREATE TABLE file_processing_jobs (
  id UUID PRIMARY KEY,
  file_object_id UUID NOT NULL REFERENCES file_objects(id) ON DELETE CASCADE,
  account_id UUID NOT NULL REFERENCES accounts(id),
  job_type VARCHAR(50) NOT NULL,  -- thumbnail, ocr, virus_scan, metadata_extraction
  status VARCHAR(20) DEFAULT 'pending',
  configuration JSONB DEFAULT '{}',
  result JSONB,
  error_message TEXT,
  started_at TIMESTAMP,
  completed_at TIMESTAMP
);

CREATE INDEX idx_file_processing_jobs_file ON file_processing_jobs(file_object_id);
CREATE INDEX idx_file_processing_jobs_status ON file_processing_jobs(status);
```

### file_tags & file_object_tags
File organization via tagging.

```sql
CREATE TABLE file_tags (
  id UUID PRIMARY KEY,
  account_id UUID NOT NULL REFERENCES accounts(id),
  name VARCHAR(100) NOT NULL,
  color VARCHAR(7),  -- Hex color
  description TEXT,
  files_count INTEGER DEFAULT 0
);

CREATE TABLE file_object_tags (
  id UUID PRIMARY KEY,
  file_object_id UUID NOT NULL REFERENCES file_objects(id) ON DELETE CASCADE,
  file_tag_id UUID NOT NULL REFERENCES file_tags(id) ON DELETE CASCADE,
  account_id UUID NOT NULL REFERENCES accounts(id)
);

CREATE UNIQUE INDEX idx_file_object_tags_unique ON file_object_tags(file_object_id, file_tag_id);
```

## Storage Providers

### Provider Interface

All storage providers implement the `StorageProviders::Base` interface:

```ruby
module StorageProviders
  class Base
    # Lifecycle methods
    def initialize_storage
    def test_connection
    def health_check

    # File operations
    def upload_file(file_object, file_data, options = {})
    def read_file(file_object)
    def stream_file(file_object, &block)
    def delete_file(file_object)
    def copy_file(source_key, destination_key)
    def move_file(source_key, destination_key)
    def file_exists?(file_object)

    # URLs and metadata
    def file_url(file_object)
    def download_url(file_object, expires_in: 1.hour)
    def signed_url(file_object, expires_in: 1.hour, disposition: 'inline')
    def file_metadata(file_object)

    # Batch operations
    def list_files(prefix: nil, options: {})
    def batch_delete(file_objects)
  end
end
```

### Local Storage

Stores files on local filesystem with configurable root path.

**Configuration**:
```json
{
  "root_path": "/path/to/storage"
}
```

**Features**:
- Automatic directory structure creation
- File organization by category
- Checksums (MD5, SHA256)
- Disk usage statistics

### AWS S3 Storage

Cloud storage with multipart uploads, CDN support, and signed URLs.

**Configuration**:
```json
{
  "bucket": "my-bucket",
  "region": "us-east-1",
  "access_key_id": "encrypted:...",
  "secret_access_key": "encrypted:...",
  "endpoint": "https://s3.amazonaws.com",  // Optional for S3-compatible services
  "storage_class": "STANDARD",
  "encryption": "AES256",
  "acl": "private",
  "cdn_domain": "cdn.example.com"  // Optional
}
```

**Features**:
- Multipart upload for large files (>100MB)
- Server-side encryption
- Presigned URLs for direct browser uploads
- CDN integration
- Lifecycle policies
- Storage class configuration

### Google Cloud Storage

Google Cloud Platform storage with similar capabilities to S3.

**Configuration**:
```json
{
  "bucket": "my-bucket",
  "project_id": "my-project",
  "credentials": "encrypted:..."
}
```

### Azure Blob Storage

Microsoft Azure cloud storage.

**Configuration**:
```json
{
  "container": "my-container",
  "account_name": "myaccount",
  "access_key": "encrypted:..."
}
```

## File Storage Service

The `FileStorageService` provides a unified interface for file operations across all storage providers.

### Basic Usage

```ruby
# Initialize service for account
service = FileStorageService.new(account, storage_config: storage)

# Upload file
file_object = service.upload_file(
  uploaded_file,
  filename: 'document.pdf',
  content_type: 'application/pdf',
  category: 'user_upload',
  description: 'User uploaded document',
  visibility: 'private',
  metadata: { source: 'web_upload' },
  processing_tasks: ['thumbnail', 'ocr']
)

# Download file
content = service.download_file(file_object)

# Stream large file
service.stream_file(file_object) do |chunk|
  # Process chunk
end

# Delete file (soft delete)
service.delete_file(file_object, permanent: false)

# Permanently delete
service.delete_file(file_object, permanent: true)

# Create version
new_version = service.create_version(
  file_object,
  new_file_data,
  created_by_user: current_user,
  change_description: 'Updated content'
)

# Create share
share = service.create_share(
  file_object,
  created_by_id: current_user.id,
  expires_at: 7.days.from_now,
  max_downloads: 10,
  password: 'secret',
  notify_on_access: true
)

# Get share URL
url = service.share_url(share)

# Add tags
tags = service.add_tags(file_object, ['important', 'project-alpha'])

# Get file URL
url = service.file_url(file_object, signed: true, expires_in: 1.hour)
```

## API Endpoints

### Files Controller

**Base Path**: `/api/v1/files`

#### List Files
```http
GET /api/v1/files

Query Parameters:
  - category: string (filter by category)
  - visibility: string (filter by visibility)
  - storage_id: uuid (filter by storage)
  - tags: string (comma-separated tag names)
  - search: string (filename search)
  - include_deleted: boolean
  - page: integer
  - per_page: integer (max 100)

Response:
{
  "success": true,
  "data": {
    "files": [...],
    "pagination": {
      "current_page": 1,
      "per_page": 25,
      "total_pages": 5,
      "total_count": 120
    }
  }
}
```

#### Show File
```http
GET /api/v1/files/:id

Response:
{
  "success": true,
  "data": {
    "file": {
      "id": "uuid",
      "filename": "document.pdf",
      "urls": {
        "view": "https://...",
        "download": "https://...",
        "signed": "https://..."
      },
      "versions": [...],
      "tags": [...]
    }
  }
}
```

#### Upload File
```http
POST /api/v1/files/upload

Form Data:
  - file: (required) file upload
  - filename: string
  - content_type: string
  - category: string
  - description: string
  - visibility: string (private, public, shared)
  - metadata: json
  - tags: array or comma-separated
  - processing_tasks: array
  - storage_id: uuid (optional, uses default if not provided)

Response:
{
  "success": true,
  "data": {
    "file": {...},
    "url": "https://..."
  }
}
```

#### Download File
```http
GET /api/v1/files/:id/download

Query Parameters:
  - stream: boolean (use streaming for large files)
  - disposition: string (attachment or inline)

Response: Binary file data
```

#### Update File Metadata
```http
PATCH /api/v1/files/:id

Body:
{
  "filename": "new-name.pdf",
  "description": "Updated description",
  "visibility": "public",
  "category": "processed",
  "metadata": {...}
}
```

#### Delete File
```http
DELETE /api/v1/files/:id

Query Parameters:
  - permanent: boolean (default: false)

Response:
{
  "success": true,
  "data": {
    "deleted": true,
    "permanent": false,
    "message": "File moved to trash"
  }
}
```

#### Additional Endpoints

```http
POST /api/v1/files/:id/restore
POST /api/v1/files/:id/versions
POST /api/v1/files/:id/tags
DELETE /api/v1/files/:id/tags
POST /api/v1/files/:id/share
GET /api/v1/files/stats
```

### Storage Providers Controller

**Base Path**: `/api/v1/storage`

```http
GET /api/v1/storage                      # List all storage configurations
POST /api/v1/storage                     # Create storage configuration
GET /api/v1/storage/:id                  # Show storage details
PATCH /api/v1/storage/:id                # Update storage configuration
DELETE /api/v1/storage/:id               # Delete storage configuration
POST /api/v1/storage/:id/test            # Test connection
GET /api/v1/storage/:id/health           # Health check
POST /api/v1/storage/:id/set_default     # Set as default storage
POST /api/v1/storage/:id/initialize      # Initialize storage backend
GET /api/v1/storage/:id/files            # List files in provider
GET /api/v1/storage/supported            # List supported providers
GET /api/v1/storage/stats                # Aggregate statistics
```

## Workflow Integration

### File Upload Node

Uploads files to storage from workflow context.

**Configuration**:
```json
{
  "node_type": "file_upload",
  "configuration": {
    "file_data_variable": "generated_image",
    "filename": "output.png",
    "content_type": "image/png",
    "category": "workflow_output",
    "description": "AI generated image",
    "visibility": "private",
    "storage_id": "uuid",
    "output_variable": "file_id",
    "url_variable": "file_url",
    "processing_tasks": ["thumbnail"]
  }
}
```

**Supported File Sources**:
- Direct file data in configuration
- Previous node output
- Variable reference
- URL download
- Base64 encoded data

**Output**:
```json
{
  "output": {
    "file_id": "uuid",
    "filename": "output.png",
    "file_size": 1024000,
    "content_type": "image/png",
    "storage_key": "workflow_output/20250119/abc123_output.png",
    "url": "https://..."
  }
}
```

### File Download Node

Downloads files from storage for use in subsequent nodes.

**Configuration**:
```json
{
  "node_type": "file_download",
  "configuration": {
    "file_id": "uuid",
    "output_format": "metadata",  // metadata, content, base64, url
    "output_variable": "file_content",
    "base64_variable": "file_base64",
    "url_variable": "file_url",
    "signed_url": true,
    "url_expires_in": 3600
  }
}
```

**Output Formats**:
- `metadata`: File info with URLs
- `content`: Raw file content
- `base64`: Base64 encoded content
- `url`: File URL only

### File Transform Node

Transforms images (resize, convert, optimize).

**Configuration**:
```json
{
  "node_type": "file_transform",
  "configuration": {
    "file_id": "uuid",
    "operation": "resize",  // resize, thumbnail, convert, compress, etc.
    "params": {
      "width": 800,
      "height": 600,
      "maintain_aspect": true,
      "quality": 85
    },
    "save_output": true,
    "output_category": "processed",
    "output_variable": "transformed_file_id"
  }
}
```

**Supported Operations**:
- `resize`: Resize image with optional aspect ratio
- `thumbnail`: Create thumbnail with smart cropping
- `convert`: Change image format
- `compress`: Reduce file size
- `watermark`: Add text watermark
- `crop`: Crop to specific dimensions
- `rotate`: Rotate image
- `grayscale`: Convert to grayscale
- `blur`: Apply blur effect

## Permissions

### Resource Permissions
- `files.read` - View files
- `files.create` - Upload files
- `files.update` - Update file metadata
- `files.delete` - Delete files
- `files.download` - Download files
- `files.share` - Share files externally
- `files.version` - Manage file versions
- `files.tag` - Tag and organize files
- `storage.read` - View storage configurations
- `storage.create` - Create storage configurations
- `storage.update` - Update storage configurations
- `storage.delete` - Delete storage configurations
- `storage.test` - Test storage connections

### Admin Permissions
- `admin.files.read` - View all files across accounts
- `admin.files.manage` - Manage any file
- `admin.files.delete` - Delete any file
- `admin.files.recover` - Recover deleted files
- `admin.files.audit` - View file access audit logs
- `admin.storage.read` - View all storage configurations
- `admin.storage.create` - Create system storage configurations
- `admin.storage.edit` - Edit any storage configuration
- `admin.storage.delete` - Delete storage configurations
- `admin.storage.manage_quota` - Manage storage quotas
- `admin.storage.health` - Monitor storage health

## Security Features

### Encryption
- Sensitive storage credentials encrypted using `AiCredentialEncryptionService`
- Credentials marked with `encrypted:` prefix in configuration
- Automatic decryption on provider instantiation

### Access Control
- Permission-based access to all file operations
- Account-level isolation
- File visibility settings (private, public, shared)
- Share token authentication
- Password-protected shares
- Download limits

### Audit Logging
- All file operations logged via `Auditable` concern
- Access logs for shared files
- Detailed event tracking

## Dependencies

```ruby
# Gemfile additions
gem "aws-sdk-s3", "~> 1.156"           # AWS S3 storage
gem "google-cloud-storage", "~> 1.51"  # Google Cloud Storage
gem "azure-storage-blob", "~> 2.0"     # Azure Blob Storage
gem "mini_magick", "~> 5.0"            # Image transformations
gem "marcel", "~> 1.0"                 # MIME type detection
gem "sys-filesystem", "~> 1.5"         # Disk statistics
```

## Usage Examples

### Creating Default Storage

```ruby
# Create local storage for development
storage = FileStorage.create!(
  account: account,
  name: 'Local Storage',
  provider_type: 'local',
  configuration: {
    'root_path' => Rails.root.join('storage', 'files').to_s
  },
  is_default: true,
  quota_enabled: true,
  quota_bytes: 10.gigabytes
)

# Initialize storage backend
storage.storage_provider.initialize_storage
```

### Uploading from Web Form

```ruby
# Controller
def upload
  service = FileStorageService.new(current_account)

  file_object = service.upload_file(
    params[:file],
    filename: params[:file].original_filename,
    content_type: params[:file].content_type,
    category: 'user_upload',
    uploaded_by_id: current_user.id,
    processing_tasks: ['thumbnail', 'virus_scan']
  )

  render_success(data: { file: file_object.file_summary })
end
```

### Sharing a File

```ruby
# Create share with password and expiration
service = FileStorageService.new(account, storage_config: file.file_storage)

share = service.create_share(
  file_object,
  created_by_id: current_user.id,
  expires_at: 7.days.from_now,
  max_downloads: 10,
  password: 'secret123',
  notify_on_access: true
)

share_url = service.share_url(share)
# => "https://app.powernode.com/shares/abc123xyz"
```

### Version Management

```ruby
# Create new version
service = FileStorageService.new(account, storage_config: file.file_storage)

new_version = service.create_version(
  file_object,
  updated_file_data,
  created_by_user: current_user,
  change_description: 'Updated with latest changes'
)

# Rollback to previous version
restored = service.rollback_version(
  file_object,
  3,  # version number
  created_by_user: current_user
)
```

## Migration Guide

### Running the Migration

```bash
cd server
rails db:migrate
```

### Installing Dependencies

```bash
cd server
bundle install
```

### Initializing Storage

```ruby
# In Rails console or seed file
account = Account.first
storage = FileStorage.create!(
  account: account,
  name: 'Default Storage',
  provider_type: 'local',
  configuration: { 'root_path' => Rails.root.join('storage', 'files').to_s },
  is_default: true
)

storage.storage_provider.initialize_storage
```

## Testing

### RSpec Examples

```ruby
require 'rails_helper'

RSpec.describe FileStorageService do
  let(:account) { create(:account) }
  let(:storage) { create(:file_storage, :local, account: account) }
  let(:service) { described_class.new(account, storage_config: storage) }

  describe '#upload_file' do
    it 'uploads file successfully' do
      file = fixture_file_upload('test.pdf', 'application/pdf')

      file_object = service.upload_file(
        file,
        filename: 'test.pdf',
        content_type: 'application/pdf'
      )

      expect(file_object).to be_persisted
      expect(file_object.filename).to eq('test.pdf')
    end
  end
end
```

## Troubleshooting

### Common Issues

**Storage Provider Not Found**:
- Ensure provider type is supported (`local`, `s3`, `gcs`, `azure`)
- Check StorageProviderFactory.supported_providers

**Quota Exceeded**:
- Check storage.quota_bytes and storage.total_size_bytes
- Increase quota or clean up old files

**Permission Denied**:
- Verify user has required permissions (`files.create`, etc.)
- Check file visibility settings

**Connection Test Failed**:
- Verify storage configuration
- Check credentials encryption
- Test network connectivity

## Future Enhancements

- Additional storage providers (FTP, WebDAV, Dropbox, etc.)
- Advanced file processing (video transcoding, document conversion)
- Content delivery network (CDN) integration
- File deduplication
- Automated cleanup and archival
- Advanced search and filtering
- Thumbnail caching

## References

- **Database Schema**: `/server/db/migrate/20251019180000_create_file_management_system.rb`
- **Models**: `/server/app/models/file_*.rb`
- **Services**: `/server/app/services/storage_providers/*.rb`, `/server/app/services/file_storage_service.rb`
- **Controllers**: `/server/app/controllers/api/v1/files_controller.rb`, `/server/app/controllers/api/v1/storage_providers_controller.rb`
- **Workflow Nodes**: `/server/app/services/mcp/node_executors/file_*.rb`
- **Permissions**: `/server/config/permissions.rb` (lines 169-184, 300-311)

---

**Implementation Complete**: ✅ January 19, 2025
