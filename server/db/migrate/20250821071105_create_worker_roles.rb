# frozen_string_literal: true

class CreateWorkerRoles < ActiveRecord::Migration[8.0]
  def change
    # Create join table for many-to-many relationship between workers and roles
    create_table :worker_roles, id: :string, limit: 36 do |t|
      t.string :worker_id, null: false, limit: 36
      t.string :role_id, null: false, limit: 36
      
      # Track who assigned the role and when
      t.string :assigned_by_id, limit: 36
      t.datetime :assigned_at
      
      # Optional expiration for temporary roles
      t.datetime :expires_at
      
      t.timestamps
    end
    
    # Add indexes for performance
    add_index :worker_roles, :worker_id
    add_index :worker_roles, :role_id
    add_index :worker_roles, [:worker_id, :role_id], unique: true, name: 'index_worker_roles_on_worker_and_role'
    add_index :worker_roles, :expires_at
    
    # Add foreign key constraints
    add_foreign_key :worker_roles, :workers
    add_foreign_key :worker_roles, :roles
    add_foreign_key :worker_roles, :users, column: :assigned_by_id
    
    # Remove old permissions column from workers (replaced by roles)
    remove_column :workers, :permissions if column_exists?(:workers, :permissions)
    
    # Keep role column for now but it will be replaced by worker_roles
    add_column :workers, :legacy_role, :string unless column_exists?(:workers, :legacy_role)
    execute "UPDATE workers SET legacy_role = role WHERE legacy_role IS NULL" if column_exists?(:workers, :role)
  end
end