class RenameServicesToWorkers < ActiveRecord::Migration[8.0]
  def change
    rename_table :services, :workers
    rename_table :service_activities, :worker_activities
    
    # Update foreign key column names
    rename_column :worker_activities, :service_id, :worker_id
    
    # Update any index names if needed
    rename_index :workers, 'index_services_on_account_primary_unique', 'index_workers_on_account_primary_unique'
  end
end
