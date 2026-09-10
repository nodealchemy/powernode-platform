# frozen_string_literal: true

module RoleHelpers
  # Permissions are code-defined (the Permissions catalog is the source of
  # truth — there is no Permission AR model to seed). This helper is retained
  # as a no-op for backward compatibility and returns the catalog names that
  # callers may reference. Any name not already in the catalog is registered via
  # the runtime seam so tests can grant it by name.
  def setup_test_permissions
    names = []
    [ 'users', 'accounts', 'analytics' ].each do |resource|
      [ 'create', 'read', 'update', 'delete', 'manage' ].each do |action|
        name = "#{resource}.#{action}"
        Permissions.register_permissions(name => "Test permission") unless Permissions.permission_exists?(name)
        names << name
      end
    end
    names
  end
end

RSpec.configure do |config|
  config.include RoleHelpers
end
