# frozen_string_literal: true

class CreateDockerHostManagementTables < ActiveRecord::Migration[8.0]
  def change
    # ================================================================
    # Docker Hosts - Registered standalone Docker daemon hosts
    # ================================================================
    create_table :devops_docker_hosts, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :api_endpoint, null: false
      t.string :api_version, default: "v1.45"
      t.string :environment, null: false, default: "development"
      t.string :status, null: false, default: "pending"
      t.text :encrypted_tls_credentials
      t.string :encryption_key_id
      t.string :docker_version
      t.string :os_type
      t.string :architecture
      t.string :kernel_version
      t.integer :container_count, default: 0
      t.integer :image_count, default: 0
      t.bigint :memory_bytes
      t.integer :cpu_count
      t.bigint :storage_bytes
      t.boolean :auto_sync, default: true
      t.integer :sync_interval_seconds, default: 60
      t.integer :consecutive_failures, default: 0
      t.datetime :last_synced_at
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :devops_docker_hosts, :slug, unique: true
    add_index :devops_docker_hosts, [:account_id, :name], unique: true
    add_index :devops_docker_hosts, :status
    add_index :devops_docker_hosts, :environment

    add_check_constraint :devops_docker_hosts,
      "environment IN ('staging', 'production', 'development', 'custom')",
      name: "chk_docker_hosts_environment"
    add_check_constraint :devops_docker_hosts,
      "status IN ('pending', 'connected', 'disconnected', 'error', 'maintenance')",
      name: "chk_docker_hosts_status"

    # ================================================================
    # Docker Containers - Cached container state from Docker hosts
    # ================================================================
    create_table :devops_docker_containers, id: :uuid do |t|
      t.references :docker_host, type: :uuid, null: false,
        foreign_key: { to_table: :devops_docker_hosts }, index: true
      t.string :docker_container_id, null: false
      t.string :name, null: false
      t.string :image, null: false
      t.string :image_id
      t.string :state, null: false, default: "created"
      t.string :status_text
      t.jsonb :ports, default: []
      t.jsonb :mounts, default: []
      t.jsonb :networks, default: {}
      t.jsonb :labels, default: {}
      t.jsonb :environment, default: []
      t.text :command
      t.string :restart_policy
      t.integer :restart_count, default: 0
      t.bigint :size_rw
      t.datetime :started_at
      t.datetime :finished_at
      t.datetime :last_seen_at
      t.timestamps
    end

    add_index :devops_docker_containers, [:docker_host_id, :docker_container_id],
      unique: true, name: "idx_docker_containers_host_container"
    add_index :devops_docker_containers, :state

    add_check_constraint :devops_docker_containers,
      "state IN ('created', 'running', 'paused', 'restarting', 'exited', 'removing', 'dead')",
      name: "chk_docker_containers_state"

    # ================================================================
    # Docker Images - Cached image state from Docker hosts
    # ================================================================
    create_table :devops_docker_images, id: :uuid do |t|
      t.references :docker_host, type: :uuid, null: false,
        foreign_key: { to_table: :devops_docker_hosts }, index: true
      t.string :docker_image_id, null: false
      t.jsonb :repo_tags, default: []
      t.jsonb :repo_digests, default: []
      t.bigint :size_bytes
      t.bigint :virtual_size
      t.integer :container_count, default: 0
      t.string :architecture
      t.string :os
      t.jsonb :labels, default: {}
      t.datetime :docker_created_at
      t.datetime :last_seen_at
      t.timestamps
    end

    add_index :devops_docker_images, [:docker_host_id, :docker_image_id],
      unique: true, name: "idx_docker_images_host_image"

    # ================================================================
    # Docker Events - Health events and alerts
    # ================================================================
    create_table :devops_docker_events, id: :uuid do |t|
      t.references :docker_host, type: :uuid, null: false,
        foreign_key: { to_table: :devops_docker_hosts }, index: true
      t.string :event_type, null: false
      t.string :severity, null: false, default: "info"
      t.string :source_type, null: false
      t.string :source_id
      t.string :source_name
      t.text :message, null: false
      t.jsonb :metadata, default: {}
      t.boolean :acknowledged, default: false
      t.references :acknowledged_by, type: :uuid, foreign_key: { to_table: :users },
        index: true, null: true
      t.datetime :acknowledged_at
      t.timestamps
    end

    add_index :devops_docker_events, :severity
    add_index :devops_docker_events, :acknowledged
    add_index :devops_docker_events, :created_at

    add_check_constraint :devops_docker_events,
      "severity IN ('info', 'warning', 'error', 'critical')",
      name: "chk_docker_events_severity"
    add_check_constraint :devops_docker_events,
      "source_type IN ('host', 'container', 'image', 'network', 'volume')",
      name: "chk_docker_events_source_type"

    # ================================================================
    # Docker Activities - Container lifecycle audit trail
    # ================================================================
    create_table :devops_docker_activities, id: :uuid do |t|
      t.references :docker_host, type: :uuid, null: false,
        foreign_key: { to_table: :devops_docker_hosts }, index: true
      t.references :container, type: :uuid,
        foreign_key: { to_table: :devops_docker_containers },
        index: true, null: true
      t.references :image, type: :uuid,
        foreign_key: { to_table: :devops_docker_images },
        index: true, null: true
      t.references :triggered_by, type: :uuid,
        foreign_key: { to_table: :users },
        index: true, null: true
      t.string :activity_type, null: false
      t.string :status, null: false, default: "pending"
      t.jsonb :params, default: {}
      t.jsonb :result, default: {}
      t.datetime :started_at
      t.datetime :completed_at
      t.integer :duration_ms
      t.string :trigger_source
      t.timestamps
    end

    add_index :devops_docker_activities, :activity_type
    add_index :devops_docker_activities, :status
    add_index :devops_docker_activities, :created_at

    add_check_constraint :devops_docker_activities,
      "activity_type IN ('create', 'start', 'stop', 'restart', 'remove', 'pull', 'image_remove', 'image_tag')",
      name: "chk_docker_activities_type"
    add_check_constraint :devops_docker_activities,
      "status IN ('pending', 'running', 'completed', 'failed')",
      name: "chk_docker_activities_status"
  end
end
