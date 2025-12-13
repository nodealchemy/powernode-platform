# frozen_string_literal: true

class CreateNotificationSystem < ActiveRecord::Migration[8.0]
  def change
    # Create email_deliveries table - Email tracking and delivery status
    create_table :email_deliveries, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :user, null: true, foreign_key: true, type: :uuid
      t.string :recipient_email, null: false
      t.string :sender_email
      t.string :subject, null: false
      t.text :body_text
      t.text :body_html
      t.string :email_type, null: false
      t.string :status, default: 'pending'
      t.string :external_id
      t.text :error_message
      t.datetime :sent_at
      t.datetime :delivered_at
      t.datetime :opened_at
      t.datetime :clicked_at
      t.datetime :bounced_at
      t.string :bounce_reason
      t.integer :retry_count, default: 0
      t.jsonb :metadata, default: {}
      t.timestamps null: false

      t.index [ :recipient_email ], name: 'idx_email_deliveries_on_recipient_email'
      t.index [ :email_type ], name: 'idx_email_deliveries_on_email_type'
      t.index [ :status ], name: 'idx_email_deliveries_on_status'
      t.index [ :sent_at ], name: 'idx_email_deliveries_on_sent_at'
      t.index [ :external_id ], unique: true, where: "external_id IS NOT NULL", name: 'idx_email_deliveries_on_external_id_unique'
    end

    # Create webhook_endpoints table - Webhook management
    create_table :webhook_endpoints, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :created_by, null: true, foreign_key: { to_table: :users }, type: :uuid
      t.string :url, null: false, limit: 1000
      t.string :description, limit: 500
      t.string :status, null: false, default: 'active', limit: 20
      t.boolean :is_active, default: true
      t.string :secret_key
      t.string :content_type, null: false, default: 'application/json', limit: 100
      t.integer :timeout_seconds, null: false, default: 30
      t.integer :retry_limit, null: false, default: 3
      t.string :retry_backoff, null: false, default: 'exponential', limit: 20
      t.integer :max_retries, default: 3
      t.jsonb :event_types, default: []
      t.jsonb :headers, default: {}
      t.integer :success_count, null: false, default: 0
      t.integer :failure_count, null: false, default: 0
      t.timestamp :last_delivery_at
      t.jsonb :metadata, default: {}
      t.timestamps null: false

      t.index [ :account_id ], name: 'idx_webhook_endpoints_on_account_id'
      t.index [ :created_by_id ], name: 'idx_webhook_endpoints_on_created_by'
      t.index [ :is_active ], name: 'idx_webhook_endpoints_on_is_active'
      t.index [ :content_type ], name: 'idx_webhook_endpoints_on_content_type'
      t.index [ :success_count ], name: 'idx_webhook_endpoints_on_success_count'
      t.index [ :failure_count ], name: 'idx_webhook_endpoints_on_failure_count'
      t.index [ :last_delivery_at ], name: 'idx_webhook_endpoints_on_last_delivery_at'
      t.index [ :status, :is_active ], name: 'idx_webhook_endpoints_on_status_active'
    end

    # Create webhook_events table - Event tracking
    create_table :webhook_events, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :account, null: true, foreign_key: true, type: :uuid
      t.references :payment, null: true, foreign_key: true, type: :uuid
      t.string :provider, null: false
      t.string :event_type, null: false
      t.string :event_id, null: false
      t.string :external_id, null: false
      t.jsonb :payload, default: {}
      t.datetime :occurred_at, null: false
      t.string :status, default: 'pending'
      t.integer :retry_count, null: false, default: 0
      t.text :error_message
      t.text :metadata
      t.datetime :processed_at
      t.timestamps null: false

      t.index [ :account_id, :event_type ], name: 'idx_webhook_events_on_account_event_type'
      t.index [ :event_id ], unique: true, name: 'idx_webhook_events_on_event_id_unique'
      t.index [ :external_id ], unique: true, name: 'idx_webhook_events_on_external_id_unique'
      t.index [ :provider ], name: 'idx_webhook_events_on_provider'
      t.index [ :retry_count ], name: 'idx_webhook_events_on_retry_count'
      t.index [ :occurred_at ], name: 'idx_webhook_events_on_occurred_at'
      t.index [ :status ], name: 'idx_webhook_events_on_status'
    end

    # Create webhook_deliveries table - Delivery tracking
    create_table :webhook_deliveries, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :webhook_endpoint, null: false, foreign_key: true, type: :uuid
      t.references :webhook_event, null: false, foreign_key: true, type: :uuid
      t.string :status, default: 'pending'
      t.integer :attempt_number, default: 1
      t.integer :response_status
      t.text :response_body
      t.text :error_message
      t.datetime :attempted_at
      t.datetime :next_retry_at
      t.jsonb :request_headers, default: {}
      t.jsonb :response_headers, default: {}
      t.timestamps null: false

      t.index [ :webhook_endpoint_id ], name: 'idx_webhook_deliveries_on_webhook_endpoint_id'
      t.index [ :webhook_event_id ], name: 'idx_webhook_deliveries_on_webhook_event_id'
      t.index [ :status ], name: 'idx_webhook_deliveries_on_status'
      t.index [ :attempted_at ], name: 'idx_webhook_deliveries_on_attempted_at'
      t.index [ :next_retry_at ], name: 'idx_webhook_deliveries_on_next_retry_at'
    end

    # Create background_jobs table - Job queue management
    create_table :background_jobs, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.string :job_id, null: false
      t.string :job_type, null: false
      t.string :status, default: 'pending'
      t.integer :priority, default: 0
      t.integer :attempts, default: 0
      t.integer :max_attempts, default: 25
      t.jsonb :arguments, default: {}
      t.text :error_message
      t.text :backtrace
      t.datetime :scheduled_at
      t.datetime :started_at
      t.datetime :finished_at
      t.datetime :failed_at
      t.timestamps null: false

      t.index [ :job_id ], unique: true, name: 'idx_background_jobs_on_job_id_unique'
      t.index [ :job_type ], name: 'idx_background_jobs_on_job_type'
      t.index [ :status ], name: 'idx_background_jobs_on_status'
      t.index [ :job_type, :status ], name: 'idx_background_jobs_on_job_type_status'
      t.index [ :scheduled_at ], name: 'idx_background_jobs_on_scheduled_at'
      t.index [ :created_at ], name: 'idx_background_jobs_on_created_at'
    end

    # Create reconciliation_reports table - Payment reconciliation
    create_table :reconciliation_reports, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.string :report_type, null: false
      t.string :reconciliation_type, null: false
      t.string :gateway, null: false
      t.date :report_date, null: false
      t.date :reconciliation_date, null: false
      t.date :date_range_start, null: false
      t.date :date_range_end, null: false
      t.string :status, default: 'pending'
      t.integer :total_transactions, default: 0
      t.integer :matched_transactions, default: 0
      t.integer :unmatched_transactions, default: 0
      t.integer :discrepancies_found, default: 0
      t.integer :discrepancies_count, default: 0
      t.integer :high_severity_count, default: 0
      t.integer :medium_severity_count, default: 0
      t.decimal :total_amount_cents, precision: 15, scale: 2, default: 0
      t.text :summary
      t.jsonb :metadata, default: {}
      t.timestamps null: false

      t.index [ :gateway, :report_date, :report_type ], unique: true, name: 'idx_reconciliation_reports_on_gateway_date_type_unique'
      t.index [ :status ], name: 'idx_reconciliation_reports_on_status'
      t.index [ :report_date ], name: 'idx_reconciliation_reports_on_report_date'
    end

    # Create reconciliation_flags table - Issue flagging
    create_table :reconciliation_flags, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :reconciliation_report, null: false, foreign_key: true, type: :uuid
      t.string :flag_type, null: false
      t.string :severity, default: 'medium'
      t.string :transaction_id
      t.text :description, null: false
      t.decimal :amount_cents, precision: 15, scale: 2
      t.string :status, default: 'open'
      t.datetime :resolved_at
      t.references :resolved_by, null: true, foreign_key: { to_table: :users }, type: :uuid
      t.text :resolution_notes
      t.jsonb :metadata, default: {}
      t.timestamps null: false

      t.index [ :reconciliation_report_id ], name: 'idx_reconciliation_flags_on_reconciliation_report_id'
      t.index [ :flag_type ], name: 'idx_reconciliation_flags_on_flag_type'
      t.index [ :severity ], name: 'idx_reconciliation_flags_on_severity'
      t.index [ :status ], name: 'idx_reconciliation_flags_on_status'
      t.index [ :resolved_at ], name: 'idx_reconciliation_flags_on_resolved_at'
    end

    # Create reconciliation_investigations table - Investigation tracking
    create_table :reconciliation_investigations, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :reconciliation_flag, null: false, foreign_key: true, type: :uuid
      t.references :investigator, null: false, foreign_key: { to_table: :users }, type: :uuid
      t.string :status, default: 'open'
      t.text :notes
      t.datetime :started_at, null: false
      t.datetime :completed_at
      t.jsonb :findings, default: {}
      t.timestamps null: false

      t.index [ :reconciliation_flag_id ], name: 'idx_reconciliation_investigations_on_reconciliation_flag_id'
      t.index [ :investigator_id ], name: 'idx_reconciliation_investigations_on_investigator_id'
      t.index [ :status ], name: 'idx_reconciliation_investigations_on_status'
      t.index [ :started_at ], name: 'idx_reconciliation_investigations_on_started_at'
    end

    # Add check constraints for notification system
    add_check_constraint :email_deliveries, "status IN ('pending', 'sent', 'delivered', 'bounced', 'failed', 'opened', 'clicked')", name: 'valid_email_status'
    add_check_constraint :email_deliveries, "email_type IN ('welcome', 'verification', 'password_reset', 'invitation', 'notification', 'marketing', 'transactional')", name: 'valid_email_type'
    add_check_constraint :email_deliveries, 'retry_count >= 0', name: 'valid_email_retry_count'

    add_check_constraint :webhook_endpoints, 'timeout_seconds > 0 AND timeout_seconds <= 300', name: 'valid_webhook_timeout'
    add_check_constraint :webhook_endpoints, 'retry_limit >= 0 AND retry_limit <= 10', name: 'valid_webhook_retry_limit'
    add_check_constraint :webhook_endpoints, "status IN ('active', 'inactive', 'suspended')", name: 'valid_webhook_status'
    add_check_constraint :webhook_endpoints, "content_type IN ('application/json', 'application/x-www-form-urlencoded')", name: 'valid_webhook_content_type'
    add_check_constraint :webhook_endpoints, "retry_backoff IN ('linear', 'exponential')", name: 'valid_webhook_retry_backoff'
    add_check_constraint :webhook_endpoints, 'success_count >= 0', name: 'valid_webhook_success_count'
    add_check_constraint :webhook_endpoints, 'failure_count >= 0', name: 'valid_webhook_failure_count'

    add_check_constraint :webhook_events, "status IN ('pending', 'processing', 'processed', 'failed', 'skipped')", name: 'valid_webhook_event_status'
    add_check_constraint :webhook_events, "provider IN ('stripe', 'paypal')", name: 'valid_webhook_provider'
    add_check_constraint :webhook_events, 'retry_count >= 0 AND retry_count <= 10', name: 'valid_webhook_retry_count'

    add_check_constraint :webhook_deliveries, "status IN ('pending', 'success', 'failed', 'timeout')", name: 'valid_webhook_delivery_status'
    add_check_constraint :webhook_deliveries, 'attempt_number > 0', name: 'valid_webhook_attempt_number'

    add_check_constraint :background_jobs, "status IN ('pending', 'processing', 'completed', 'failed', 'cancelled', 'retrying')", name: 'valid_job_status'
    add_check_constraint :background_jobs, 'attempts >= 0 AND max_attempts > 0', name: 'valid_job_attempts'
    add_check_constraint :background_jobs, 'priority >= 0', name: 'valid_job_priority'

    add_check_constraint :reconciliation_reports, "report_type IN ('daily', 'weekly', 'monthly', 'manual')", name: 'valid_report_type'
    add_check_constraint :reconciliation_reports, "gateway IN ('stripe', 'paypal')", name: 'valid_reconciliation_gateway'
    add_check_constraint :reconciliation_reports, "status IN ('pending', 'processing', 'completed', 'failed')", name: 'valid_reconciliation_status'
    add_check_constraint :reconciliation_reports, 'total_transactions >= 0 AND matched_transactions >= 0 AND unmatched_transactions >= 0', name: 'valid_transaction_counts'

    add_check_constraint :reconciliation_flags, "flag_type IN ('missing_payment', 'duplicate_payment', 'amount_mismatch', 'status_mismatch', 'unknown_transaction')", name: 'valid_flag_type'
    add_check_constraint :reconciliation_flags, "severity IN ('low', 'medium', 'high', 'critical')", name: 'valid_flag_severity'
    add_check_constraint :reconciliation_flags, "status IN ('open', 'investigating', 'resolved', 'dismissed')", name: 'valid_flag_status'

    add_check_constraint :reconciliation_investigations, "status IN ('open', 'in_progress', 'completed', 'escalated')", name: 'valid_investigation_status'
  end
end
