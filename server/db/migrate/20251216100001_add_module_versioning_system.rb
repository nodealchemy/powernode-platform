# frozen_string_literal: true

# Migration for Module Versioning System
# Adds versioning support to System::NodeModule and creates System::NodeModuleVersion
class AddModuleVersioningSystem < ActiveRecord::Migration[8.0]
  def change
    # ============ System::NodeModuleVersion ============
    # Stores historical versions of node modules for rollback capability
    create_table :system_node_module_versions, id: :uuid do |t|
      t.references :node_module, null: false, foreign_key: { to_table: :system_node_modules }, type: :uuid
      t.integer :version_number, null: false
      t.string :data_file_name
      t.string :data_checksum
      t.integer :data_file_size
      t.text :changelog
      t.jsonb :mask, null: false, default: {}
      t.jsonb :file_spec, null: false, default: {}
      t.jsonb :package_spec, null: false, default: {}
      t.jsonb :config, null: false, default: {}
      t.references :created_by, foreign_key: { to_table: :users }, type: :uuid

      t.timestamps
    end

    add_index :system_node_module_versions, [:node_module_id, :version_number], unique: true, name: 'idx_module_versions_unique'
    add_index :system_node_module_versions, :version_number
    add_index :system_node_module_versions, :data_checksum

    # ============ Add versioning fields to System::NodeModule ============
    change_table :system_node_modules do |t|
      # Lock spec prevents updates when true (immutability)
      t.boolean :lock_spec, null: false, default: false

      # Current version tracking
      t.integer :current_version_number, null: false, default: 0
      t.references :current_version, foreign_key: { to_table: :system_node_module_versions }, type: :uuid

      # Package specification (what packages this module provides/requires)
      t.jsonb :package_spec, null: false, default: {}

      # Data file for the module
      t.string :data_file_name
      t.string :data_checksum
      t.integer :data_file_size
    end

    add_index :system_node_modules, :lock_spec
    add_index :system_node_modules, :current_version_number
    add_index :system_node_modules, :package_spec, using: :gin
    add_index :system_node_modules, :data_checksum
  end
end
