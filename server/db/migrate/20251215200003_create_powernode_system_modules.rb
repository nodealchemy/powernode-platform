# frozen_string_literal: true

# Consolidated migration for Powernode System - Modules
# Combines: node_module_categories, node_module_copy_paths, node_modules, node_module_assignments,
#           module_dependencies, template_modules, node_mount_points, instance_mount_points
class CreatePowernodeSystemModules < ActiveRecord::Migration[8.0]
  def change
    # ============ System::NodeModuleCategory ============
    create_table :system_node_module_categories, id: :uuid do |t|
      t.string :name, null: false
      t.text :description
      t.boolean :enabled, null: false, default: true
      t.boolean :public, null: false, default: false
      t.string :icon
      t.string :color
      t.integer :position, null: false, default: 0
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :parent, foreign_key: { to_table: :system_node_module_categories }, type: :uuid

      t.timestamps
    end

    add_index :system_node_module_categories, [:account_id, :name], unique: true
    add_index :system_node_module_categories, :enabled
    add_index :system_node_module_categories, :public
    add_index :system_node_module_categories, :position

    # ============ System::NodeModuleCopyPath ============
    create_table :system_node_module_copy_paths, id: :uuid do |t|
      t.string :name, null: false
      t.text :description
      t.string :source_path, null: false
      t.string :destination_path, null: false
      t.boolean :enabled, null: false, default: true
      t.boolean :recursive, null: false, default: false
      t.boolean :preserve_permissions, null: false, default: true
      t.references :account, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end

    add_index :system_node_module_copy_paths, [:account_id, :name], unique: true
    add_index :system_node_module_copy_paths, :enabled

    # ============ System::NodeModule ============
    create_table :system_node_modules, id: :uuid do |t|
      t.string :name, null: false
      t.text :description
      t.string :variety, null: false, default: 'config'
      t.boolean :enabled, null: false, default: true
      t.boolean :public, null: false, default: false
      t.integer :priority, null: false, default: 0
      t.jsonb :mask, null: false, default: {}
      t.jsonb :file_spec, null: false, default: {}
      t.jsonb :config, null: false, default: {}
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :node_platform, foreign_key: { to_table: :system_node_platforms }, type: :uuid
      t.references :category, foreign_key: { to_table: :system_node_module_categories }, type: :uuid
      t.references :copy_path, foreign_key: { to_table: :system_node_module_copy_paths }, type: :uuid

      t.timestamps
    end

    add_index :system_node_modules, [:account_id, :name], unique: true
    add_index :system_node_modules, :variety
    add_index :system_node_modules, :enabled
    add_index :system_node_modules, :public
    add_index :system_node_modules, :priority
    add_index :system_node_modules, :mask, using: :gin
    add_index :system_node_modules, :file_spec, using: :gin
    add_index :system_node_modules, :config, using: :gin

    add_check_constraint :system_node_modules,
      "variety IN ('config', 'instance', 'subscription')",
      name: 'system_node_modules_variety_check'

    # ============ System::NodeModuleAssignment (Join: Node ↔ Module) ============
    create_table :system_node_module_assignments, id: :uuid do |t|
      t.references :node, null: false, foreign_key: { to_table: :system_nodes }, type: :uuid
      t.references :node_module, null: false, foreign_key: { to_table: :system_node_modules }, type: :uuid
      t.jsonb :config, null: false, default: {}
      t.boolean :enabled, null: false, default: true
      t.integer :priority, null: false, default: 0

      t.timestamps
    end

    add_index :system_node_module_assignments, [:node_id, :node_module_id], unique: true, name: 'idx_node_module_assignments_unique'
    add_index :system_node_module_assignments, :enabled
    add_index :system_node_module_assignments, :priority
    add_index :system_node_module_assignments, :config, using: :gin

    # ============ System::ModuleDependency (Join: Module ↔ Module self-ref) ============
    create_table :system_module_dependencies, id: :uuid do |t|
      t.references :node_module, null: false, foreign_key: { to_table: :system_node_modules }, type: :uuid
      t.references :dependency, null: false, foreign_key: { to_table: :system_node_modules }, type: :uuid
      t.string :dependency_type, null: false, default: 'requires'
      t.boolean :required, null: false, default: true
      t.string :version_constraint

      t.timestamps
    end

    add_index :system_module_dependencies, [:node_module_id, :dependency_id], unique: true, name: 'idx_module_dependencies_unique'
    add_index :system_module_dependencies, :dependency_type

    add_check_constraint :system_module_dependencies,
      "dependency_type IN ('requires', 'recommends', 'conflicts', 'provides')",
      name: 'system_module_dependencies_type_check'

    # ============ System::TemplateModule (Join: Template ↔ Module) ============
    create_table :system_template_modules, id: :uuid do |t|
      t.references :node_template, null: false, foreign_key: { to_table: :system_node_templates }, type: :uuid
      t.references :node_module, null: false, foreign_key: { to_table: :system_node_modules }, type: :uuid
      t.jsonb :config, null: false, default: {}
      t.boolean :enabled, null: false, default: true
      t.integer :priority, null: false, default: 0

      t.timestamps
    end

    add_index :system_template_modules, [:node_template_id, :node_module_id], unique: true, name: 'idx_template_modules_unique'
    add_index :system_template_modules, :enabled
    add_index :system_template_modules, :priority
    add_index :system_template_modules, :config, using: :gin

    # ============ System::NodeMountPoint ============
    create_table :system_node_mount_points, id: :uuid do |t|
      t.string :name, null: false
      t.text :description
      t.string :mount_path, null: false
      t.string :mount_type, null: false, default: 'nfs'
      t.string :source
      t.jsonb :options, null: false, default: {}
      t.boolean :enabled, null: false, default: true
      t.boolean :auto_mount, null: false, default: true
      t.references :account, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end

    add_index :system_node_mount_points, [:account_id, :name], unique: true
    add_index :system_node_mount_points, :mount_type
    add_index :system_node_mount_points, :enabled
    add_index :system_node_mount_points, :options, using: :gin

    add_check_constraint :system_node_mount_points,
      "mount_type IN ('nfs', 'cifs', 'tmpfs', 'bind', 'efs', 'ebs', 'custom')",
      name: 'system_node_mount_points_type_check'

    # ============ System::InstanceMountPoint (Join: Instance ↔ MountPoint) ============
    create_table :system_instance_mount_points, id: :uuid do |t|
      t.references :node_instance, null: false, foreign_key: { to_table: :system_node_instances }, type: :uuid
      t.references :mount_point, null: false, foreign_key: { to_table: :system_node_mount_points }, type: :uuid
      t.jsonb :config, null: false, default: {}
      t.boolean :enabled, null: false, default: true
      t.string :status, null: false, default: 'pending'

      t.timestamps
    end

    add_index :system_instance_mount_points, [:node_instance_id, :mount_point_id], unique: true, name: 'idx_instance_mount_points_unique'
    add_index :system_instance_mount_points, :enabled
    add_index :system_instance_mount_points, :status
    add_index :system_instance_mount_points, :config, using: :gin

    add_check_constraint :system_instance_mount_points,
      "status IN ('pending', 'mounted', 'unmounted', 'error')",
      name: 'system_instance_mount_points_status_check'
  end
end
