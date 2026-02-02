# frozen_string_literal: true

class UpdateInvitationsToSingleRole < ActiveRecord::Migration[8.0]
  def up
    # Add single role column to invitations
    add_column :invitations, :role, :string, limit: 20, null: true
    add_index :invitations, :role

    # Migrate existing invitation roles to single role
    # Priority: admin > owner > member
    execute <<-SQL
      UPDATE invitations#{' '}
      SET role = (
        CASE#{' '}
          WHEN EXISTS (
            SELECT 1 FROM roles r#{' '}
            WHERE r.id = invitations.role_id AND r.name = 'Admin'
          ) THEN 'admin'
          WHEN EXISTS (
            SELECT 1 FROM roles r#{' '}
            WHERE r.id = invitations.role_id AND r.name = 'Owner'
          ) THEN 'owner'
          WHEN EXISTS (
            SELECT 1 FROM roles r#{' '}
            WHERE r.id = invitations.role_id AND r.name = 'Member'
          ) THEN 'member'
          ELSE 'member'
        END
      )
      WHERE role_id IS NOT NULL
    SQL

    # Set default role for invitations without a role_id
    execute <<-SQL
      UPDATE invitations#{' '}
      SET role = 'member'#{' '}
      WHERE role_id IS NULL
    SQL

    # Make role column required after migration
    change_column_null :invitations, :role, false

    # Remove the role_id foreign key and column
    remove_foreign_key :invitations, :roles, column: :role_id if foreign_key_exists?(:invitations, :roles)
    remove_column :invitations, :role_id
  end

  def down
    # Add role_id column back
    add_column :invitations, :role_id, :string, limit: 36, null: true
    add_foreign_key :invitations, :roles, column: :role_id

    # Migrate single roles back to role_id
    execute <<-SQL
      UPDATE invitations#{' '}
      SET role_id = (
        SELECT roles.id FROM roles#{' '}
        WHERE roles.name = CASE invitations.role
          WHEN 'admin' THEN 'Admin'
          WHEN 'owner' THEN 'Owner'
          WHEN 'member' THEN 'Member'
          ELSE 'Member'
        END
      )
      WHERE role IS NOT NULL
    SQL

    # Remove single role column
    remove_index :invitations, :role
    remove_column :invitations, :role
  end
end
