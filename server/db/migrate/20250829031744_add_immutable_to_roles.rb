class AddImmutableToRoles < ActiveRecord::Migration[8.0]
  def change
    add_column :roles, :immutable, :boolean, default: false, null: false
    
    # Mark super_admin as immutable
    reversible do |direction|
      direction.up do
        execute "UPDATE roles SET immutable = true WHERE name = 'super_admin'"
      end
    end
  end
end
