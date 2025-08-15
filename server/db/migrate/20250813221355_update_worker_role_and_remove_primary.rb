class UpdateWorkerRoleAndRemovePrimary < ActiveRecord::Migration[8.0]
  def change
    # Add role attribute to workers
    add_column :workers, :role, :string, null: false, default: 'user'
    
    # Remove primary column and its index
    remove_index :workers, name: 'index_workers_on_account_primary_unique'
    remove_column :workers, :primary, :boolean
    
    # Add unique index for system role globally
    add_index :workers, :role, unique: true, where: "role = 'system'", name: 'index_workers_on_system_role_unique'
  end
end
