# frozen_string_literal: true

class PlatformSystemBaseline < ActiveRecord::Migration[8.1]
  def change
  create_table "account_git_webhook_configs", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "branch_filter"
    t.string "branch_filter_type", default: "none"
    t.string "content_type", default: "application/json", null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.jsonb "custom_headers", default: {}, null: false
    t.text "description"
    t.jsonb "event_types", default: [], null: false
    t.integer "failure_count", default: 0, null: false
    t.boolean "is_active", default: true, null: false
    t.datetime "last_delivery_at"
    t.string "name", null: false
    t.string "retry_backoff", default: "exponential", null: false
    t.integer "retry_limit", default: 3, null: false
    t.string "secret_key", null: false
    t.string "signature_secret"
    t.string "status", default: "active", null: false
    t.integer "success_count", default: 0, null: false
    t.integer "timeout_seconds", default: 30, null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["account_id", "status"]
    t.index ["account_id"]
    t.index ["created_by_id"]
    t.check_constraint "branch_filter_type::text = ANY (ARRAY['none'::character varying::text, 'exact'::character varying::text, 'wildcard'::character varying::text, 'regex'::character varying::text])", name: "account_git_webhook_configs_branch_filter_type_check"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'inactive'::character varying::text])", name: "account_git_webhook_configs_status_check"
  end

  create_table "admin_settings", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "category", limit: 100
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "is_encrypted", default: false
    t.boolean "is_public", default: false
    t.string "key", limit: 255, null: false
    t.string "setting_type", limit: 50, default: "string"
    t.integer "sort_order", default: 0
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["category"]
    t.index ["is_public"]
    t.index ["key"], unique: true
    t.index ["setting_type"]
    t.index ["sort_order"]
    t.check_constraint "setting_type::text = ANY (ARRAY['string'::character varying::text, 'text'::character varying::text, 'integer'::character varying::text, 'boolean'::character varying::text, 'json'::character varying::text, 'array'::character varying::text])", name: "valid_admin_setting_type"
  end

  create_table "audit_logs", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "action", limit: 100, null: false
    t.datetime "chain_verified_at"
    t.datetime "created_at", null: false
    t.string "integrity_hash"
    t.string "ip_address", limit: 45
    t.jsonb "metadata", default: {}
    t.jsonb "new_values", default: {}
    t.jsonb "old_values", default: {}
    t.string "previous_hash"
    t.string "request_id", limit: 50
    t.string "resource_id", limit: 36
    t.string "resource_type", limit: 100, null: false
    t.string "risk_level", default: "low", null: false
    t.bigint "sequence_number"
    t.string "severity", default: "medium", null: false
    t.string "source", limit: 20, default: "web", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent", limit: 1000
    t.uuid "user_id"
    t.index ["account_id", "created_at"]
    t.index ["account_id"]
    t.index ["action"]
    t.index ["chain_verified_at"]
    t.index ["created_at"]
    t.index ["integrity_hash"], name: "index_audit_logs_on_integrity_hash", unique: true, where: "(integrity_hash IS NOT NULL)"
    t.index ["request_id"]
    t.index ["resource_type", "resource_id"]
    t.index ["risk_level"]
    t.index ["sequence_number"], name: "index_audit_logs_on_sequence_number", unique: true, where: "(sequence_number IS NOT NULL)"
    t.index ["severity"]
    t.index ["user_id"]
  end

  create_table "background_jobs", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.jsonb "arguments", default: {}
    t.integer "attempts", default: 0
    t.text "backtrace"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "failed_at"
    t.datetime "finished_at"
    t.string "job_id", null: false
    t.string "job_type", null: false
    t.integer "max_attempts", default: 25
    t.integer "priority", default: 0
    t.datetime "scheduled_at"
    t.datetime "started_at"
    t.string "status", default: "pending"
    t.datetime "updated_at", null: false
    t.index ["created_at"]
    t.index ["job_id"], unique: true
    t.index ["job_type", "status"]
    t.index ["job_type"]
    t.index ["scheduled_at"]
    t.index ["status"]
    t.check_constraint "attempts >= 0 AND max_attempts > 0", name: "valid_job_attempts"
    t.check_constraint "priority >= 0", name: "valid_job_priority"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'processing'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'cancelled'::character varying::text, 'retrying'::character varying::text])", name: "valid_job_status"
  end

  create_table "circuit_breaker_events", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "circuit_breaker_id", null: false
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.text "error_message"
    t.string "event_type", null: false
    t.integer "failure_count"
    t.string "new_state"
    t.string "old_state"
    t.datetime "updated_at", null: false
    t.index ["circuit_breaker_id", "created_at"]
    t.index ["circuit_breaker_id"]
    t.index ["event_type"]
  end

  create_table "circuit_breakers", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.jsonb "configuration", default: {}
    t.datetime "created_at", null: false
    t.integer "failure_count", default: 0
    t.integer "failure_threshold", default: 5, null: false
    t.datetime "half_opened_at"
    t.datetime "last_failure_at"
    t.datetime "last_success_at"
    t.jsonb "metrics", default: {}
    t.string "name", null: false
    t.datetime "opened_at"
    t.string "provider"
    t.integer "reset_timeout_seconds", default: 60
    t.string "service", null: false
    t.string "state", default: "closed", null: false
    t.integer "success_count", default: 0
    t.integer "success_threshold", default: 2, null: false
    t.integer "timeout_seconds", default: 30
    t.datetime "updated_at", null: false
    t.index ["name", "service"], unique: true
    t.index ["service", "state"]
    t.index ["state"]
  end

  create_table "data_retention_policies", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.string "action", default: "delete", null: false
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.string "data_type", null: false
    t.text "description"
    t.datetime "last_enforced_at"
    t.string "legal_basis"
    t.jsonb "metadata", default: {}
    t.integer "records_processed_count", default: 0
    t.integer "retention_days", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "data_type"], unique: true
    t.index ["account_id"]
    t.index ["active"]
    t.index ["data_type"]
  end

  create_table "database_backups", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "backup_type", limit: 50, null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.uuid "created_by_id", null: false
    t.text "description"
    t.integer "duration_seconds"
    t.text "error_message"
    t.string "file_path", limit: 1000
    t.integer "file_size_bytes"
    t.jsonb "metadata", default: {}
    t.datetime "started_at", null: false
    t.string "status", limit: 50, default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["backup_type"]
    t.index ["created_by_id"]
    t.index ["started_at"]
    t.index ["status"]
    t.check_constraint "backup_type::text = ANY (ARRAY['full'::character varying::text, 'incremental'::character varying::text, 'manual'::character varying::text])", name: "valid_backup_type"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'running'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text])", name: "valid_backup_status"
  end

  create_table "database_restores", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.uuid "database_backup_id", null: false
    t.text "description"
    t.integer "duration_seconds"
    t.text "error_message"
    t.uuid "initiated_by_id", null: false
    t.jsonb "metadata", default: {}
    t.datetime "started_at", null: false
    t.string "status", limit: 50, default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["database_backup_id"]
    t.index ["initiated_by_id"]
    t.index ["started_at"]
    t.index ["status"]
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'running'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text])", name: "valid_restore_status"
  end

  create_table "email_deliveries", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.text "body_html"
    t.text "body_text"
    t.string "bounce_reason"
    t.datetime "bounced_at"
    t.datetime "clicked_at"
    t.datetime "created_at", null: false
    t.datetime "delivered_at"
    t.string "email_type", null: false
    t.text "error_message"
    t.string "external_id"
    t.jsonb "metadata", default: {}
    t.datetime "opened_at"
    t.string "recipient_email", null: false
    t.integer "retry_count", default: 0
    t.string "sender_email"
    t.datetime "sent_at"
    t.string "status", default: "pending"
    t.string "subject", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id"
    t.index ["email_type"]
    t.index ["external_id"], name: "idx_email_deliveries_on_external_id_unique", unique: true, where: "(external_id IS NOT NULL)"
    t.index ["recipient_email"]
    t.index ["sent_at"]
    t.index ["status"]
    t.index ["user_id"]
    t.check_constraint "email_type::text = ANY (ARRAY['welcome'::character varying::text, 'verification'::character varying::text, 'password_reset'::character varying::text, 'invitation'::character varying::text, 'notification'::character varying::text, 'marketing'::character varying::text, 'transactional'::character varying::text])", name: "valid_email_type"
    t.check_constraint "retry_count >= 0", name: "valid_email_retry_count"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'sent'::character varying::text, 'delivered'::character varying::text, 'bounced'::character varying::text, 'failed'::character varying::text, 'opened'::character varying::text, 'clicked'::character varying::text])", name: "valid_email_status"
  end

  create_table "file_object_tags", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.uuid "file_object_id", null: false
    t.uuid "file_tag_id", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"]
    t.index ["file_object_id", "file_tag_id"], unique: true
    t.index ["file_object_id"]
    t.index ["file_tag_id"]
  end

  create_table "file_objects", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.jsonb "access_permissions", default: {}
    t.uuid "account_id", null: false
    t.uuid "attachable_id"
    t.string "attachable_type"
    t.string "category"
    t.string "checksum_md5"
    t.string "checksum_sha256"
    t.string "content_type", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.uuid "deleted_by_id"
    t.jsonb "dimensions", default: {}
    t.integer "download_count", default: 0, null: false
    t.jsonb "exif_data", default: {}
    t.datetime "expires_at"
    t.bigint "file_size", null: false
    t.uuid "file_storage_id", null: false
    t.string "file_type"
    t.string "filename", null: false
    t.boolean "is_latest_version", default: true, null: false
    t.datetime "last_accessed_at"
    t.jsonb "metadata", default: {}, null: false
    t.uuid "parent_file_id"
    t.jsonb "processing_metadata", default: {}
    t.string "processing_status", default: "pending"
    t.string "storage_key", null: false
    t.datetime "updated_at", null: false
    t.uuid "uploaded_by_id", null: false
    t.integer "version", default: 1, null: false
    t.string "visibility", default: "private", null: false
    t.index ["account_id", "category"]
    t.index ["account_id", "created_at"]
    t.index ["account_id", "file_type"]
    t.index ["account_id", "filename"]
    t.index ["account_id", "is_latest_version"]
    t.index ["account_id", "visibility"]
    t.index ["account_id"]
    t.index ["attachable_type", "attachable_id"]
    t.index ["checksum_sha256"]
    t.index ["deleted_at"]
    t.index ["deleted_by_id"]
    t.index ["expires_at"], name: "index_file_objects_on_expires_at", where: "(expires_at IS NOT NULL)"
    t.index ["file_storage_id", "storage_key"], unique: true
    t.index ["file_storage_id"]
    t.index ["metadata"], name: "index_file_objects_on_metadata", using: :gin
    t.index ["parent_file_id"]
    t.index ["processing_status"]
    t.index ["uploaded_by_id"]
    t.check_constraint "category IS NULL OR (category::text = ANY (ARRAY['user_upload'::character varying::text, 'workflow_output'::character varying::text, 'ai_generated'::character varying::text, 'temp'::character varying::text, 'system'::character varying::text, 'import'::character varying::text, 'page_content'::character varying::text, 'sbom_export'::character varying::text, 'attestation_proof'::character varying::text, 'supply_chain_scan_report'::character varying::text, 'vendor_compliance'::character varying::text, 'vendor_assessment'::character varying::text, 'vendor_certificate'::character varying::text, 'disk_image'::character varying::text]))", name: "file_objects_category_check"
    t.check_constraint "file_type::text = ANY (ARRAY['image'::character varying::text, 'document'::character varying::text, 'video'::character varying::text, 'audio'::character varying::text, 'archive'::character varying::text, 'code'::character varying::text, 'data'::character varying::text, 'other'::character varying::text])", name: "file_objects_file_type_check"
    t.check_constraint "processing_status::text = ANY (ARRAY['pending'::character varying::text, 'processing'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text])", name: "file_objects_processing_status_check"
    t.check_constraint "visibility::text = ANY (ARRAY['private'::character varying::text, 'public'::character varying::text, 'shared'::character varying::text, 'internal'::character varying::text])", name: "file_objects_visibility_check"
  end

  create_table "file_processing_jobs", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.jsonb "error_details", default: {}
    t.uuid "file_object_id", null: false
    t.jsonb "job_parameters", default: {}
    t.string "job_type", null: false
    t.integer "max_retries", default: 3, null: false
    t.jsonb "metadata", default: {}
    t.string "output_storage_key"
    t.integer "priority", default: 50, null: false
    t.jsonb "result_data", default: {}
    t.integer "retry_count", default: 0, null: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"]
    t.index ["created_at"]
    t.index ["file_object_id"]
    t.index ["job_type"]
    t.index ["priority"]
    t.index ["status"]
    t.check_constraint "job_type::text = ANY (ARRAY['thumbnail'::character varying::text, 'resize'::character varying::text, 'convert'::character varying::text, 'scan'::character varying::text, 'ocr'::character varying::text, 'metadata_extract'::character varying::text, 'compress'::character varying::text, 'watermark'::character varying::text, 'transform'::character varying::text])", name: "file_processing_jobs_job_type_check"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'processing'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'cancelled'::character varying::text])", name: "file_processing_jobs_status_check"
  end

  create_table "file_shares", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "access_level", default: "view", null: false
    t.jsonb "access_log", default: []
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id", null: false
    t.integer "download_count", default: 0, null: false
    t.datetime "expires_at"
    t.uuid "file_object_id", null: false
    t.datetime "last_accessed_at"
    t.integer "max_downloads"
    t.jsonb "metadata", default: {}
    t.string "password_digest"
    t.jsonb "recipients", default: []
    t.string "share_token", null: false
    t.string "share_type", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"]
    t.index ["created_at"]
    t.index ["created_by_id"]
    t.index ["expires_at"], name: "index_file_shares_on_expires_at", where: "(expires_at IS NOT NULL)"
    t.index ["file_object_id"]
    t.index ["share_token"], unique: true
    t.index ["status"]
    t.check_constraint "access_level::text = ANY (ARRAY['view'::character varying::text, 'download'::character varying::text, 'edit'::character varying::text, 'admin'::character varying::text])", name: "file_shares_access_level_check"
    t.check_constraint "share_type::text = ANY (ARRAY['public_link'::character varying::text, 'email'::character varying::text, 'user'::character varying::text, 'api'::character varying::text])", name: "file_shares_share_type_check"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'expired'::character varying::text, 'revoked'::character varying::text, 'pending'::character varying::text])", name: "file_shares_status_check"
  end

  create_table "file_storages", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.jsonb "capabilities", default: {}, null: false
    t.jsonb "configuration", default: {}, null: false
    t.datetime "created_at", null: false
    t.jsonb "default_mount_options", default: {}, null: false
    t.string "deployment_shape", default: "self_hosted", null: false
    t.string "encryption_mode", default: "none", null: false
    t.bigint "files_count", default: 0, null: false
    t.jsonb "health_details", default: {}
    t.string "health_status"
    t.boolean "is_default"
    t.datetime "last_health_check_at"
    t.jsonb "metadata", default: {}, null: false
    t.string "name", null: false
    t.boolean "node_mount_capable", default: false, null: false
    t.integer "priority", default: 100, null: false
    t.string "provider_type", null: false
    t.bigint "quota_bytes"
    t.boolean "requires_node_credentials", default: false, null: false
    t.string "status", default: "active", null: false
    t.bigint "total_size_bytes", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], unique: true
    t.index ["account_id", "provider_type"]
    t.index ["account_id", "status"]
    t.index ["account_id"]
    t.index ["configuration"], name: "index_file_storages_on_configuration", using: :gin
    t.index ["health_status"]
    t.index ["node_mount_capable"], name: "index_file_storages_node_mount_capable_true", where: "(node_mount_capable = true)"
    t.index ["priority"]
    t.check_constraint "deployment_shape::text = ANY (ARRAY['self_hosted'::character varying::text, 'gateway_proxy'::character varying::text])", name: "file_storages_deployment_shape_check"
    t.check_constraint "encryption_mode::text = ANY (ARRAY['none'::character varying::text, 'fscrypt'::character varying::text, 'luks'::character varying::text, 'client_side_aes'::character varying::text])", name: "file_storages_encryption_mode_check"
    t.check_constraint "provider_type::text = ANY (ARRAY['local'::character varying::text, 's3'::character varying::text, 'gcs'::character varying::text, 'azure'::character varying::text, 'nfs'::character varying::text, 'smb'::character varying::text, 'ftp'::character varying::text, 'webdav'::character varying::text, 'custom'::character varying::text])", name: "file_storages_provider_type_check"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'inactive'::character varying::text, 'maintenance'::character varying::text, 'failed'::character varying::text])", name: "file_storages_status_check"
  end

  create_table "file_tags", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "color"
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "files_count", default: 0, null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], unique: true
    t.index ["account_id"]
  end

  create_table "file_versions", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "change_description"
    t.jsonb "change_metadata", default: {}
    t.string "checksum_sha256"
    t.datetime "created_at", null: false
    t.uuid "created_by_id", null: false
    t.datetime "deleted_at"
    t.uuid "file_object_id", null: false
    t.bigint "file_size", null: false
    t.jsonb "metadata", default: {}
    t.string "storage_key", null: false
    t.datetime "updated_at", null: false
    t.integer "version_number", null: false
    t.index ["account_id", "created_at"]
    t.index ["account_id"]
    t.index ["created_by_id"]
    t.index ["deleted_at"]
    t.index ["file_object_id", "version_number"], unique: true
    t.index ["file_object_id"]
    t.index ["storage_key"]
  end

  create_table "flipper_features", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], unique: true
  end

  create_table "flipper_gates", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "feature_key", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["feature_key", "key", "value"], unique: true
  end

  create_table "notifications", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "action_label"
    t.string "action_url"
    t.string "category", default: "general"
    t.datetime "created_at", null: false
    t.datetime "dismissed_at"
    t.datetime "expires_at"
    t.string "icon"
    t.text "message", null: false
    t.json "metadata", default: {}
    t.string "notification_type", null: false
    t.integer "priority", default: 0
    t.datetime "read_at"
    t.string "severity", default: "info", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["account_id", "created_at"]
    t.index ["account_id"]
    t.index ["category"]
    t.index ["expires_at"]
    t.index ["notification_type"]
    t.index ["priority"]
    t.index ["user_id", "created_at"]
    t.index ["user_id", "read_at"]
    t.index ["user_id"]
  end

  create_table "report_requests", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "completed_at"
    t.string "content_type", limit: 100
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "expires_at"
    t.string "file_path", limit: 1000
    t.integer "file_size"
    t.integer "file_size_bytes"
    t.string "file_url"
    t.string "format", limit: 20, default: "pdf"
    t.string "name", limit: 255
    t.jsonb "parameters", default: {}
    t.string "report_type", limit: 100, null: false
    t.datetime "requested_at", null: false
    t.uuid "requested_by_id", null: false
    t.string "status", limit: 50, default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "report_type"]
    t.index ["account_id"]
    t.index ["expires_at"]
    t.index ["requested_at"]
    t.index ["requested_by_id"]
    t.index ["status"]
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'generating'::character varying::text, 'processing'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'expired'::character varying::text, 'cancelled'::character varying::text])", name: "valid_report_request_status"
  end

  create_table "scheduled_reports", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id", null: false
    t.string "format", limit: 20, default: "pdf", null: false
    t.string "frequency", limit: 50, null: false
    t.boolean "is_active", default: true
    t.datetime "last_run_at"
    t.string "last_status", limit: 50
    t.string "name", limit: 255, null: false
    t.datetime "next_run_at"
    t.jsonb "parameters", default: {}
    t.jsonb "recipients", default: []
    t.string "report_type", limit: 100, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "report_type"]
    t.index ["account_id"]
    t.index ["created_by_id"]
    t.index ["frequency"]
    t.index ["is_active"]
    t.index ["next_run_at"]
    t.check_constraint "frequency::text = ANY (ARRAY['daily'::character varying::text, 'weekly'::character varying::text, 'monthly'::character varying::text, 'quarterly'::character varying::text, 'yearly'::character varying::text])", name: "valid_report_frequency"
  end

  create_table "scheduled_tasks", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "cron_expression", limit: 100
    t.integer "failure_count", default: 0
    t.integer "interval_seconds"
    t.boolean "is_active", default: true
    t.text "last_error_message"
    t.datetime "last_run_at"
    t.string "last_status", limit: 50
    t.string "name", limit: 255, null: false
    t.datetime "next_run_at"
    t.jsonb "parameters", default: {}
    t.integer "success_count", default: 0
    t.string "task_type", limit: 100, null: false
    t.datetime "updated_at", null: false
    t.index ["is_active"]
    t.index ["last_run_at"]
    t.index ["name"], unique: true
    t.index ["next_run_at"]
    t.index ["task_type"]
  end

  create_table "security_secrets", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.string "scope", null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["account_id", "scope", "key"], unique: true
    t.index ["account_id"]
  end

  create_table "task_executions", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.text "error_message"
    t.text "log_output"
    t.jsonb "result", default: {}
    t.uuid "scheduled_task_id", null: false
    t.datetime "started_at", null: false
    t.string "status", limit: 50, null: false
    t.datetime "updated_at", null: false
    t.index ["scheduled_task_id", "started_at"]
    t.index ["scheduled_task_id"]
    t.index ["started_at"]
    t.index ["status"]
    t.check_constraint "status::text = ANY (ARRAY['running'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'timeout'::character varying::text])", name: "valid_execution_status"
  end

  create_table "validation_rules", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.boolean "auto_fixable", default: false
    t.string "category", null: false
    t.jsonb "configuration", default: {}
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "enabled", default: true
    t.string "name", null: false
    t.string "severity", default: "warning", null: false
    t.datetime "updated_at", null: false
    t.index ["category", "enabled"]
    t.index ["severity"]
  end

  create_table "webhook_deliveries", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.integer "attempt_number", default: 1
    t.datetime "attempted_at"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "next_retry_at"
    t.jsonb "request_headers", default: {}
    t.text "response_body"
    t.jsonb "response_headers", default: {}
    t.integer "response_status"
    t.integer "response_time_ms", comment: "Response time in milliseconds"
    t.string "status", default: "pending"
    t.datetime "updated_at", null: false
    t.uuid "webhook_endpoint_id", null: false
    t.uuid "webhook_event_id", null: false
    t.index ["attempted_at"]
    t.index ["next_retry_at"]
    t.index ["status"]
    t.index ["webhook_endpoint_id"]
    t.index ["webhook_event_id"]
    t.check_constraint "attempt_number > 0", name: "valid_webhook_attempt_number"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'success'::character varying::text, 'failed'::character varying::text, 'timeout'::character varying::text])", name: "valid_webhook_delivery_status"
  end

  create_table "webhook_delivery_stats", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.integer "avg_latency_ms"
    t.datetime "created_at", null: false
    t.jsonb "error_counts", default: {}
    t.integer "failed_deliveries", default: 0, null: false
    t.integer "max_latency_ms"
    t.integer "min_latency_ms"
    t.integer "p95_latency_ms"
    t.integer "retried_deliveries", default: 0, null: false
    t.date "stat_date", null: false
    t.integer "successful_deliveries", default: 0, null: false
    t.integer "total_deliveries", default: 0, null: false
    t.datetime "updated_at", null: false
    t.uuid "webhook_endpoint_id", null: false
    t.index ["stat_date"]
    t.index ["webhook_endpoint_id", "stat_date"], unique: true
    t.index ["webhook_endpoint_id"]
  end

  create_table "webhook_endpoints", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.integer "circuit_break_threshold", default: 5, null: false, comment: "Number of consecutive failures before circuit break"
    t.datetime "circuit_broken_at"
    t.datetime "circuit_cooldown_until"
    t.integer "consecutive_failures", default: 0, null: false
    t.string "content_type", limit: 100, default: "application/json", null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.jsonb "custom_headers", default: {}, null: false
    t.integer "daily_count", default: 0, null: false
    t.datetime "daily_count_reset_at"
    t.integer "daily_limit", default: 100, null: false
    t.string "description", limit: 500
    t.jsonb "event_types", default: []
    t.integer "failure_count", default: 0, null: false
    t.jsonb "headers", default: {}
    t.boolean "is_active", default: true
    t.datetime "last_delivery_at", precision: nil
    t.integer "max_retries", default: 3
    t.jsonb "metadata", default: {}
    t.string "payload_detail_level", default: "full", null: false, comment: "full, minimal, or ids_only"
    t.string "retry_backoff", limit: 20, default: "exponential", null: false
    t.integer "retry_limit", default: 3, null: false
    t.string "secret_key"
    t.string "signature_secret"
    t.string "status", limit: 20, default: "active", null: false
    t.integer "success_count", default: 0, null: false
    t.string "tier", default: "free", null: false
    t.integer "timeout_seconds", default: 30, null: false
    t.datetime "updated_at", null: false
    t.string "url", limit: 1000, null: false
    t.index ["account_id"]
    t.index ["circuit_broken_at"], name: "index_webhook_endpoints_on_circuit_broken", where: "(circuit_broken_at IS NOT NULL)"
    t.index ["content_type"]
    t.index ["created_by_id"]
    t.index ["failure_count"]
    t.index ["is_active"]
    t.index ["last_delivery_at"]
    t.index ["status", "is_active"]
    t.index ["success_count"]
    t.index ["tier"]
    t.check_constraint "content_type::text = ANY (ARRAY['application/json'::character varying::text, 'application/x-www-form-urlencoded'::character varying::text])", name: "valid_webhook_content_type"
    t.check_constraint "failure_count >= 0", name: "valid_webhook_failure_count"
    t.check_constraint "payload_detail_level::text = ANY (ARRAY['full'::character varying::text, 'minimal'::character varying::text, 'ids_only'::character varying::text])", name: "webhook_endpoints_payload_detail_level_check"
    t.check_constraint "retry_backoff::text = ANY (ARRAY['linear'::character varying::text, 'exponential'::character varying::text])", name: "valid_webhook_retry_backoff"
    t.check_constraint "retry_limit >= 0 AND retry_limit <= 10", name: "valid_webhook_retry_limit"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'inactive'::character varying::text, 'suspended'::character varying::text])", name: "valid_webhook_status"
    t.check_constraint "success_count >= 0", name: "valid_webhook_success_count"
    t.check_constraint "tier::text = ANY (ARRAY['free'::text, 'pro'::text, 'business'::text])", name: "check_webhook_tier"
    t.check_constraint "timeout_seconds > 0 AND timeout_seconds <= 300", name: "valid_webhook_timeout"
  end

  create_table "webhook_events", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "event_id", null: false
    t.string "event_type", null: false
    t.string "external_id", null: false
    t.text "metadata"
    t.datetime "occurred_at", null: false
    t.jsonb "payload", default: {}
    t.uuid "payment_id"
    t.datetime "processed_at"
    t.string "provider", null: false
    t.integer "retry_count", default: 0, null: false
    t.string "status", default: "pending"
    t.datetime "updated_at", null: false
    t.index ["account_id", "event_type"]
    t.index ["account_id"]
    t.index ["event_id"], unique: true
    t.index ["external_id"], unique: true
    t.index ["occurred_at"]
    t.index ["payment_id"]
    t.index ["provider"]
    t.index ["retry_count"]
    t.index ["status"]
    t.check_constraint "provider::text = ANY (ARRAY['stripe'::character varying::text, 'paypal'::character varying::text])", name: "valid_webhook_provider"
    t.check_constraint "retry_count >= 0 AND retry_count <= 10", name: "valid_webhook_retry_count"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'processing'::character varying::text, 'processed'::character varying::text, 'failed'::character varying::text, 'skipped'::character varying::text])", name: "valid_webhook_event_status"
  end

  create_table "worker_activities", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "activity_type", limit: 100, null: false
    t.datetime "created_at", null: false
    t.jsonb "details", default: {}
    t.datetime "occurred_at", null: false
    t.string "status", limit: 50
    t.datetime "updated_at", null: false
    t.uuid "worker_id", null: false
    t.index ["activity_type"]
    t.index ["occurred_at"]
    t.index ["worker_id", "occurred_at"]
    t.index ["worker_id"]
  end

  create_table "worker_roles", id: false, force: :cascade do |t|
    t.datetime "granted_at", precision: nil, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.uuid "role_id", null: false
    t.uuid "worker_id", null: false
    t.index ["role_id"]
    t.index ["worker_id", "role_id"], unique: true
    t.index ["worker_id"]
  end

  create_table "workers", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.jsonb "capabilities", default: {}, null: false
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "is_system", default: false, null: false
    t.datetime "last_seen_at"
    t.string "name", null: false
    t.uuid "node_instance_id"
    t.jsonb "permissions", default: []
    t.string "status", default: "active"
    t.string "token_digest"
    t.datetime "updated_at", null: false
    t.string "worker_type", default: "background", null: false
    t.index ["account_id"]
    t.index ["capabilities"], name: "index_workers_on_capabilities", using: :gin
    t.index ["is_system"], name: "index_workers_on_is_system_unique", unique: true, where: "(is_system = true)"
    t.index ["name"], unique: true
    t.index ["node_instance_id"], name: "index_workers_on_node_instance_id", unique: true, where: "(node_instance_id IS NOT NULL)"
    t.index ["permissions"], name: "index_workers_on_permissions", using: :gin
    t.index ["status"]
    t.index ["worker_type"]
    t.check_constraint "worker_type::text = ANY (ARRAY['background'::character varying::text, 'infrastructure'::character varying::text])", name: "workers_worker_type_check"
  end

    add_foreign_key "account_git_webhook_configs", "accounts", column: "account_id"
    add_foreign_key "account_git_webhook_configs", "users", column: "created_by_id"
    add_foreign_key "audit_logs", "accounts", column: "account_id"
    add_foreign_key "audit_logs", "users", column: "user_id", on_delete: :nullify
    add_foreign_key "circuit_breaker_events", "circuit_breakers", column: "circuit_breaker_id"
    add_foreign_key "data_retention_policies", "accounts", column: "account_id"
    add_foreign_key "database_backups", "users", column: "created_by_id"
    add_foreign_key "database_restores", "database_backups", column: "database_backup_id"
    add_foreign_key "database_restores", "users", column: "initiated_by_id"
    add_foreign_key "email_deliveries", "users", column: "user_id"
    add_foreign_key "file_object_tags", "accounts", column: "account_id"
    add_foreign_key "file_object_tags", "file_objects", column: "file_object_id"
    add_foreign_key "file_object_tags", "file_tags", column: "file_tag_id"
    add_foreign_key "file_objects", "accounts", column: "account_id"
    add_foreign_key "file_objects", "file_storages", column: "file_storage_id"
    add_foreign_key "file_objects", "users", column: "deleted_by_id"
    add_foreign_key "file_objects", "users", column: "uploaded_by_id"
    add_foreign_key "file_processing_jobs", "accounts", column: "account_id"
    add_foreign_key "file_processing_jobs", "file_objects", column: "file_object_id"
    add_foreign_key "file_shares", "accounts", column: "account_id"
    add_foreign_key "file_shares", "file_objects", column: "file_object_id"
    add_foreign_key "file_shares", "users", column: "created_by_id"
    add_foreign_key "file_storages", "accounts", column: "account_id"
    add_foreign_key "file_tags", "accounts", column: "account_id"
    add_foreign_key "file_versions", "accounts", column: "account_id"
    add_foreign_key "file_versions", "file_objects", column: "file_object_id"
    add_foreign_key "file_versions", "users", column: "created_by_id"
    add_foreign_key "notifications", "accounts", column: "account_id"
    add_foreign_key "notifications", "users", column: "user_id"
    add_foreign_key "report_requests", "accounts", column: "account_id"
    add_foreign_key "report_requests", "users", column: "requested_by_id"
    add_foreign_key "scheduled_reports", "accounts", column: "account_id"
    add_foreign_key "scheduled_reports", "users", column: "created_by_id"
    add_foreign_key "security_secrets", "accounts", column: "account_id"
    add_foreign_key "task_executions", "scheduled_tasks", column: "scheduled_task_id"
    add_foreign_key "webhook_deliveries", "webhook_endpoints", column: "webhook_endpoint_id"
    add_foreign_key "webhook_deliveries", "webhook_events", column: "webhook_event_id"
    add_foreign_key "webhook_delivery_stats", "webhook_endpoints", column: "webhook_endpoint_id"
    add_foreign_key "webhook_endpoints", "accounts", column: "account_id"
    add_foreign_key "webhook_endpoints", "users", column: "created_by_id"
    add_foreign_key "webhook_events", "accounts", column: "account_id"
    add_foreign_key "worker_activities", "workers", column: "worker_id"
    add_foreign_key "worker_roles", "roles", column: "role_id"
    add_foreign_key "worker_roles", "workers", column: "worker_id"
    add_foreign_key "workers", "accounts", column: "account_id"
  end
end
