# frozen_string_literal: true

class UpdateWorkerRoleUserToAccount < ActiveRecord::Migration[8.0]
  def up
    # Update existing 'user' role workers to 'account' role
    execute "UPDATE workers SET role = 'account' WHERE role = 'user'"

    # Change the default value for future records
    change_column_default :workers, :role, 'account'
  end

  def down
    # Revert 'account' role workers back to 'user' role
    execute "UPDATE workers SET role = 'user' WHERE role = 'account'"

    # Change the default value back to 'user'
    change_column_default :workers, :role, 'user'
  end
end
