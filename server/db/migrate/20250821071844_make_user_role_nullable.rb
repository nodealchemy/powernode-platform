# frozen_string_literal: true

class MakeUserRoleNullable < ActiveRecord::Migration[8.0]
  def change
    # Make role column nullable since roles are now handled through user_roles association
    change_column_null :users, :role, true

    # Also make worker role nullable
    change_column_null :workers, :role, true if column_exists?(:workers, :role)
  end
end
