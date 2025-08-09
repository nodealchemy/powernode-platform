class CreateRolesAndPermissions < ActiveRecord::Migration[8.0]
  def change
    # Create roles table
    create_table :roles, id: false do |t|
      t.string :id, primary_key: true, null: false, limit: 36
      t.string :name, null: false, limit: 50
      t.string :description, limit: 255
      t.boolean :system_role, default: false, null: false
      t.timestamps null: false
      
      t.index [:name], unique: true
      t.index [:system_role]
    end

    # Create permissions table
    create_table :permissions, id: false do |t|
      t.string :id, primary_key: true, null: false, limit: 36
      t.string :name, limit: 100
      t.string :resource, null: false, limit: 50
      t.string :action, null: false, limit: 50
      t.string :description, limit: 255
      t.timestamps null: false
      
      t.index [:name], unique: true, where: "name IS NOT NULL"
      t.index [:resource, :action], unique: true
      t.index [:resource]
      t.index [:action]
    end

    # Create role_permissions join table
    create_table :role_permissions, id: false do |t|
      t.string :id, primary_key: true, null: false, limit: 36
      t.string :role_id, null: false, limit: 36
      t.string :permission_id, null: false, limit: 36
      t.timestamps null: false
      
      t.foreign_key :roles, column: :role_id
      t.foreign_key :permissions, column: :permission_id
      t.index [:role_id]
      t.index [:permission_id]
      t.index [:role_id, :permission_id], unique: true
    end

    # Create user_roles join table
    create_table :user_roles, id: false do |t|
      t.string :id, primary_key: true, null: false, limit: 36
      t.string :user_id, null: false, limit: 36
      t.string :role_id, null: false, limit: 36
      t.timestamps null: false
      
      t.foreign_key :users, column: :user_id
      t.foreign_key :roles, column: :role_id
      t.index [:user_id]
      t.index [:role_id]
      t.index [:user_id, :role_id], unique: true
    end
  end
end