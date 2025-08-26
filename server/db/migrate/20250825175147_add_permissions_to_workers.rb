class AddPermissionsToWorkers < ActiveRecord::Migration[8.0]
  def change
    add_column :workers, :permissions, :jsonb, default: []
    add_index :workers, :permissions, using: :gin
  end
end
