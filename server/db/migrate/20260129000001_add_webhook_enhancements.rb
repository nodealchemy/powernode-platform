# frozen_string_literal: true

# Comprehensive webhook enhancements migration
# Phase 1: Branch filtering for git webhooks
# Phase 2: Account-level webhooks and custom headers
# Phase 3: Circuit breaker, enhanced diagnostics, and payload detail levels
class AddWebhookEnhancements < ActiveRecord::Migration[8.0]
  def change
    # =========================================================================
    # Phase 1: Branch Filtering for Git Repositories
    # =========================================================================

    # Add branch filtering columns to git_repositories
    add_column :git_repositories, :branch_filter, :string, comment: "Branch filter pattern for webhooks"
    add_column :git_repositories, :branch_filter_type, :string, default: "none",
               comment: "Filter type: none, exact, wildcard, regex"

    # Add check constraint for branch_filter_type
    execute <<~SQL
      ALTER TABLE git_repositories
      ADD CONSTRAINT git_repositories_branch_filter_type_check
      CHECK (branch_filter_type IN ('none', 'exact', 'wildcard', 'regex'));
    SQL

    # =========================================================================
    # Phase 2: Account-Level Git Webhooks
    # =========================================================================

    create_table :account_git_webhook_configs, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true
      t.references :created_by, type: :uuid, foreign_key: { to_table: :users }

      # Webhook configuration
      t.string :url, null: false
      t.string :name, null: false
      t.text :description
      t.string :status, null: false, default: "active"
      t.boolean :is_active, null: false, default: true

      # Event filtering
      t.jsonb :event_types, null: false, default: []
      t.string :branch_filter
      t.string :branch_filter_type, default: "none"

      # Security
      t.string :secret_key, null: false
      t.string :signature_secret

      # Settings
      t.string :content_type, null: false, default: "application/json"
      t.integer :timeout_seconds, null: false, default: 30
      t.integer :retry_limit, null: false, default: 3
      t.string :retry_backoff, null: false, default: "exponential"
      t.jsonb :custom_headers, null: false, default: {}

      # Statistics
      t.integer :success_count, null: false, default: 0
      t.integer :failure_count, null: false, default: 0
      t.datetime :last_delivery_at

      t.timestamps
    end

    # Add status constraint
    execute <<~SQL
      ALTER TABLE account_git_webhook_configs
      ADD CONSTRAINT account_git_webhook_configs_status_check
      CHECK (status IN ('active', 'inactive'));
    SQL

    # Add branch filter type constraint
    execute <<~SQL
      ALTER TABLE account_git_webhook_configs
      ADD CONSTRAINT account_git_webhook_configs_branch_filter_type_check
      CHECK (branch_filter_type IN ('none', 'exact', 'wildcard', 'regex'));
    SQL

    # Add custom headers to webhook_endpoints (Phase 2.2)
    unless column_exists?(:webhook_endpoints, :custom_headers)
      add_column :webhook_endpoints, :custom_headers, :jsonb, null: false, default: {}
    end

    # =========================================================================
    # Phase 3: Circuit Breaker and Enhanced Diagnostics
    # =========================================================================

    # Add circuit breaker columns to webhook_endpoints
    add_column :webhook_endpoints, :consecutive_failures, :integer, null: false, default: 0
    add_column :webhook_endpoints, :circuit_broken_at, :datetime
    add_column :webhook_endpoints, :circuit_cooldown_until, :datetime
    add_column :webhook_endpoints, :circuit_break_threshold, :integer, null: false, default: 5,
               comment: "Number of consecutive failures before circuit break"

    # Add payload detail level
    add_column :webhook_endpoints, :payload_detail_level, :string, null: false, default: "full",
               comment: "full, minimal, or ids_only"

    # Add constraint for payload_detail_level
    execute <<~SQL
      ALTER TABLE webhook_endpoints
      ADD CONSTRAINT webhook_endpoints_payload_detail_level_check
      CHECK (payload_detail_level IN ('full', 'minimal', 'ids_only'));
    SQL

    # Add response_time_ms to webhook_deliveries for enhanced diagnostics
    add_column :webhook_deliveries, :response_time_ms, :integer,
               comment: "Response time in milliseconds"

    # Add index for circuit breaker queries
    add_index :webhook_endpoints, [:circuit_broken_at],
              where: "circuit_broken_at IS NOT NULL",
              name: "index_webhook_endpoints_on_circuit_broken"

    # Add index for account webhooks queries
    add_index :account_git_webhook_configs, [:account_id, :status],
              name: "index_account_git_webhooks_on_account_status"
  end

  def down
    # Phase 3
    remove_index :webhook_endpoints, name: "index_webhook_endpoints_on_circuit_broken"
    remove_column :webhook_deliveries, :response_time_ms
    execute "ALTER TABLE webhook_endpoints DROP CONSTRAINT IF EXISTS webhook_endpoints_payload_detail_level_check;"
    remove_column :webhook_endpoints, :payload_detail_level
    remove_column :webhook_endpoints, :circuit_break_threshold
    remove_column :webhook_endpoints, :circuit_cooldown_until
    remove_column :webhook_endpoints, :circuit_broken_at
    remove_column :webhook_endpoints, :consecutive_failures

    # Phase 2
    remove_column :webhook_endpoints, :custom_headers if column_exists?(:webhook_endpoints, :custom_headers)
    drop_table :account_git_webhook_configs

    # Phase 1
    execute "ALTER TABLE git_repositories DROP CONSTRAINT IF EXISTS git_repositories_branch_filter_type_check;"
    remove_column :git_repositories, :branch_filter_type
    remove_column :git_repositories, :branch_filter
  end
end
