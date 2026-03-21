# frozen_string_literal: true

# Consolidated migration for Powernode System - Node Core
# Combines: node_architectures, node_platforms, node_scripts, node_templates, nodes, node_instances
class CreatePowernodeSystemNodeCore < ActiveRecord::Migration[8.0]
  def change
    # ============ System::NodeArchitecture ============
    create_table :system_node_architectures, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true

      # Core fields
      t.string :name, null: false
      t.text :description
      t.text :kernel_options

      # Status flags
      t.boolean :enabled, null: false, default: true
      t.boolean :public, null: false, default: false

      # File attachments via FileObject
      t.references :kernel_file_object, type: :uuid, foreign_key: { to_table: :file_objects }
      t.references :ramdisk_file_object, type: :uuid, foreign_key: { to_table: :file_objects }
      t.references :image_file_object, type: :uuid, foreign_key: { to_table: :file_objects }

      t.timestamps

      t.index [:account_id, :name], unique: true
      t.index [:account_id, :enabled]
      t.index [:account_id, :public]
    end

    # ============ System::NodePlatform ============
    create_table :system_node_platforms, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :node_architecture, type: :uuid, null: false,
                   foreign_key: { to_table: :system_node_architectures }

      # Core fields
      t.string :name, null: false
      t.text :description

      # Status flags
      t.boolean :enabled, null: false, default: true
      t.boolean :public, null: false, default: false

      # Scripts (text for inline storage)
      t.text :build_script
      t.text :init_script
      t.text :sync_script

      t.timestamps

      t.index [:account_id, :name], unique: true
      t.index [:account_id, :enabled]
      t.index [:account_id, :public]
    end

    # ============ System::NodeScript ============
    create_table :system_node_scripts, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true

      # Core fields
      t.string :name, null: false
      t.text :description
      t.string :variety, null: false, default: 'custom'
      t.text :data

      # Status flags
      t.boolean :enabled, null: false, default: true
      t.boolean :public, null: false, default: false

      t.timestamps

      t.index [:account_id, :name], unique: true
      t.index [:account_id, :variety]
      t.index [:account_id, :enabled]
      t.index [:account_id, :public]
    end

    add_check_constraint :system_node_scripts,
      "variety IN ('build', 'init', 'sync', 'custom')",
      name: 'system_node_scripts_variety_check'

    # ============ System::NodeTemplate ============
    create_table :system_node_templates, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :node_platform, type: :uuid, null: false,
                   foreign_key: { to_table: :system_node_platforms }

      # Core fields
      t.string :name, null: false
      t.text :description
      t.string :admin_user

      # Configuration
      t.jsonb :config, null: false, default: {}

      # Status flags
      t.boolean :enabled, null: false, default: true
      t.boolean :public, null: false, default: false

      t.timestamps

      t.index [:account_id, :name], unique: true
      t.index [:account_id, :enabled]
      t.index [:account_id, :public]
      t.index :config, using: :gin
    end

    # ============ System::Node ============
    create_table :system_nodes, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :node_template, type: :uuid, null: false,
                   foreign_key: { to_table: :system_node_templates }
      t.references :worker, type: :uuid, foreign_key: true

      # Core fields
      t.string :name, null: false
      t.text :description

      # Configuration
      t.jsonb :config, null: false, default: {}

      # SSH credentials (encrypted at application level)
      t.text :ssh_key_ciphertext
      t.text :ssh_host_key_ciphertext

      # Networking
      t.string :public_address
      t.boolean :allocate_public_ip, null: false, default: false

      # Status flags
      t.boolean :enabled, null: false, default: true

      t.timestamps

      t.index [:account_id, :name], unique: true
      t.index [:account_id, :enabled]
      t.index :config, using: :gin
    end

    # ============ System::NodeInstance ============
    create_table :system_node_instances, id: :uuid do |t|
      t.references :node, type: :uuid, null: false,
                   foreign_key: { to_table: :system_nodes }
      # Provider references added in providers migration
      t.references :provider_region, type: :uuid
      t.references :provider_instance_type, type: :uuid

      # Core fields
      t.string :name, null: false
      t.text :description
      t.string :variety, null: false, default: 'cloud'
      t.string :status, null: false, default: 'pending'

      # Configuration
      t.jsonb :config, null: false, default: {}

      # Instance key (encrypted at application level)
      t.text :key_ciphertext

      # Networking
      t.string :private_ip_address
      t.string :public_ip_address
      t.string :vpn_ip_address

      t.timestamps

      t.index [:node_id, :name], unique: true
      t.index [:node_id, :status]
      t.index [:node_id, :variety]
      t.index [:provider_region_id, :status]
      t.index :config, using: :gin
    end

    add_check_constraint :system_node_instances,
      "variety IN ('cloud', 'physical', 'dynamic')",
      name: 'system_node_instances_variety_check'

    add_check_constraint :system_node_instances,
      "status IN ('pending', 'provisioning', 'running', 'stopped', 'terminated', 'error')",
      name: 'system_node_instances_status_check'
  end
end
