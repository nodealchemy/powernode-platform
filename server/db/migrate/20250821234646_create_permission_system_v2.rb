# frozen_string_literal: true

class CreatePermissionSystemV2 < ActiveRecord::Migration[8.0]
  def change
    # Drop old permission-related tables and columns if they exist
    remove_column :users, :role, if_exists: true
    remove_column :users, :permissions, if_exists: true
    remove_column :workers, :role, if_exists: true

    # Drop foreign key constraints that reference roles table
    if foreign_key_exists?(:account_delegations, :roles)
      remove_foreign_key :account_delegations, :roles
    end

    if foreign_key_exists?(:role_permissions, :roles)
      remove_foreign_key :role_permissions, :roles
    end

    # Drop old tables
    drop_table :user_roles, if_exists: true, force: :cascade
    drop_table :worker_roles, if_exists: true, force: :cascade
    drop_table :role_permissions, if_exists: true, force: :cascade
    drop_table :permissions, if_exists: true, force: :cascade
    drop_table :roles, if_exists: true, force: :cascade

    # Create new permissions table
    create_table :permissions, id: false do |t|
      t.string :id, limit: 36, primary_key: true, default: -> { 'gen_random_uuid()' }
      t.string :name, limit: 100, null: false
      t.string :category, limit: 20, null: false
      t.string :resource, limit: 50, null: false
      t.string :action, limit: 50, null: false
      t.text :description
      t.timestamps null: false

      t.index :name, unique: true
      t.index :category
      t.index [ :resource, :action ]
    end

    # Add check constraint for category
    execute <<-SQL
      ALTER TABLE permissions#{' '}
      ADD CONSTRAINT check_permission_category#{' '}
      CHECK (category IN ('resource', 'admin', 'system'))
    SQL

    # Create new roles table
    create_table :roles, id: false do |t|
      t.string :id, limit: 36, primary_key: true, default: -> { 'gen_random_uuid()' }
      t.string :name, limit: 50, null: false
      t.string :display_name, limit: 100, null: false
      t.text :description
      t.string :role_type, limit: 20, null: false
      t.boolean :is_system, default: false, null: false
      t.timestamps null: false

      t.index :name, unique: true
      t.index :role_type
      t.index :is_system
    end

    # Add check constraint for role_type
    execute <<-SQL
      ALTER TABLE roles#{' '}
      ADD CONSTRAINT check_role_type#{' '}
      CHECK (role_type IN ('user', 'admin', 'system'))
    SQL

    # Create role_permissions junction table
    create_table :role_permissions, id: false do |t|
      t.string :role_id, limit: 36, null: false
      t.string :permission_id, limit: 36, null: false
      t.timestamp :created_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }

      t.index [ :role_id, :permission_id ], unique: true
      t.index :permission_id
    end

    # Create user_roles junction table
    create_table :user_roles, id: false do |t|
      t.string :user_id, limit: 36, null: false
      t.string :role_id, limit: 36, null: false
      t.string :granted_by, limit: 36
      t.timestamp :granted_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }

      t.index [ :user_id, :role_id ], unique: true
      t.index :role_id
      t.index :granted_by
    end

    # Create worker_roles junction table
    create_table :worker_roles, id: false do |t|
      t.string :worker_id, limit: 36, null: false
      t.string :role_id, limit: 36, null: false
      t.timestamp :granted_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }

      t.index [ :worker_id, :role_id ], unique: true
      t.index :role_id
    end

    # Add foreign key constraints
    add_foreign_key :role_permissions, :roles, column: :role_id
    add_foreign_key :role_permissions, :permissions, column: :permission_id
    add_foreign_key :user_roles, :users, column: :user_id
    add_foreign_key :user_roles, :roles, column: :role_id
    add_foreign_key :user_roles, :users, column: :granted_by
    add_foreign_key :worker_roles, :workers, column: :worker_id
    add_foreign_key :worker_roles, :roles, column: :role_id

    # Create indexes for performance
    add_index :user_roles, :user_id
    add_index :worker_roles, :worker_id

    # Add trigger to update updated_at for junction tables (optional)
    execute <<-SQL
      CREATE OR REPLACE FUNCTION update_updated_at_column()
      RETURNS TRIGGER AS $$
      BEGIN
        NEW.updated_at = NOW();
        RETURN NEW;
      END;
      $$ language 'plpgsql';
    SQL

    execute <<-SQL
      CREATE TRIGGER update_permissions_updated_at BEFORE UPDATE ON permissions
        FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
    SQL

    execute <<-SQL
      CREATE TRIGGER update_roles_updated_at BEFORE UPDATE ON roles
        FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
    SQL
  end
end
