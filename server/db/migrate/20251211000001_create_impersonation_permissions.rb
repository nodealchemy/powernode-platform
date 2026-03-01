# frozen_string_literal: true

class CreateImpersonationPermissions < ActiveRecord::Migration[8.0]
  def up
    # Create impersonation permissions
    impersonate_permission = Permission.find_or_create_by!(
      resource: 'users',
      action: 'impersonate'
    ) do |permission|
      permission.name = 'users.impersonate'
      permission.description = 'Can impersonate other users in the same account'
    end

    view_impersonation_permission = Permission.find_or_create_by!(
      resource: 'impersonation',
      action: 'view'
    ) do |permission|
      permission.name = 'impersonation.view'
      permission.description = 'Can view impersonation history and logs'
    end

    # Assign impersonation permissions to Owner and Admin roles
    owner_role = Role.find_by(name: 'Owner')
    admin_role = Role.find_by(name: 'Admin')

    if owner_role
      owner_role.add_permission(impersonate_permission)
      owner_role.add_permission(view_impersonation_permission)
    end

    if admin_role
      admin_role.add_permission(impersonate_permission)
      admin_role.add_permission(view_impersonation_permission)
    end
  end

  def down
    Permission.where(
      resource: [ 'users', 'impersonation' ],
      action: [ 'impersonate', 'view' ]
    ).destroy_all
  end
end
