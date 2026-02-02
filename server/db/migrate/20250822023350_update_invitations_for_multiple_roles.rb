class UpdateInvitationsForMultipleRoles < ActiveRecord::Migration[8.0]
  def change
    # Remove single role column and add JSON array for multiple roles
    remove_column :invitations, :role, :string if column_exists?(:invitations, :role)
    add_column :invitations, :role_names, :json, default: [ 'member' ]

    # No GIN index for JSON column - PostgreSQL doesn't support it directly
    # We could use jsonb instead if we need indexing
  end
end
