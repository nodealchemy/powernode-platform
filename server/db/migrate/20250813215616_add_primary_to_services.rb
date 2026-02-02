class AddPrimaryToServices < ActiveRecord::Migration[8.0]
  def change
    add_column :services, :primary, :boolean, null: false, default: false
    add_index :services, [ :account_id, :primary ], unique: true, where: '"primary" = true', name: 'index_services_on_account_primary_unique'
  end
end
