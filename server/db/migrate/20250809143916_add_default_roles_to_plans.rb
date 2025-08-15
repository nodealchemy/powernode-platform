class AddDefaultRolesToPlans < ActiveRecord::Migration[8.0]
  def change
    add_column :plans, :default_roles, :text
  end
end
