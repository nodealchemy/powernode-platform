# frozen_string_literal: true

# Consolidated migration for Powernode System - Puppet Configuration Management
# Combines: puppet_modules, puppet_resources, module_puppet_assignments
class CreatePowernodeSystemPuppet < ActiveRecord::Migration[8.0]
  def change
    # ============ System::PuppetModule ============
    create_table :system_puppet_modules, id: :uuid do |t|
      t.string :name, null: false
      t.text :description
      t.boolean :enabled, null: false, default: true
      t.boolean :public, null: false, default: false
      t.string :version
      t.string :author
      t.string :license
      t.string :source_url
      t.string :project_url
      t.string :forge_name
      t.jsonb :dependencies, null: false, default: []
      t.jsonb :config, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.references :account, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end

    add_index :system_puppet_modules, [:account_id, :name], unique: true
    add_index :system_puppet_modules, :enabled
    add_index :system_puppet_modules, :public
    add_index :system_puppet_modules, :forge_name
    add_index :system_puppet_modules, :dependencies, using: :gin
    add_index :system_puppet_modules, :config, using: :gin
    add_index :system_puppet_modules, :metadata, using: :gin

    # ============ System::PuppetResource ============
    create_table :system_puppet_resources, id: :uuid do |t|
      t.string :name, null: false
      t.text :description
      t.string :resource_type, null: false
      t.string :title
      t.string :path
      t.text :data
      t.boolean :enabled, null: false, default: true
      t.boolean :exported, null: false, default: false
      t.jsonb :parameters, null: false, default: {}
      t.jsonb :config, null: false, default: {}
      t.references :puppet_module, null: false, foreign_key: { to_table: :system_puppet_modules }, type: :uuid

      t.timestamps
    end

    add_index :system_puppet_resources, [:puppet_module_id, :name], unique: true
    add_index :system_puppet_resources, :resource_type
    add_index :system_puppet_resources, :enabled
    add_index :system_puppet_resources, :exported
    add_index :system_puppet_resources, :parameters, using: :gin
    add_index :system_puppet_resources, :config, using: :gin

    add_check_constraint :system_puppet_resources,
      "resource_type IN ('file', 'package', 'service', 'exec', 'user', 'group', 'cron', 'mount', 'host', 'notify', 'class', 'define', 'custom')",
      name: 'system_puppet_resources_type_check'

    # ============ System::ModulePuppetAssignment (Join: NodeModule ↔ PuppetModule) ============
    create_table :system_module_puppet_assignments, id: :uuid do |t|
      t.references :node_module, null: false, foreign_key: { to_table: :system_node_modules }, type: :uuid
      t.references :puppet_module, null: false, foreign_key: { to_table: :system_puppet_modules }, type: :uuid
      t.jsonb :config, null: false, default: {}
      t.jsonb :parameters, null: false, default: {}
      t.boolean :enabled, null: false, default: true
      t.integer :priority, null: false, default: 0

      t.timestamps
    end

    add_index :system_module_puppet_assignments, [:node_module_id, :puppet_module_id], unique: true, name: 'idx_module_puppet_assignments_unique'
    add_index :system_module_puppet_assignments, :enabled
    add_index :system_module_puppet_assignments, :priority
    add_index :system_module_puppet_assignments, :config, using: :gin
    add_index :system_module_puppet_assignments, :parameters, using: :gin
  end
end
