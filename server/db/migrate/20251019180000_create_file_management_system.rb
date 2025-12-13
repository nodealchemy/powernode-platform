# frozen_string_literal: true

class CreateFileManagementSystem < ActiveRecord::Migration[8.0]
  def change
    # Storage Provider Configurations
    create_table :file_storages, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true

      # Provider details
      t.string :name, null: false
      t.string :provider_type, null: false  # local, s3, gcs, azure, ftp, webdav
      t.string :status, null: false, default: 'active'  # active, inactive, maintenance
      t.integer :priority, null: false, default: 100  # Lower = higher priority

      # Configuration (encrypted credentials, endpoints, etc.)
      t.jsonb :configuration, null: false, default: {}
      t.jsonb :capabilities, null: false, default: {}

      # Usage tracking
      t.bigint :files_count, null: false, default: 0
      t.bigint :total_size_bytes, null: false, default: 0
      t.bigint :quota_bytes, null: true  # null = unlimited
      t.boolean :is_default, null: false, default: false

      # Metadata
      t.jsonb :metadata, null: false, default: {}

      # Health monitoring
      t.datetime :last_health_check_at
      t.string :health_status  # healthy, degraded, failed
      t.jsonb :health_details, default: {}

      t.timestamps

      t.index [ :account_id, :name ], unique: true
      t.index [ :account_id, :provider_type ]
      t.index [ :account_id, :status ]
      t.index [ :account_id, :is_default ], where: 'is_default = true'
      t.index :priority
      t.index :health_status
      t.index :configuration, using: :gin
    end

    # Universal File Objects
    create_table :file_objects, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :file_storage, type: :uuid, null: false, foreign_key: true
      t.references :uploaded_by, type: :uuid, null: false, foreign_key: { to_table: :users }

      # File identification
      t.string :filename, null: false
      t.string :storage_key, null: false  # Unique key in storage provider
      t.string :content_type, null: false
      t.bigint :file_size, null: false  # in bytes
      t.string :checksum_md5
      t.string :checksum_sha256

      # File categorization
      t.string :file_type  # image, document, video, audio, archive, other
      t.string :category  # user_upload, workflow_output, ai_generated, temp
      t.string :visibility, null: false, default: 'private'  # private, public, shared

      # Ownership and associations
      t.string :attachable_type  # Polymorphic: AiWorkflowRun, KnowledgeBaseArticle, etc.
      t.uuid :attachable_id

      # Version control
      t.integer :version, null: false, default: 1
      t.boolean :is_latest_version, null: false, default: true
      t.uuid :parent_file_id  # Reference to previous version

      # Access control
      t.jsonb :access_permissions, default: {}
      t.datetime :expires_at  # For temporary files or signed URLs

      # Usage tracking
      t.integer :download_count, null: false, default: 0
      t.datetime :last_accessed_at

      # Processing status
      t.string :processing_status, default: 'pending'  # pending, processing, completed, failed
      t.jsonb :processing_metadata, default: {}

      # Extended metadata
      t.jsonb :metadata, null: false, default: {}
      t.jsonb :exif_data, default: {}  # For images
      t.jsonb :dimensions, default: {}  # width, height, duration for media

      # Soft delete
      t.datetime :deleted_at
      t.references :deleted_by, type: :uuid, foreign_key: { to_table: :users }

      t.timestamps

      # Indexes for performance
      t.index [ :account_id, :filename ]
      t.index [ :account_id, :file_type ]
      t.index [ :account_id, :category ]
      t.index [ :account_id, :visibility ]
      t.index [ :account_id, :is_latest_version ]
      t.index [ :account_id, :created_at ]
      t.index [ :file_storage_id, :storage_key ], unique: true
      t.index [ :attachable_type, :attachable_id ]
      t.index [ :parent_file_id ]
      t.index [ :processing_status ]
      t.index [ :deleted_at ]
      t.index [ :expires_at ], where: "expires_at IS NOT NULL"
      t.index :checksum_sha256
      t.index :metadata, using: :gin
    end

    # File Version History
    create_table :file_versions, id: :uuid do |t|
      t.references :file_object, type: :uuid, null: false, foreign_key: true
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :created_by, type: :uuid, null: false, foreign_key: { to_table: :users }

      # Version details
      t.integer :version_number, null: false
      t.string :storage_key, null: false  # Storage location for this version
      t.bigint :file_size, null: false
      t.string :checksum_sha256

      # Change tracking
      t.string :change_description
      t.jsonb :change_metadata, default: {}

      # Version metadata
      t.jsonb :metadata, default: {}

      # Soft delete (for version cleanup)
      t.datetime :deleted_at

      t.timestamps

      t.index [ :file_object_id, :version_number ], unique: true
      t.index [ :account_id, :created_at ]
      t.index [ :deleted_at ]
      t.index :storage_key
    end

    # File Shares (for external sharing)
    create_table :file_shares, id: :uuid do |t|
      t.references :file_object, type: :uuid, null: false, foreign_key: true
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :created_by, type: :uuid, null: false, foreign_key: { to_table: :users }

      # Share configuration
      t.string :share_token, null: false
      t.string :share_type, null: false  # public_link, email, user
      t.string :access_level, null: false, default: 'view'  # view, download, edit

      # Share recipients (for email/user shares)
      t.jsonb :recipients, default: []

      # Access control
      t.string :password_digest  # For password-protected shares
      t.integer :max_downloads
      t.integer :download_count, null: false, default: 0
      t.datetime :expires_at

      # Tracking
      t.datetime :last_accessed_at
      t.jsonb :access_log, default: []

      # Status
      t.string :status, null: false, default: 'active'  # active, expired, revoked

      # Metadata
      t.jsonb :metadata, default: {}

      t.timestamps

      t.index [ :share_token ], unique: true
      t.index [ :status ]
      t.index [ :expires_at ], where: "expires_at IS NOT NULL"
      t.index [ :created_at ]
    end

    # File Processing Jobs (for async operations)
    create_table :file_processing_jobs, id: :uuid do |t|
      t.references :file_object, type: :uuid, null: false, foreign_key: true
      t.references :account, type: :uuid, null: false, foreign_key: true

      # Job details
      t.string :job_type, null: false  # thumbnail, resize, convert, scan, ocr, metadata_extract
      t.string :status, null: false, default: 'pending'  # pending, processing, completed, failed
      t.integer :priority, null: false, default: 50

      # Configuration
      t.jsonb :job_parameters, default: {}

      # Results
      t.jsonb :result_data, default: {}
      t.string :output_storage_key  # For operations that generate new files

      # Error handling
      t.jsonb :error_details, default: {}
      t.integer :retry_count, null: false, default: 0
      t.integer :max_retries, null: false, default: 3

      # Timing
      t.datetime :started_at
      t.datetime :completed_at
      t.integer :duration_ms

      # Metadata
      t.jsonb :metadata, default: {}

      t.timestamps

      t.index [ :job_type ]
      t.index [ :status ]
      t.index [ :priority ]
      t.index [ :created_at ]
    end

    # File Tags (for organization)
    create_table :file_tags, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.string :name, null: false
      t.string :color
      t.text :description
      t.integer :files_count, null: false, default: 0

      t.timestamps

      t.index [ :account_id, :name ], unique: true
    end

    # File Object Tags (join table)
    create_table :file_object_tags, id: :uuid do |t|
      t.references :file_object, type: :uuid, null: false, foreign_key: true
      t.references :file_tag, type: :uuid, null: false, foreign_key: true
      t.references :account, type: :uuid, null: false, foreign_key: true

      t.timestamps

      t.index [ :file_object_id, :file_tag_id ], unique: true
    end

    # Constraints
    add_check_constraint :file_storages, "provider_type IN ('local', 's3', 'gcs', 'azure', 'ftp', 'webdav', 'custom')", name: 'file_storages_provider_type_check'
    add_check_constraint :file_storages, "status IN ('active', 'inactive', 'maintenance', 'failed')", name: 'file_storages_status_check'

    add_check_constraint :file_objects, "visibility IN ('private', 'public', 'shared', 'internal')", name: 'file_objects_visibility_check'
    add_check_constraint :file_objects, "file_type IN ('image', 'document', 'video', 'audio', 'archive', 'code', 'data', 'other')", name: 'file_objects_file_type_check'
    add_check_constraint :file_objects, "processing_status IN ('pending', 'processing', 'completed', 'failed')", name: 'file_objects_processing_status_check'
    add_check_constraint :file_objects, "category IN ('user_upload', 'workflow_output', 'ai_generated', 'temp', 'system', 'import')", name: 'file_objects_category_check'

    add_check_constraint :file_shares, "share_type IN ('public_link', 'email', 'user', 'api')", name: 'file_shares_share_type_check'
    add_check_constraint :file_shares, "access_level IN ('view', 'download', 'edit', 'admin')", name: 'file_shares_access_level_check'
    add_check_constraint :file_shares, "status IN ('active', 'expired', 'revoked', 'pending')", name: 'file_shares_status_check'

    add_check_constraint :file_processing_jobs, "job_type IN ('thumbnail', 'resize', 'convert', 'scan', 'ocr', 'metadata_extract', 'compress', 'watermark', 'transform')", name: 'file_processing_jobs_job_type_check'
    add_check_constraint :file_processing_jobs, "status IN ('pending', 'processing', 'completed', 'failed', 'cancelled')", name: 'file_processing_jobs_status_check'
  end
end
