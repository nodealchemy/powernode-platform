# frozen_string_literal: true

# Creates all GDPR compliance tables for data privacy management
class CreateGdprComplianceTables < ActiveRecord::Migration[8.0]
  def change
    # User Consents - Track all user consent decisions
    create_table :user_consents, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.string :consent_type, null: false # marketing, analytics, cookies, data_sharing, etc.
      t.boolean :granted, null: false, default: false
      t.string :version # Version of consent text user agreed to
      t.text :consent_text # Actual text shown to user
      t.string :collection_method, null: false # explicit, implicit, opt_out
      t.string :ip_address
      t.string :user_agent
      t.datetime :granted_at
      t.datetime :withdrawn_at
      t.datetime :expires_at
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :user_consents, [ :user_id, :consent_type ]
    add_index :user_consents, [ :account_id, :consent_type ]
    add_index :user_consents, :consent_type
    add_index :user_consents, :granted
    add_index :user_consents, :expires_at

    # Data Export Requests - GDPR Article 20 data portability
    create_table :data_export_requests, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :requested_by, type: :uuid, foreign_key: { to_table: :users }
      t.string :status, null: false, default: 'pending' # pending, processing, completed, failed, expired
      t.string :format, null: false, default: 'json' # json, csv, zip
      t.string :export_type, default: 'full' # full, partial
      t.jsonb :include_data_types, default: [] # profile, activity, payments, files, etc.
      t.jsonb :exclude_data_types, default: []
      t.string :file_path # Path to generated export file
      t.integer :file_size_bytes
      t.string :download_token # Secure token for download
      t.datetime :download_token_expires_at
      t.datetime :processing_started_at
      t.datetime :completed_at
      t.datetime :downloaded_at
      t.datetime :expires_at # Export file expiration
      t.text :error_message
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :data_export_requests, :status
    add_index :data_export_requests, :download_token, unique: true, where: 'download_token IS NOT NULL'
    add_index :data_export_requests, :expires_at

    # Data Deletion Requests - GDPR Article 17 right to erasure
    create_table :data_deletion_requests, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :requested_by, type: :uuid, foreign_key: { to_table: :users }
      t.references :processed_by, type: :uuid, foreign_key: { to_table: :users }
      t.string :status, null: false, default: 'pending' # pending, approved, processing, completed, rejected, cancelled
      t.string :deletion_type, null: false, default: 'full' # full, partial, anonymize
      t.jsonb :data_types_to_delete, default: [] # Specific data types to delete
      t.jsonb :data_types_to_retain, default: [] # Legal retention requirements
      t.text :reason # User's reason for deletion
      t.text :rejection_reason
      t.datetime :approved_at
      t.datetime :processing_started_at
      t.datetime :completed_at
      t.datetime :grace_period_ends_at # Time before permanent deletion
      t.boolean :grace_period_extended, default: false
      t.jsonb :deletion_log, default: [] # Log of what was deleted
      t.jsonb :retention_log, default: [] # Log of what was retained and why
      t.text :error_message
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :data_deletion_requests, :status
    add_index :data_deletion_requests, :deletion_type
    add_index :data_deletion_requests, :grace_period_ends_at

    # Data Retention Policies - Configurable retention rules
    create_table :data_retention_policies, id: :uuid do |t|
      t.references :account, type: :uuid, foreign_key: true # null = system default
      t.string :data_type, null: false # audit_logs, user_activity, payment_records, etc.
      t.integer :retention_days, null: false
      t.string :action, null: false, default: 'delete' # delete, anonymize, archive
      t.boolean :active, default: true
      t.string :legal_basis # GDPR article, regulation reference
      t.text :description
      t.datetime :last_enforced_at
      t.integer :records_processed_count, default: 0
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :data_retention_policies, [ :account_id, :data_type ], unique: true
    add_index :data_retention_policies, :data_type
    add_index :data_retention_policies, :active

    # Terms Acceptances - Track ToS/Privacy Policy acceptances
    create_table :terms_acceptances, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.string :document_type, null: false # terms_of_service, privacy_policy, dpa, cookie_policy
      t.string :document_version, null: false
      t.string :document_hash # SHA256 hash of document content
      t.string :ip_address
      t.string :user_agent
      t.datetime :accepted_at, null: false
      t.datetime :superseded_at # When newer version was accepted
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :terms_acceptances, [ :user_id, :document_type ]
    add_index :terms_acceptances, [ :user_id, :document_type, :document_version ], unique: true
    add_index :terms_acceptances, :document_type
    add_index :terms_acceptances, :document_version

    # Account Terminations - Manage account closure with grace period
    create_table :account_terminations, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :requested_by, type: :uuid, foreign_key: { to_table: :users }
      t.references :cancelled_by, type: :uuid, foreign_key: { to_table: :users }
      t.references :processed_by, type: :uuid, foreign_key: { to_table: :users }
      t.string :status, null: false, default: 'pending' # pending, grace_period, processing, completed, cancelled
      t.text :reason
      t.text :cancellation_reason
      t.datetime :requested_at, null: false
      t.datetime :grace_period_ends_at, null: false # Default 30 days
      t.datetime :cancelled_at
      t.datetime :processing_started_at
      t.datetime :completed_at
      t.boolean :data_export_requested, default: false
      t.references :data_export_request, type: :uuid, foreign_key: true
      t.boolean :feedback_submitted, default: false
      t.text :feedback
      t.jsonb :termination_log, default: []
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :account_terminations, :status
    add_index :account_terminations, :grace_period_ends_at

    # Cookie Consents - Separate tracking for cookie preferences
    create_table :cookie_consents, id: :uuid do |t|
      t.references :user, type: :uuid, foreign_key: true, index: false # Can be null for anonymous - custom index below
      t.string :visitor_id # For anonymous tracking
      t.boolean :necessary, null: false, default: true # Always true - can't be disabled
      t.boolean :functional, default: false
      t.boolean :analytics, default: false
      t.boolean :marketing, default: false
      t.string :ip_address
      t.string :user_agent
      t.datetime :consented_at, null: false
      t.datetime :updated_at_user
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :cookie_consents, :visitor_id, unique: true, where: 'visitor_id IS NOT NULL'
    add_index :cookie_consents, [ :user_id ], unique: true, where: 'user_id IS NOT NULL'
  end
end
