# frozen_string_literal: true

# Consolidated migration for Powernode System - Operations & Storage
# Combines: operations, provider_volume_types, provider_volumes, provider_volume_snapshots,
#           provider_networks, provider_network_subnets, region_volume_types
class CreatePowernodeSystemOperationsStorage < ActiveRecord::Migration[8.0]
  def change
    # ============ System::Operation ============
    create_table :system_operations, id: :uuid do |t|
      t.string :command, null: false
      t.string :status, null: false, default: 'pending'
      t.text :description
      t.integer :progress, null: false, default: 0
      t.datetime :scheduled_at
      t.datetime :started_at
      t.datetime :completed_at
      t.boolean :exclusive, null: false, default: false
      t.jsonb :events, null: false, default: []
      t.jsonb :options, null: false, default: {}
      t.text :error_message

      # Polymorphic association for operable (Node, NodeInstance, Provider, etc.)
      t.references :operable, polymorphic: true, type: :uuid

      # Who initiated the operation
      t.references :initiated_by, foreign_key: { to_table: :users }, type: :uuid

      t.references :account, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end

    add_index :system_operations, :command
    add_index :system_operations, :status
    add_index :system_operations, :scheduled_at
    add_index :system_operations, :started_at
    add_index :system_operations, :completed_at
    add_index :system_operations, :exclusive
    add_index :system_operations, :events, using: :gin
    add_index :system_operations, :options, using: :gin
    add_index :system_operations, [:operable_type, :operable_id]

    add_check_constraint :system_operations,
      "status IN ('pending', 'scheduled', 'running', 'complete', 'failed', 'aborted', 'cancelled')",
      name: 'system_operations_status_check'

    add_check_constraint :system_operations,
      "progress >= 0 AND progress <= 100",
      name: 'system_operations_progress_check'

    # ============ System::ProviderVolumeType ============
    create_table :system_provider_volume_types, id: :uuid do |t|
      t.string :name, null: false
      t.text :description
      t.string :volume_type, null: false
      t.integer :min_size_gb, null: false, default: 1
      t.integer :max_size_gb, null: false, default: 16384
      t.integer :min_iops
      t.integer :max_iops
      t.integer :min_throughput
      t.integer :max_throughput
      t.boolean :enabled, null: false, default: true
      t.jsonb :specs, null: false, default: {}
      t.references :provider, null: false, foreign_key: { to_table: :system_providers }, type: :uuid
      t.references :account, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end

    add_index :system_provider_volume_types, [:account_id, :name], unique: true
    add_index :system_provider_volume_types, :volume_type
    add_index :system_provider_volume_types, :enabled
    add_index :system_provider_volume_types, :specs, using: :gin

    add_check_constraint :system_provider_volume_types,
      "volume_type IN ('gp2', 'gp3', 'io1', 'io2', 'st1', 'sc1', 'standard', 'ssd', 'hdd', 'custom')",
      name: 'system_provider_volume_types_type_check'

    # ============ System::ProviderVolume ============
    create_table :system_provider_volumes, id: :uuid do |t|
      t.string :name, null: false
      t.text :description
      t.string :external_id
      t.integer :size_gb, null: false
      t.integer :iops
      t.integer :throughput
      t.string :status, null: false, default: 'creating'
      t.string :device_name
      t.boolean :encrypted, null: false, default: false
      t.boolean :delete_on_termination, null: false, default: false
      t.jsonb :config, null: false, default: {}
      t.references :volume_type, foreign_key: { to_table: :system_provider_volume_types }, type: :uuid
      t.references :provider_region, foreign_key: { to_table: :system_provider_regions }, type: :uuid
      t.references :availability_zone, foreign_key: { to_table: :system_provider_availability_zones }, type: :uuid
      t.references :node_instance, foreign_key: { to_table: :system_node_instances }, type: :uuid
      t.references :account, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end

    add_index :system_provider_volumes, [:account_id, :name], unique: true
    add_index :system_provider_volumes, :external_id
    add_index :system_provider_volumes, :status
    add_index :system_provider_volumes, :encrypted
    add_index :system_provider_volumes, :config, using: :gin

    add_check_constraint :system_provider_volumes,
      "status IN ('creating', 'available', 'in-use', 'deleting', 'deleted', 'error')",
      name: 'system_provider_volumes_status_check'

    # ============ System::ProviderVolumeSnapshot ============
    create_table :system_provider_volume_snapshots, id: :uuid do |t|
      t.string :name, null: false
      t.text :description
      t.string :external_id
      t.integer :size_gb, null: false
      t.string :status, null: false, default: 'pending'
      t.boolean :encrypted, null: false, default: false
      t.integer :progress, null: false, default: 0
      t.jsonb :config, null: false, default: {}
      t.references :volume, foreign_key: { to_table: :system_provider_volumes }, type: :uuid
      t.references :account, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end

    add_index :system_provider_volume_snapshots, [:account_id, :name], unique: true
    add_index :system_provider_volume_snapshots, :external_id
    add_index :system_provider_volume_snapshots, :status
    add_index :system_provider_volume_snapshots, :encrypted
    add_index :system_provider_volume_snapshots, :config, using: :gin

    add_check_constraint :system_provider_volume_snapshots,
      "status IN ('pending', 'creating', 'completed', 'error', 'deleting', 'deleted')",
      name: 'system_provider_volume_snapshots_status_check'

    add_check_constraint :system_provider_volume_snapshots,
      "progress >= 0 AND progress <= 100",
      name: 'system_provider_volume_snapshots_progress_check'

    # ============ System::ProviderNetwork ============
    create_table :system_provider_networks, id: :uuid do |t|
      t.string :name, null: false
      t.text :description
      t.string :external_id
      t.string :cidr_block, null: false
      t.string :status, null: false, default: 'pending'
      t.boolean :is_default, null: false, default: false
      t.boolean :enable_dns_support, null: false, default: true
      t.boolean :enable_dns_hostnames, null: false, default: false
      t.jsonb :config, null: false, default: {}
      t.references :provider, null: false, foreign_key: { to_table: :system_providers }, type: :uuid
      t.references :provider_region, foreign_key: { to_table: :system_provider_regions }, type: :uuid
      t.references :account, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end

    add_index :system_provider_networks, [:account_id, :name], unique: true
    add_index :system_provider_networks, :external_id
    add_index :system_provider_networks, :cidr_block
    add_index :system_provider_networks, :status
    add_index :system_provider_networks, :is_default
    add_index :system_provider_networks, :config, using: :gin

    add_check_constraint :system_provider_networks,
      "status IN ('pending', 'available', 'deleting', 'deleted', 'error')",
      name: 'system_provider_networks_status_check'

    # ============ System::ProviderNetworkSubnet ============
    create_table :system_provider_network_subnets, id: :uuid do |t|
      t.string :name, null: false
      t.text :description
      t.string :external_id
      t.string :cidr_block, null: false
      t.string :status, null: false, default: 'pending'
      t.boolean :is_public, null: false, default: false
      t.boolean :map_public_ip_on_launch, null: false, default: false
      t.integer :available_ip_count
      t.jsonb :config, null: false, default: {}
      t.references :network, null: false, foreign_key: { to_table: :system_provider_networks }, type: :uuid
      t.references :availability_zone, foreign_key: { to_table: :system_provider_availability_zones }, type: :uuid

      t.timestamps
    end

    add_index :system_provider_network_subnets, [:network_id, :name], unique: true
    add_index :system_provider_network_subnets, :external_id
    add_index :system_provider_network_subnets, :cidr_block
    add_index :system_provider_network_subnets, :status
    add_index :system_provider_network_subnets, :is_public
    add_index :system_provider_network_subnets, :config, using: :gin

    add_check_constraint :system_provider_network_subnets,
      "status IN ('pending', 'available', 'deleting', 'deleted', 'error')",
      name: 'system_provider_network_subnets_status_check'

    # ============ System::RegionVolumeType (Join: Region ↔ VolumeType) ============
    create_table :system_region_volume_types, id: :uuid do |t|
      t.references :provider_region, null: false, foreign_key: { to_table: :system_provider_regions }, type: :uuid
      t.references :volume_type, null: false, foreign_key: { to_table: :system_provider_volume_types }, type: :uuid
      t.boolean :enabled, null: false, default: true
      t.jsonb :config, null: false, default: {}

      t.timestamps
    end

    add_index :system_region_volume_types, [:provider_region_id, :volume_type_id], unique: true, name: 'idx_region_volume_types_unique'
    add_index :system_region_volume_types, :enabled
  end
end
