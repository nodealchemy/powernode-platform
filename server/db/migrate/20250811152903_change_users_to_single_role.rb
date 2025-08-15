class ChangeUsersToSingleRole < ActiveRecord::Migration[8.0]
  def up
    # Add single role column to users
    add_column :users, :role, :string, limit: 20, null: true
    add_index :users, :role
    
    # Migrate existing user roles to single role
    # Priority: admin > owner > member
    execute <<-SQL
      UPDATE users 
      SET role = (
        CASE 
          WHEN EXISTS (
            SELECT 1 FROM user_roles ur 
            JOIN roles r ON ur.role_id = r.id 
            WHERE ur.user_id = users.id AND r.name = 'Admin'
          ) THEN 'admin'
          WHEN EXISTS (
            SELECT 1 FROM user_roles ur 
            JOIN roles r ON ur.role_id = r.id 
            WHERE ur.user_id = users.id AND r.name = 'Owner'
          ) THEN 'owner'
          WHEN EXISTS (
            SELECT 1 FROM user_roles ur 
            JOIN roles r ON ur.role_id = r.id 
            WHERE ur.user_id = users.id AND r.name = 'Member'
          ) THEN 'member'
          ELSE 'member'
        END
      )
    SQL
    
    # Make role column required after migration
    change_column_null :users, :role, false
    
    # Drop the many-to-many relationship
    drop_table :user_roles
    
    # Update Role model references to remove unused associations
    # Note: Roles table is kept for delegation permissions and future extensibility
  end
  
  def down
    # Recreate user_roles table
    create_table :user_roles, id: { type: :string, limit: 36 } do |t|
      t.string :user_id, limit: 36, null: false
      t.string :role_id, limit: 36, null: false
      t.timestamps
    end
    
    add_index :user_roles, [:user_id, :role_id], unique: true
    add_index :user_roles, :user_id
    add_index :user_roles, :role_id
    
    add_foreign_key :user_roles, :users, column: :user_id
    add_foreign_key :user_roles, :roles, column: :role_id
    
    # Migrate single roles back to user_roles
    execute <<-SQL
      INSERT INTO user_roles (id, user_id, role_id, created_at, updated_at)
      SELECT 
        gen_random_uuid(),
        users.id,
        roles.id,
        users.created_at,
        users.updated_at
      FROM users
      JOIN roles ON roles.name = CASE users.role
        WHEN 'admin' THEN 'Admin'
        WHEN 'owner' THEN 'Owner'
        WHEN 'member' THEN 'Member'
        ELSE 'Member'
      END
      WHERE users.role IS NOT NULL
    SQL
    
    # Remove single role column
    remove_index :users, :role
    remove_column :users, :role
  end
end
