# frozen_string_literal: true

class CreateDockerSwarmManagementTables < ActiveRecord::Migration[8.0]
  def change
    # Docker Swarm Clusters - Registered cluster connections
    create_table :devops_swarm_clusters, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid, index: true

      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :api_endpoint, null: false
      t.string :api_version, default: "v1.45"
      t.string :environment, null: false, default: "development"
      t.text :encrypted_tls_credentials
      t.string :encryption_key_id
      t.string :swarm_id
      t.string :status, null: false, default: "pending"
      t.integer :node_count, default: 0
      t.integer :service_count, default: 0
      t.boolean :auto_sync, default: true
      t.integer :sync_interval_seconds, default: 60
      t.integer :consecutive_failures, default: 0
      t.datetime :last_synced_at
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :devops_swarm_clusters, :slug, unique: true
    add_index :devops_swarm_clusters, :status
    add_index :devops_swarm_clusters, :environment
    add_index :devops_swarm_clusters, [:account_id, :name], unique: true

    add_check_constraint :devops_swarm_clusters,
      "environment IN ('staging', 'production', 'development', 'custom')",
      name: "swarm_clusters_environment_check"
    add_check_constraint :devops_swarm_clusters,
      "status IN ('pending', 'connected', 'disconnected', 'error', 'maintenance')",
      name: "swarm_clusters_status_check"

    # Docker Swarm Nodes - Cached node state synced from Docker API
    create_table :devops_swarm_nodes, id: :uuid do |t|
      t.references :cluster, null: false, foreign_key: { to_table: :devops_swarm_clusters }, type: :uuid, index: true

      t.string :docker_node_id, null: false
      t.string :hostname, null: false
      t.string :role, null: false, default: "worker"
      t.string :availability, null: false, default: "active"
      t.string :status, null: false, default: "ready"
      t.string :manager_status
      t.string :ip_address
      t.string :engine_version
      t.string :os
      t.string :architecture
      t.bigint :memory_bytes
      t.integer :cpu_count
      t.jsonb :labels, default: {}
      t.datetime :last_seen_at

      t.timestamps
    end

    add_index :devops_swarm_nodes, [:cluster_id, :docker_node_id], unique: true
    add_index :devops_swarm_nodes, :role
    add_index :devops_swarm_nodes, :status

    add_check_constraint :devops_swarm_nodes,
      "role IN ('manager', 'worker')",
      name: "swarm_nodes_role_check"
    add_check_constraint :devops_swarm_nodes,
      "availability IN ('active', 'pause', 'drain')",
      name: "swarm_nodes_availability_check"
    add_check_constraint :devops_swarm_nodes,
      "status IN ('ready', 'down', 'disconnected', 'unknown')",
      name: "swarm_nodes_status_check"

    # Docker Swarm Stacks - Stack definitions with compose YAML
    # (must be created before services, since services reference stacks)
    create_table :devops_swarm_stacks, id: :uuid do |t|
      t.references :cluster, null: false, foreign_key: { to_table: :devops_swarm_clusters }, type: :uuid, index: true

      t.string :name, null: false
      t.string :slug, null: false
      t.text :compose_file
      t.jsonb :compose_variables, default: {}
      t.string :status, null: false, default: "draft"
      t.integer :service_count, default: 0
      t.datetime :last_deployed_at
      t.integer :deploy_count, default: 0

      t.timestamps
    end

    add_index :devops_swarm_stacks, :slug
    add_index :devops_swarm_stacks, [:cluster_id, :name], unique: true

    add_check_constraint :devops_swarm_stacks,
      "status IN ('draft', 'deploying', 'deployed', 'failed', 'removing', 'removed')",
      name: "swarm_stacks_status_check"

    # Docker Swarm Services - Tracked service state
    create_table :devops_swarm_services, id: :uuid do |t|
      t.references :cluster, null: false, foreign_key: { to_table: :devops_swarm_clusters }, type: :uuid, index: true
      t.references :stack, foreign_key: { to_table: :devops_swarm_stacks }, type: :uuid, index: true

      t.string :docker_service_id, null: false
      t.string :service_name, null: false
      t.string :image, null: false
      t.string :mode, null: false, default: "replicated"
      t.integer :desired_replicas, default: 1
      t.integer :running_replicas, default: 0
      t.jsonb :ports, default: []
      t.jsonb :constraints, default: []
      t.jsonb :resource_limits, default: {}
      t.jsonb :resource_reservations, default: {}
      t.jsonb :update_config, default: {}
      t.jsonb :rollback_config, default: {}
      t.jsonb :labels, default: {}
      t.jsonb :environment, default: []
      t.bigint :version

      t.timestamps
    end

    add_index :devops_swarm_services, [:cluster_id, :docker_service_id], unique: true, name: "idx_swarm_services_cluster_docker_id"
    add_index :devops_swarm_services, :service_name

    add_check_constraint :devops_swarm_services,
      "mode IN ('replicated', 'global')",
      name: "swarm_services_mode_check"

    # Docker Swarm Deployments - Audit trail for all mutations
    create_table :devops_swarm_deployments, id: :uuid do |t|
      t.references :cluster, null: false, foreign_key: { to_table: :devops_swarm_clusters }, type: :uuid, index: true
      t.references :service, foreign_key: { to_table: :devops_swarm_services }, type: :uuid, index: true
      t.references :stack, foreign_key: { to_table: :devops_swarm_stacks }, type: :uuid, index: true
      t.references :triggered_by, foreign_key: { to_table: :users }, type: :uuid

      t.string :deployment_type, null: false
      t.string :status, null: false, default: "pending"
      t.jsonb :previous_state, default: {}
      t.jsonb :desired_state, default: {}
      t.jsonb :result, default: {}
      t.datetime :started_at
      t.datetime :completed_at
      t.integer :duration_ms
      t.string :git_sha
      t.string :trigger_source

      t.timestamps
    end

    add_index :devops_swarm_deployments, :deployment_type
    add_index :devops_swarm_deployments, :status
    add_index :devops_swarm_deployments, :created_at

    add_check_constraint :devops_swarm_deployments,
      "deployment_type IN ('deploy', 'update', 'scale', 'rollback', 'remove', 'stack_deploy', 'stack_remove')",
      name: "swarm_deployments_type_check"
    add_check_constraint :devops_swarm_deployments,
      "status IN ('pending', 'running', 'completed', 'failed', 'cancelled')",
      name: "swarm_deployments_status_check"

    # Docker Swarm Events - Health events and alerts
    create_table :devops_swarm_events, id: :uuid do |t|
      t.references :cluster, null: false, foreign_key: { to_table: :devops_swarm_clusters }, type: :uuid, index: true

      t.string :event_type, null: false
      t.string :severity, null: false, default: "info"
      t.string :source_type, null: false
      t.string :source_id
      t.string :source_name
      t.text :message, null: false
      t.jsonb :metadata, default: {}
      t.boolean :acknowledged, default: false
      t.references :acknowledged_by, foreign_key: { to_table: :users }, type: :uuid
      t.datetime :acknowledged_at

      t.timestamps
    end

    add_index :devops_swarm_events, :event_type
    add_index :devops_swarm_events, :severity
    add_index :devops_swarm_events, :acknowledged
    add_index :devops_swarm_events, :created_at

    add_check_constraint :devops_swarm_events,
      "severity IN ('info', 'warning', 'error', 'critical')",
      name: "swarm_events_severity_check"
    add_check_constraint :devops_swarm_events,
      "source_type IN ('node', 'service', 'task', 'cluster', 'stack')",
      name: "swarm_events_source_type_check"
  end
end
