class RemoveLegacyRoleFromWorkers < ActiveRecord::Migration[8.0]
  def change
    remove_column :workers, :legacy_role, :string
  end
end
