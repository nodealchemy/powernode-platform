# frozen_string_literal: true

class CreateContainerOrchestrationTables < ActiveRecord::Migration[8.0]
  def change
    # MCP Container Templates - Pre-defined container images
    create_table :mcp_container_templates, id: :uuid do |t|
      t.references :account, foreign_key: true, type: :uuid, index: true  # nil = system template
      t.references :created_by, foreign_key: { to_table: :users }, type: :uuid

      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :image_name, null: false  # Docker image name
      t.string :image_tag, default: "latest"
      t.string :registry_url  # Custom registry URL if not Docker Hub
      t.string :visibility, default: "private"  # private, account, public
      t.string :status, default: "active"  # active, deprecated, archived

      # Container configuration
      t.jsonb :environment_variables, default: {}  # Non-secret env vars
      t.jsonb :vault_secret_paths, default: []  # Paths to inject from Vault
      t.jsonb :resource_limits, default: {}  # cpu, memory, storage
      t.jsonb :security_options, default: {}  # caps, read_only, network
      t.jsonb :labels, default: {}  # Gitea runner labels

      # Execution settings
      t.string :entrypoint
      t.jsonb :command_args, default: []
      t.integer :timeout_seconds, default: 3600
      t.integer :max_retries, default: 3
      t.boolean :allow_network, default: false
      t.boolean :privileged, default: false  # Should almost always be false
      t.boolean :read_only_root, default: true

      # Usage tracking
      t.integer :execution_count, default: 0
      t.integer :success_count, default: 0
      t.integer :failure_count, default: 0
      t.datetime :last_used_at

      t.timestamps
    end

    add_index :mcp_container_templates, :slug, unique: true
    add_index :mcp_container_templates, :visibility
    add_index :mcp_container_templates, :status
    add_index :mcp_container_templates, [ :account_id, :name ], unique: true, where: "account_id IS NOT NULL"

    add_check_constraint :mcp_container_templates, "visibility IN ('private', 'account', 'public')", name: "mcp_templates_visibility_check"
    add_check_constraint :mcp_container_templates, "status IN ('active', 'deprecated', 'archived')", name: "mcp_templates_status_check"

    # MCP Container Instances - Running/completed containers
    create_table :mcp_container_instances, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid, index: true
      t.references :template, foreign_key: { to_table: :mcp_container_templates }, type: :uuid, index: true
      t.references :triggered_by, foreign_key: { to_table: :users }, type: :uuid
      t.references :a2a_task, foreign_key: { to_table: :ai_a2a_tasks }, type: :uuid, index: true

      t.string :execution_id, null: false  # Unique execution identifier
      t.string :status, default: "pending"  # pending, provisioning, running, completed, failed, cancelled, timeout
      t.string :image_name, null: false
      t.string :image_tag, default: "latest"

      # Gitea Runner integration
      t.string :gitea_workflow_run_id
      t.string :gitea_job_id
      t.string :runner_name
      t.jsonb :runner_labels, default: []

      # Execution context
      t.jsonb :environment_variables, default: {}
      t.jsonb :input_parameters, default: {}
      t.jsonb :output_data, default: {}
      t.jsonb :artifacts, default: []  # Output files/data
      t.text :logs  # Container stdout/stderr (truncated)
      t.string :exit_code
      t.text :error_message

      # Resource usage
      t.integer :memory_used_mb
      t.float :cpu_used_millicores
      t.bigint :storage_used_bytes
      t.integer :network_bytes_in
      t.integer :network_bytes_out

      # Timing
      t.datetime :queued_at
      t.datetime :started_at
      t.datetime :completed_at
      t.integer :duration_ms
      t.integer :timeout_seconds

      # Security
      t.string :vault_token_id  # Reference to short-lived Vault token used
      t.boolean :sandbox_enabled, default: true
      t.jsonb :security_violations, default: []

      t.timestamps
    end

    add_index :mcp_container_instances, :execution_id, unique: true
    add_index :mcp_container_instances, :status
    add_index :mcp_container_instances, :gitea_workflow_run_id
    add_index :mcp_container_instances, [ :account_id, :status ]
    add_index :mcp_container_instances, :created_at

    add_check_constraint :mcp_container_instances,
      "status IN ('pending', 'provisioning', 'running', 'completed', 'failed', 'cancelled', 'timeout')",
      name: "mcp_instances_status_check"

    # MCP Resource Quotas - Account limits
    create_table :mcp_resource_quotas, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid, index: { unique: true }

      # Container limits
      t.integer :max_concurrent_containers, default: 5
      t.integer :max_containers_per_hour, default: 50
      t.integer :max_containers_per_day, default: 500

      # Resource limits per container
      t.integer :max_memory_mb, default: 512
      t.integer :max_cpu_millicores, default: 500
      t.bigint :max_storage_bytes, default: 1073741824  # 1GB
      t.integer :max_execution_time_seconds, default: 3600

      # Network limits
      t.boolean :allow_network_access, default: false
      t.jsonb :allowed_egress_domains, default: []

      # Current usage tracking
      t.integer :current_running_containers, default: 0
      t.integer :containers_used_today, default: 0
      t.integer :containers_used_this_hour, default: 0
      t.datetime :usage_reset_at

      # Overage handling
      t.boolean :allow_overage, default: false
      t.decimal :overage_rate_per_container, precision: 10, scale: 4

      t.timestamps
    end

    # MCP Secret References - Vault secret paths
    create_table :mcp_secret_references, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid, index: true
      t.references :created_by, foreign_key: { to_table: :users }, type: :uuid

      t.string :name, null: false
      t.string :secret_type, null: false  # ai_provider, mcp_server, chat_channel, git_credential, custom
      t.string :vault_path, null: false
      t.string :vault_key  # Specific key within the secret (optional)
      t.text :description
      t.jsonb :metadata, default: {}

      t.datetime :last_accessed_at
      t.datetime :last_rotated_at
      t.datetime :expires_at

      t.timestamps
    end

    add_index :mcp_secret_references, [ :account_id, :name ], unique: true
    add_index :mcp_secret_references, :secret_type
    add_index :mcp_secret_references, :vault_path
    add_index :mcp_secret_references, :expires_at, where: "expires_at IS NOT NULL"

    add_check_constraint :mcp_secret_references,
      "secret_type IN ('ai_provider', 'mcp_server', 'chat_channel', 'git_credential', 'custom')",
      name: "mcp_secrets_type_check"
  end
end
