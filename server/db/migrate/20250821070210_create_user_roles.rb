# frozen_string_literal: true

class CreateUserRoles < ActiveRecord::Migration[8.0]
  def change
    # Create join table for many-to-many relationship between users and roles
    create_table :user_roles, id: :string, limit: 36 do |t|
      t.string :user_id, null: false, limit: 36
      t.string :role_id, null: false, limit: 36
      
      # Track who assigned the role and when
      t.string :assigned_by_id, limit: 36
      t.datetime :assigned_at
      
      # Optional expiration for temporary roles
      t.datetime :expires_at
      
      # Optional context/scope for role (e.g., specific account or resource)
      t.string :context_type
      t.string :context_id, limit: 36
      
      t.timestamps
    end
    
    # Add indexes for performance
    add_index :user_roles, :user_id
    add_index :user_roles, :role_id
    add_index :user_roles, [:user_id, :role_id], unique: true, name: 'index_user_roles_on_user_and_role'
    add_index :user_roles, :expires_at
    add_index :user_roles, [:context_type, :context_id]
    
    # Add foreign key constraints
    add_foreign_key :user_roles, :users
    add_foreign_key :user_roles, :roles
    add_foreign_key :user_roles, :users, column: :assigned_by_id
    
    # Preserve existing single role column during migration
    # This will be removed after all users are migrated
    add_column :users, :legacy_role, :string unless column_exists?(:users, :legacy_role)
    execute "UPDATE users SET legacy_role = role WHERE legacy_role IS NULL" if column_exists?(:users, :role)
    
    # Track migration status
    add_column :users, :migrated_to_multi_role, :boolean, default: false, null: false unless column_exists?(:users, :migrated_to_multi_role)
    add_index :users, :migrated_to_multi_role unless index_exists?(:users, :migrated_to_multi_role)
  end
end
