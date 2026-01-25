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
      accounts.read accounts.update accounts.manage
      users.read users.create users.update users.delete users.manage
      roles.read roles.create roles.update roles.delete
      billing.read billing.update billing.manage
      analytics.read
      audit_logs.read
      settings.read settings.update
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
      settings.read
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
      ai.workflows.read ai.workflows.create ai.workflows.update ai.workflows.delete ai.workflows.execute
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
      ai.workflows.read
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
      devops.pipelines.read devops.pipelines.create devops.pipelines.update devops.pipelines.execute
      devops.deployments.read devops.deployments.create devops.deployments.approve
      devops.environments.read devops.environments.create devops.environments.update
      git_providers.read git_providers.create
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

  # Ensure common test permissions exist in the database
  # Call this in a before(:all) or before(:suite) block
  def ensure_test_permissions_exist
    permission_sets = {
      'users' => %w[read create update delete manage],
      'accounts' => %w[read update manage],
      'billing' => %w[read create update delete manage],
      'payments' => %w[read create],
      'invoices' => %w[read create],
      'subscriptions' => %w[read update],
      'analytics' => %w[read],
      'audit_logs' => %w[read export],
      'settings' => %w[read update],
      'roles' => %w[read create update delete],
      'ai.workflows' => %w[read create update delete execute export],
      'ai.agents' => %w[read create update delete execute],
      'ai.conversations' => %w[read create update delete manage],
      'ai.providers' => %w[read create update delete],
      'ai.analytics' => %w[read],
      'devops.pipelines' => %w[read create update delete execute],
      'devops.deployments' => %w[read create approve],
      'devops.environments' => %w[read create update delete],
      'git_providers' => %w[read create update delete],
      'admin' => %w[access]
    }

    permission_sets.each do |resource, actions|
      actions.each do |action|
        Permission.find_or_create_by!(name: "#{resource}.#{action}") do |p|
          p.resource = resource
          p.action = action
          p.category = resource.include?('.') ? resource.split('.').first : 'resource'
        end
      end
    end
  end

  # Grant additional permissions to an existing user
  # @param user [User] The user to grant permissions to
  # @param permission_names [Array<String>] Permission names to grant
  def grant_permissions(user, *permission_names)
    permission_names.flatten.each do |name|
      permission = Permission.find_by(name: name)
      next unless permission
      next if user.permissions.include?(permission)

      # Find or create a role for this permission
      role = user.roles.first || create(:role)
      role.permissions << permission unless role.permissions.include?(permission)
      user.roles << role unless user.roles.include?(role)
    end
    user.reload
  end

  # Revoke permissions from an existing user
  # @param user [User] The user to revoke permissions from
  # @param permission_names [Array<String>] Permission names to revoke
  def revoke_permissions(user, *permission_names)
    permission_names.flatten.each do |name|
      permission = Permission.find_by(name: name)
      next unless permission

      user.roles.each do |role|
        role.permissions.delete(permission)
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
