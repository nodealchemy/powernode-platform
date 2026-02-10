# frozen_string_literal: true

# MCP Hosting Tables - Managed hosting for MCP servers
#
# Revenue Model: Hosting fees + marketplace commission
# - Free tier: 1 server, limited requests
# - Pro: 5 servers, 10K requests/mo ($79/mo)
# - Enterprise: Unlimited + private registry ($299/mo)
# - Marketplace commission: 20% on paid tools
#
class CreateMcpHostingTables < ActiveRecord::Migration[8.0]
  def change
    # ==========================================================================
    # MCP HOSTED SERVERS - Managed MCP server instances
    # ==========================================================================
    create_table :mcp_hosted_servers, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :mcp_server, foreign_key: true, type: :uuid
      t.string :name, null: false
      t.text :description
      t.string :server_type, null: false, default: "custom"
      t.string :status, null: false, default: "pending"
      t.string :visibility, null: false, default: "private"

      # Deployment configuration
      t.string :runtime, null: false, default: "node"
      t.string :runtime_version
      t.string :deployment_region, default: "us-east-1"
      t.integer :memory_mb, default: 512
      t.integer :cpu_millicores, default: 500
      t.integer :max_instances, default: 3
      t.integer :min_instances, default: 0
      t.integer :timeout_seconds, default: 30

      # Source configuration
      t.string :source_type, null: false
      t.string :source_url
      t.string :source_branch
      t.string :source_commit
      t.text :source_code
      t.string :entry_point
      t.jsonb :environment_variables, default: {}
      t.jsonb :build_config, default: {}

      # Health and metrics
      t.string :health_status, default: "unknown"
      t.datetime :last_health_check_at
      t.integer :current_instances, default: 0
      t.bigint :total_requests, default: 0
      t.bigint :total_errors, default: 0
      t.decimal :avg_latency_ms, precision: 10, scale: 2
      t.decimal :total_cost_usd, precision: 10, scale: 4, default: 0

      # Marketplace
      t.boolean :is_published, null: false, default: false
      t.decimal :price_per_request, precision: 10, scale: 6
      t.decimal :monthly_subscription_price, precision: 10, scale: 2
      t.integer :marketplace_installs, default: 0
      t.decimal :marketplace_rating, precision: 3, scale: 2
      t.integer :marketplace_reviews_count, default: 0

      # Versioning
      t.string :current_version
      t.integer :version_count, default: 1
      t.datetime :last_deployed_at
      t.references :deployed_by, foreign_key: { to_table: :users }, type: :uuid

      t.jsonb :tools_manifest, default: []
      t.jsonb :capabilities, default: []
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :mcp_hosted_servers, [ :account_id, :status ]
    add_index :mcp_hosted_servers, [ :account_id, :name ], unique: true
    add_index :mcp_hosted_servers, :status
    add_index :mcp_hosted_servers, :visibility
    add_index :mcp_hosted_servers, :is_published
    add_index :mcp_hosted_servers, :server_type
    add_index :mcp_hosted_servers, :health_status

    # ==========================================================================
    # MCP SERVER DEPLOYMENTS - Deployment history
    # ==========================================================================
    create_table :mcp_server_deployments, id: :uuid do |t|
      t.references :hosted_server, null: false, foreign_key: { to_table: :mcp_hosted_servers }, type: :uuid
      t.references :deployed_by, foreign_key: { to_table: :users }, type: :uuid
      t.string :version, null: false
      t.string :status, null: false, default: "pending"
      t.string :deployment_type, null: false, default: "manual"

      # Build info
      t.string :source_commit
      t.text :build_logs
      t.datetime :build_started_at
      t.datetime :build_completed_at
      t.integer :build_duration_seconds

      # Deployment info
      t.datetime :deployment_started_at
      t.datetime :deployment_completed_at
      t.integer :deployment_duration_seconds
      t.text :deployment_logs

      # Rollback info
      t.boolean :is_rollback, null: false, default: false
      t.uuid :rollback_from_deployment_id

      t.string :error_message
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :mcp_server_deployments, [ :hosted_server_id, :created_at ]
    add_index :mcp_server_deployments, :status
    add_index :mcp_server_deployments, :version

    # ==========================================================================
    # MCP SERVER METRICS - Time-series metrics for hosted servers
    # ==========================================================================
    create_table :mcp_server_metrics, id: :uuid do |t|
      t.references :hosted_server, null: false, foreign_key: { to_table: :mcp_hosted_servers }, type: :uuid
      t.datetime :recorded_at, null: false
      t.string :granularity, null: false, default: "minute"

      # Request metrics
      t.integer :total_requests, default: 0
      t.integer :successful_requests, default: 0
      t.integer :failed_requests, default: 0
      t.integer :timeout_requests, default: 0

      # Latency metrics
      t.decimal :avg_latency_ms, precision: 10, scale: 2
      t.decimal :p50_latency_ms, precision: 10, scale: 2
      t.decimal :p95_latency_ms, precision: 10, scale: 2
      t.decimal :p99_latency_ms, precision: 10, scale: 2

      # Resource metrics
      t.integer :active_instances
      t.decimal :cpu_usage_percent, precision: 5, scale: 2
      t.decimal :memory_usage_percent, precision: 5, scale: 2
      t.bigint :memory_used_bytes

      # Cost metrics
      t.decimal :compute_cost_usd, precision: 10, scale: 6
      t.decimal :bandwidth_cost_usd, precision: 10, scale: 6
      t.decimal :total_cost_usd, precision: 10, scale: 6

      t.timestamps
    end

    add_index :mcp_server_metrics, [ :hosted_server_id, :recorded_at ]
    add_index :mcp_server_metrics, [ :granularity, :recorded_at ]
    add_index :mcp_server_metrics, :recorded_at

    # ==========================================================================
    # MCP SERVER SUBSCRIPTIONS - Account subscriptions to hosted servers
    # ==========================================================================
    create_table :mcp_server_subscriptions, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :hosted_server, null: false, foreign_key: { to_table: :mcp_hosted_servers }, type: :uuid
      t.string :status, null: false, default: "active"
      t.string :subscription_type, null: false, default: "free"
      t.decimal :monthly_price_usd, precision: 10, scale: 2, default: 0
      t.integer :monthly_request_limit
      t.integer :requests_used_this_month, default: 0
      t.datetime :current_period_start
      t.datetime :current_period_end
      t.datetime :subscribed_at, null: false
      t.datetime :cancelled_at
      t.datetime :expires_at
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :mcp_server_subscriptions, [ :account_id, :hosted_server_id ], unique: true, name: "idx_mcp_subscriptions_account_server"
    add_index :mcp_server_subscriptions, :status

    # ==========================================================================
    # CONSTRAINTS
    # ==========================================================================
    execute <<-SQL
      ALTER TABLE mcp_hosted_servers
      ADD CONSTRAINT check_mcp_server_status
      CHECK (status IN ('pending', 'building', 'deploying', 'running', 'stopped', 'failed', 'deleted'))
    SQL

    execute <<-SQL
      ALTER TABLE mcp_hosted_servers
      ADD CONSTRAINT check_mcp_server_visibility
      CHECK (visibility IN ('private', 'team', 'public', 'marketplace'))
    SQL

    execute <<-SQL
      ALTER TABLE mcp_hosted_servers
      ADD CONSTRAINT check_mcp_source_type
      CHECK (source_type IN ('git', 'upload', 'inline', 'registry'))
    SQL

    execute <<-SQL
      ALTER TABLE mcp_server_deployments
      ADD CONSTRAINT check_deployment_status
      CHECK (status IN ('pending', 'building', 'deploying', 'running', 'failed', 'rolled_back', 'superseded'))
    SQL

    execute <<-SQL
      ALTER TABLE mcp_server_subscriptions
      ADD CONSTRAINT check_mcp_subscription_status
      CHECK (status IN ('active', 'paused', 'cancelled', 'expired'))
    SQL
  end
end
