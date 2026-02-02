class ChangeInvitationRolesToJsonb < ActiveRecord::Migration[8.0]
  def up
    # Change role_names from json to jsonb for better performance and indexing
    change_column :invitations, :role_names, :jsonb, default: [ 'member' ], using: 'role_names::jsonb'

    # Add GIN index for jsonb column for faster queries
    add_index :invitations, :role_names, using: :gin
  end

  def down
    # Remove the GIN index
    remove_index :invitations, :role_names

    # Change back to json
    change_column :invitations, :role_names, :json, default: [ 'member' ]
  end
end
