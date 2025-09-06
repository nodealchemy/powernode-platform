# frozen_string_literal: true

class CreateAdminSystemManagement < ActiveRecord::Migration[8.0]
  def change
    # Create admin_settings table - System configuration
    create_table :admin_settings, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.string :key, null: false, limit: 255
      t.text :value
      t.string :setting_type, default: 'string', limit: 50
      t.text :description
      t.boolean :is_public, default: false
      t.boolean :is_encrypted, default: false
      t.string :category, limit: 100
      t.integer :sort_order, default: 0
      t.timestamps null: false
      
      t.index [:key], unique: true, name: 'idx_admin_settings_on_key_unique'
      t.index [:category], name: 'idx_admin_settings_on_category'
      t.index [:setting_type], name: 'idx_admin_settings_on_setting_type'
      t.index [:is_public], name: 'idx_admin_settings_on_is_public'
      t.index [:sort_order], name: 'idx_admin_settings_on_sort_order'
    end

    # Create site_settings table - Public site configuration
    create_table :site_settings, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.string :key, null: false, limit: 255
      t.text :value
      t.string :setting_type, default: 'string', limit: 50
      t.text :description
      t.boolean :is_public, default: true
      t.string :category, limit: 100
      t.timestamps null: false
      
      t.index [:key], unique: true, name: 'idx_site_settings_on_key_unique'
      t.index [:setting_type], name: 'idx_site_settings_on_setting_type'
      t.index [:is_public], name: 'idx_site_settings_on_is_public'
      t.index [:category], name: 'idx_site_settings_on_category'
    end

    # Create pages table - Static content pages
    create_table :pages, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :author, null: true, foreign_key: { to_table: :users }, type: :uuid
      t.string :title, null: false, limit: 255
      t.string :slug, null: false, limit: 255
      t.text :content
      t.text :rendered_content
      t.text :excerpt
      t.string :status, default: 'draft', limit: 50
      t.boolean :is_public, default: false
      t.string :meta_title, limit: 255
      t.string :seo_title, limit: 255
      t.text :meta_description
      t.text :seo_description
      t.text :meta_keywords
      t.integer :word_count
      t.integer :estimated_read_time
      t.jsonb :metadata, default: {}
      t.datetime :published_at
      t.timestamps null: false
      
      t.index [:slug], unique: true, name: 'idx_pages_on_slug_unique'
      t.index [:status], name: 'idx_pages_on_status'
      t.index [:is_public], name: 'idx_pages_on_is_public'
      t.index [:published_at], name: 'idx_pages_on_published_at'
    end

    # Create api_keys table - API access management
    create_table :api_keys, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :created_by, null: true, foreign_key: { to_table: :users }, type: :uuid
      t.string :name, null: false, limit: 255
      t.string :key_digest, null: false
      t.string :prefix, null: false, limit: 20
      t.string :key_prefix, limit: 20
      t.string :key_suffix, limit: 20
      t.jsonb :permissions, default: []
      t.jsonb :scopes, default: []
      t.jsonb :allowed_ips, default: []
      t.jsonb :rate_limits, default: {}
      t.integer :usage_count, default: 0
      t.integer :rate_limit_per_hour
      t.integer :rate_limit_per_day
      t.jsonb :metadata, default: {}
      t.boolean :is_active, default: true
      t.datetime :expires_at
      t.datetime :last_used_at
      t.string :last_used_ip, limit: 45
      t.timestamps null: false
      
      t.index [:key_digest], unique: true, name: 'idx_api_keys_on_key_digest_unique'
      t.index [:prefix], unique: true, name: 'idx_api_keys_on_prefix_unique'
      t.index [:key_prefix], name: 'idx_api_keys_on_key_prefix'
      t.index [:key_suffix], name: 'idx_api_keys_on_key_suffix'
      t.index [:account_id], name: 'idx_api_keys_on_account_id'
      t.index [:is_active], name: 'idx_api_keys_on_is_active'
      t.index [:expires_at], name: 'idx_api_keys_on_expires_at'
      t.index [:usage_count], name: 'idx_api_keys_on_usage_count'
      t.index [:permissions], using: :gin, name: 'idx_api_keys_on_permissions'
      t.index [:scopes], using: :gin, name: 'idx_api_keys_on_scopes'
      t.index [:allowed_ips], using: :gin, name: 'idx_api_keys_on_allowed_ips'
    end

    # Create api_key_usages table - API usage tracking
    create_table :api_key_usages, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :api_key, null: false, foreign_key: true, type: :uuid
      t.string :endpoint, null: false, limit: 500
      t.string :method, null: false, limit: 10
      t.integer :response_status, null: false
      t.integer :response_time_ms
      t.string :ip_address, limit: 45
      t.string :user_agent, limit: 1000
      t.jsonb :request_params, default: {}
      t.datetime :used_at, null: false
      t.timestamps null: false
      
      t.index [:api_key_id, :used_at], name: 'idx_api_key_usages_on_api_key_used_at'
      t.index [:endpoint], name: 'idx_api_key_usages_on_endpoint'
      t.index [:response_status], name: 'idx_api_key_usages_on_response_status'
      t.index [:used_at], name: 'idx_api_key_usages_on_used_at'
    end

    # Create audit_logs table - System audit trail
    create_table :audit_logs, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :user, null: true, foreign_key: { on_delete: :nullify }, type: :uuid
      t.string :action, null: false, limit: 100
      t.string :resource_type, null: false, limit: 100
      t.string :resource_id, limit: 36
      t.string :source, null: false, default: 'web', limit: 20
      t.jsonb :old_values, default: {}
      t.jsonb :new_values, default: {}
      t.jsonb :metadata, default: {}
      t.string :ip_address, limit: 45
      t.string :user_agent, limit: 1000
      t.timestamps null: false
      
      t.index [:account_id, :created_at], name: 'idx_audit_logs_on_account_created_at'
      t.index [:user_id], name: 'idx_audit_logs_on_user_id'
      t.index [:resource_type, :resource_id], name: 'idx_audit_logs_on_resource_type_id'
      t.index [:action], name: 'idx_audit_logs_on_action'
      t.index [:created_at], name: 'idx_audit_logs_on_created_at'
    end

    # Create system_health_checks table - System monitoring
    create_table :system_health_checks, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.string :check_name, null: false, limit: 100
      t.string :status, null: false, limit: 50
      t.text :message
      t.integer :response_time_ms
      t.jsonb :details, default: {}
      t.datetime :checked_at, null: false
      t.timestamps null: false
      
      t.index [:check_name, :checked_at], name: 'idx_system_health_checks_on_name_checked_at'
      t.index [:status], name: 'idx_system_health_checks_on_status'
      t.index [:checked_at], name: 'idx_system_health_checks_on_checked_at'
    end

    # Create system_operations table - System operations tracking
    create_table :system_operations, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :initiated_by, null: true, foreign_key: { to_table: :users }, type: :uuid
      t.string :operation_type, null: false, limit: 100
      t.string :status, null: false, default: 'pending', limit: 50
      t.text :description
      t.jsonb :parameters, default: {}
      t.jsonb :result, default: {}
      t.text :error_message
      t.datetime :started_at, null: false
      t.datetime :completed_at
      t.integer :duration_ms
      t.timestamps null: false
      
      t.index [:operation_type], name: 'idx_system_operations_on_operation_type'
      t.index [:status], name: 'idx_system_operations_on_status'
      t.index [:initiated_by_id], name: 'idx_system_operations_on_initiated_by_id'
      t.index [:started_at], name: 'idx_system_operations_on_started_at'
      t.index [:completed_at], name: 'idx_system_operations_on_completed_at'
    end

    # Create database_backups table - Backup management
    create_table :database_backups, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :created_by, null: false, foreign_key: { to_table: :users }, type: :uuid
      t.string :backup_type, null: false, limit: 50
      t.string :status, null: false, default: 'pending', limit: 50
      t.string :file_path, limit: 1000
      t.integer :file_size_bytes
      t.text :description
      t.datetime :started_at, null: false
      t.datetime :completed_at
      t.integer :duration_seconds
      t.text :error_message
      t.jsonb :metadata, default: {}
      t.timestamps null: false
      
      t.index [:backup_type], name: 'idx_database_backups_on_backup_type'
      t.index [:status], name: 'idx_database_backups_on_status'
      t.index [:created_by_id], name: 'idx_database_backups_on_created_by_id'
      t.index [:started_at], name: 'idx_database_backups_on_started_at'
    end

    # Create database_restores table - Restore operations
    create_table :database_restores, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :database_backup, null: false, foreign_key: true, type: :uuid
      t.references :initiated_by, null: false, foreign_key: { to_table: :users }, type: :uuid
      t.string :status, null: false, default: 'pending', limit: 50
      t.text :description
      t.datetime :started_at, null: false
      t.datetime :completed_at
      t.integer :duration_seconds
      t.text :error_message
      t.jsonb :metadata, default: {}
      t.timestamps null: false
      
      t.index [:database_backup_id], name: 'idx_database_restores_on_database_backup_id'
      t.index [:initiated_by_id], name: 'idx_database_restores_on_initiated_by_id'
      t.index [:status], name: 'idx_database_restores_on_status'
      t.index [:started_at], name: 'idx_database_restores_on_started_at'
    end

    # Create scheduled_tasks table - Task scheduling
    create_table :scheduled_tasks, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.string :name, null: false, limit: 255
      t.string :task_type, null: false, limit: 100
      t.string :cron_expression, limit: 100
      t.integer :interval_seconds
      t.boolean :is_active, default: true
      t.jsonb :parameters, default: {}
      t.datetime :next_run_at
      t.datetime :last_run_at
      t.string :last_status, limit: 50
      t.text :last_error_message
      t.integer :success_count, default: 0
      t.integer :failure_count, default: 0
      t.timestamps null: false
      
      t.index [:name], unique: true, name: 'idx_scheduled_tasks_on_name_unique'
      t.index [:task_type], name: 'idx_scheduled_tasks_on_task_type'
      t.index [:is_active], name: 'idx_scheduled_tasks_on_is_active'
      t.index [:next_run_at], name: 'idx_scheduled_tasks_on_next_run_at'
      t.index [:last_run_at], name: 'idx_scheduled_tasks_on_last_run_at'
    end

    # Create task_executions table - Task execution history
    create_table :task_executions, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :scheduled_task, null: false, foreign_key: true, type: :uuid
      t.string :status, null: false, limit: 50
      t.datetime :started_at, null: false
      t.datetime :completed_at
      t.integer :duration_ms
      t.jsonb :result, default: {}
      t.text :error_message
      t.text :log_output
      t.timestamps null: false
      
      t.index [:scheduled_task_id, :started_at], name: 'idx_task_executions_on_scheduled_task_started_at'
      t.index [:status], name: 'idx_task_executions_on_status'
      t.index [:started_at], name: 'idx_task_executions_on_started_at'
    end

    # Create scheduled_reports table - Report scheduling
    create_table :scheduled_reports, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :created_by, null: false, foreign_key: { to_table: :users }, type: :uuid
      t.string :name, null: false, limit: 255
      t.string :report_type, null: false, limit: 100
      t.string :frequency, null: false, limit: 50
      t.string :format, null: false, default: 'pdf', limit: 20
      t.jsonb :parameters, default: {}
      t.jsonb :recipients, default: []
      t.boolean :is_active, default: true
      t.datetime :next_run_at
      t.datetime :last_run_at
      t.string :last_status, limit: 50
      t.timestamps null: false
      
      t.index [:account_id, :report_type], name: 'idx_scheduled_reports_on_account_report_type'
      t.index [:frequency], name: 'idx_scheduled_reports_on_frequency'
      t.index [:is_active], name: 'idx_scheduled_reports_on_is_active'
      t.index [:next_run_at], name: 'idx_scheduled_reports_on_next_run_at'
    end

    # Create report_requests table - On-demand report generation
    create_table :report_requests, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :requested_by, null: false, foreign_key: { to_table: :users }, type: :uuid
      t.string :report_type, null: false, limit: 100
      t.string :status, null: false, default: 'pending', limit: 50
      t.jsonb :parameters, default: {}
      t.string :file_path, limit: 1000
      t.integer :file_size_bytes
      t.datetime :requested_at, null: false
      t.datetime :completed_at
      t.datetime :expires_at
      t.text :error_message
      t.timestamps null: false
      
      t.index [:account_id, :report_type], name: 'idx_report_requests_on_account_report_type'
      t.index [:requested_by_id], name: 'idx_report_requests_on_requested_by_id'
      t.index [:status], name: 'idx_report_requests_on_status'
      t.index [:requested_at], name: 'idx_report_requests_on_requested_at'
      t.index [:expires_at], name: 'idx_report_requests_on_expires_at'
    end

    # Create worker_activities table - Worker monitoring
    create_table :worker_activities, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :worker, null: false, foreign_key: true, type: :uuid
      t.string :activity_type, null: false, limit: 100
      t.string :status, limit: 50
      t.jsonb :details, default: {}
      t.datetime :occurred_at, null: false
      t.timestamps null: false
      
      t.index [:worker_id, :occurred_at], name: 'idx_worker_activities_on_worker_occurred_at'
      t.index [:activity_type], name: 'idx_worker_activities_on_activity_type'
      t.index [:occurred_at], name: 'idx_worker_activities_on_occurred_at'
    end

    # Create gateway_connection_jobs table - Gateway connection management
    create_table :gateway_connection_jobs, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.string :gateway, null: false
      t.string :operation, null: false
      t.string :status, default: 'pending'
      t.jsonb :payload, default: {}
      t.jsonb :response, default: {}
      t.text :error_message
      t.integer :retry_count, default: 0
      t.datetime :scheduled_at
      t.datetime :completed_at
      t.timestamps null: false
      
      t.index [:gateway, :operation], name: 'idx_gateway_connection_jobs_on_gateway_operation'
      t.index [:status], name: 'idx_gateway_connection_jobs_on_status'
      t.index [:scheduled_at], name: 'idx_gateway_connection_jobs_on_scheduled_at'
    end

    # Add check constraints for admin and system management
    add_check_constraint :admin_settings, "setting_type IN ('string', 'text', 'integer', 'boolean', 'json', 'array')", name: 'valid_admin_setting_type'
    add_check_constraint :site_settings, "setting_type IN ('string', 'text', 'integer', 'boolean', 'json', 'array')", name: 'valid_site_setting_type'
    add_check_constraint :pages, "status IN ('draft', 'published', 'archived')", name: 'valid_page_status'
    add_check_constraint :system_health_checks, "status IN ('healthy', 'warning', 'critical', 'unknown')", name: 'valid_health_status'
    add_check_constraint :system_operations, "status IN ('pending', 'running', 'completed', 'failed', 'cancelled')", name: 'valid_operation_status'
    add_check_constraint :database_backups, "backup_type IN ('full', 'incremental', 'manual')", name: 'valid_backup_type'
    add_check_constraint :database_backups, "status IN ('pending', 'running', 'completed', 'failed')", name: 'valid_backup_status'
    add_check_constraint :database_restores, "status IN ('pending', 'running', 'completed', 'failed')", name: 'valid_restore_status'
    add_check_constraint :scheduled_reports, "frequency IN ('daily', 'weekly', 'monthly', 'quarterly', 'yearly')", name: 'valid_report_frequency'
    add_check_constraint :report_requests, "status IN ('pending', 'generating', 'completed', 'failed', 'expired')", name: 'valid_report_request_status'
    add_check_constraint :task_executions, "status IN ('running', 'completed', 'failed', 'timeout')", name: 'valid_execution_status'
    add_check_constraint :gateway_connection_jobs, "status IN ('pending', 'processing', 'completed', 'failed')", name: 'valid_gateway_job_status'
    add_check_constraint :api_keys, "usage_count >= 0", name: 'valid_api_key_usage_count'
    add_check_constraint :api_keys, "rate_limit_per_hour IS NULL OR rate_limit_per_hour > 0", name: 'valid_api_key_hourly_limit'
    add_check_constraint :api_keys, "rate_limit_per_day IS NULL OR rate_limit_per_day > 0", name: 'valid_api_key_daily_limit'
  end
end