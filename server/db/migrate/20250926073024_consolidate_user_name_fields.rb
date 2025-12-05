# frozen_string_literal: true

class ConsolidateUserNameFields < ActiveRecord::Migration[8.0]
  def up
    # Add the new name column
    add_column :users, :name, :string, null: false, default: ''

    # Migrate existing data: combine first_name and last_name into name
    User.reset_column_information
    User.find_each do |user|
      full_name = "#{user.first_name} #{user.last_name}".strip
      user.update_column(:name, full_name)
    end

    # Remove the old columns
    remove_column :users, :first_name
    remove_column :users, :last_name

    # Add validation constraint (this will be handled in the model)
    # The default empty string will be handled by model validations
  end

  def down
    # Add back the old columns
    add_column :users, :first_name, :string
    add_column :users, :last_name, :string

    # Migrate data back: split name into first_name and last_name
    User.reset_column_information
    User.find_each do |user|
      name_parts = user.name.to_s.split(' ', 2)
      first_name = name_parts[0] || ''
      last_name = name_parts[1] || ''

      user.update_columns(
        first_name: first_name,
        last_name: last_name
      )
    end

    # Remove the name column
    remove_column :users, :name

    # Add not null constraints to the restored columns
    change_column_null :users, :first_name, false
    change_column_null :users, :last_name, false
  end
end
