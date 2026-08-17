# frozen_string_literal: true

# Permission Test Helpers
#
# Provides convenient methods for creating users with specific permissions
# during tests. These helpers work with the existing FactoryBot factories
# and permission system.
#
# Usage:
#   let(:admin) { admin_user }
#   let(:user_with_billing) { user_with_permissions('billing.read', 'billing.update') }
#
module PermissionTestHelpers
  # =============================================================================
  # USER CREATION WITH PERMISSIONS
  # =============================================================================

  # Create a user with specific permissions
  # @param permission_names [Array<String>] Permission names (e.g., 'users.read', 'billing.manage')
  # @param options [Hash] Additional options for user creation
  # @option options [Account] :account The account for the user
  # @option options [String] :email Custom email
  # @option options [String] :first_name Custom first name
  # @return [User] Created user with specified permissions
  def user_with_permissions(*permission_names, **options)
    account = options.delete(:account) || create(:account)
    permissions = permission_names.flatten.compact

    create(:user, account: account, permissions: permissions, **options)
  end

  # Create a user without any permissions
  # @param options [Hash] Additional options for user creation
  # @return [User] Created user with no permissions
  def user_without_permissions(**options)
    account = options.delete(:account) || create(:account)
    create(:user, account: account, permissions: [], **options)
  end

  # =============================================================================
  # PREDEFINED USER TYPES
  # =============================================================================

  # Create an admin user with full system access
  # @param options [Hash] Additional options for user creation
  # @return [User] Admin user
  def admin_user(**options)
    account = options.delete(:account) || create(:account)
    create(:user, :admin, account: account, **options)
  end

  # Create an owner user (account owner with full account access)
  # @param options [Hash] Additional options for user creation
  # @return [User] Owner user
  def owner_user(**options)
    account = options.delete(:account) || create(:account)
    owner_permissions = %w[
      accounts.read accounts.manage
      users.read users.create users.update users.delete users.manage
      admin.role.read admin.role.create admin.role.update admin.role.delete
      analytics.read
      audit.read
      admin.settings.read admin.settings.update
    ]
    create(:user, account: account, permissions: owner_permissions, **options)
  end

  # Create a manager user (team/department manager)
  # @param options [Hash] Additional options for user creation
  # @return [User] Manager user
  def manager_user(**options)
    account = options.delete(:account) || create(:account)
    manager_permissions = %w[
      users.read users.create users.update
      analytics.read
      admin.settings.read
    ]
    create(:user, account: account, permissions: manager_permissions, **options)
  end

  # Create a member user (basic account member)
  # @param options [Hash] Additional options for user creation
  # @return [User] Member user
  def member_user(**options)
    account = options.delete(:account) || create(:account)
    member_permissions = %w[
      accounts.read
      users.read
    ]
    create(:user, account: account, permissions: member_permissions, **options)
  end

  # Create a billing admin user
  # @param options [Hash] Additional options for user creation
  # @return [User] Billing admin user
  def billing_admin_user(**options)
    account = options.delete(:account) || create(:account)
    billing_permissions = %w[
      billing.read billing.create billing.update billing.delete billing.manage
      payments.read payments.create
      invoices.read invoices.create
      subscriptions.read subscriptions.update
    ]
    create(:user, account: account, permissions: billing_permissions, **options)
  end

  # =============================================================================
  # AI-SPECIFIC USER TYPES
  # =============================================================================

  # Create a user with AI workflow permissions
  # @param options [Hash] Additional options for user creation
  # @return [User] AI workflow user
  def ai_workflow_user(**options)
    account = options.delete(:account) || create(:account)
    ai_permissions = %w[
      ai.loops.read ai.loops.create ai.loops.update ai.loops.delete ai.loops.execute
      ai.agents.read ai.agents.create ai.agents.update ai.agents.execute
      ai.conversations.read ai.conversations.create ai.conversations.update
      ai.providers.read
    ]
    create(:user, account: account, permissions: ai_permissions, **options)
  end

  # Create a user with AI read-only permissions
  # @param options [Hash] Additional options for user creation
  # @return [User] AI viewer user
  def ai_viewer_user(**options)
    account = options.delete(:account) || create(:account)
    ai_read_permissions = %w[
      ai.loops.read
      ai.agents.read
      ai.conversations.read
      ai.providers.read
      ai.analytics.read
    ]
    create(:user, account: account, permissions: ai_read_permissions, **options)
  end

  # =============================================================================
  # DEVOPS USER TYPES
  # =============================================================================

  # Create a user with DevOps/CI-CD permissions
  # @param options [Hash] Additional options for user creation
  # @return [User] DevOps user
  def devops_user(**options)
    account = options.delete(:account) || create(:account)
    devops_permissions = %w[
      devops.pipelines.read devops.pipelines.write
      devops.pipeline_runs.read devops.pipeline_runs.write
      devops.providers.read devops.providers.write
      devops.repositories.read devops.repositories.write
      git.providers.read git.providers.create
    ]
    create(:user, account: account, permissions: devops_permissions, **options)
  end

  # =============================================================================
  # PERMISSION ASSERTIONS
  # =============================================================================

  # Assert that a user has a specific permission
  # @param user [User] The user to check
  # @param permission [String] Permission name to check
  def assert_has_permission(user, permission)
    expect(user.has_permission?(permission)).to be(true),
      "Expected user to have permission '#{permission}' but they don't.\n" \
      "User permissions: #{user.permission_names.join(', ')}"
  end

  # Assert that a user does not have a specific permission
  # @param user [User] The user to check
  # @param permission [String] Permission name to check
  def assert_lacks_permission(user, permission)
    expect(user.has_permission?(permission)).to be(false),
      "Expected user to NOT have permission '#{permission}' but they do."
  end

  # =============================================================================
  # PERMISSION SETUP HELPERS
  # =============================================================================

  # Ensure common test permissions exist in the catalog.
  #
  # Permissions are code-defined (the Permissions catalog is the source of
  # truth — there is no Permission AR model). Real catalog permissions already
  # exist; any name here that isn't in the catalog is registered through the
  # runtime seam so it can be granted by name. Call this in a before block when
  # a spec relies on these names being grantable.
  def ensure_test_permissions_exist
    permission_sets = {
      'users' => %w[read create update delete manage],
      'accounts' => %w[read manage],
      'analytics' => %w[read],
      'audit' => %w[read export],
      'admin.role' => %w[read create update delete assign],
      'ai.workflows' => %w[read create update delete execute export],
      'ai.agents' => %w[read create update delete execute],
      'ai.conversations' => %w[read create update delete manage participate],
      'ai.providers' => %w[read create update delete test],
      'ai.analytics' => %w[read],
      'devops.pipelines' => %w[read write],
      'git.providers' => %w[read create update delete],
      'admin' => %w[access]
    }

    permission_sets.each do |resource, actions|
      actions.each do |action|
        name = "#{resource}.#{action}"
        Permissions.register_permissions(name => "Test permission") unless Permissions.permission_exists?(name)
      end
    end
  end

  # Grant additional permissions to an existing user, by NAME, through a role.
  # @param user [User] The user to grant permissions to
  # @param permission_names [Array<String>] Catalog permission names to grant
  def grant_permissions(user, *permission_names)
    permission_names.flatten.each do |name|
      next if user.has_permission?(name)

      # Auto-register ad-hoc names so the catalog-membership validation passes.
      Permissions.register_permissions(name => "Test permission") unless Permissions.permission_exists?(name)

      role = user.roles.first || create(:role)
      role.role_permissions.find_or_create_by!(permission_name: name)
      user.roles << role unless user.roles.include?(role)
    end
    user.reload
  end

  # Revoke permissions (by NAME) from an existing user's roles.
  # @param user [User] The user to revoke permissions from
  # @param permission_names [Array<String>] Catalog permission names to revoke
  def revoke_permissions(user, *permission_names)
    permission_names.flatten.each do |name|
      user.roles.each do |role|
        role.role_permissions.where(permission_name: name).delete_all
      end
    end
    user.reload
  end
end

RSpec.configure do |config|
  config.include PermissionTestHelpers, type: :request
  config.include PermissionTestHelpers, type: :controller
  config.include PermissionTestHelpers, type: :model
end
