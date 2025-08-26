# frozen_string_literal: true

class PermissionMatrixService
  # Standard permissions matrix - resource.action format
  PERMISSIONS = {
    'users' => {
      'create' => 'Create new users in the system',
      'read' => 'View user information and lists', 
      'update' => 'Modify user details and settings',
      'delete' => 'Remove users from the system',
      'suspend' => 'Suspend/unsuspend user accounts',
      'impersonate' => 'Impersonate other users for support',
      'manage' => 'Full user management including all operations',
      'invite' => 'Send invitations to new users'
    },
    'roles' => {
      'create' => 'Create new roles and permission groups',
      'read' => 'View roles and their permissions',
      'update' => 'Modify role permissions and settings',
      'delete' => 'Remove roles from the system',
      'manage' => 'Full role management including assignments',
      'assign' => 'Assign roles to users'
    },
    'accounts' => {
      'create' => 'Create new account instances',
      'read' => 'View account information and settings',
      'update' => 'Modify account details and configuration',
      'delete' => 'Remove accounts from the system',
      'manage' => 'Full account management including all operations',
      'billing' => 'Access account billing and subscription information'
    },
    'billing' => {
      'read' => 'View billing information and invoices',
      'update' => 'Modify billing settings and payment methods',
      'manage' => 'Full billing management including payments',
      'export' => 'Export billing data and reports',
      'process' => 'Process payments and refunds'
    },
    'analytics' => {
      'read' => 'View analytics dashboards and basic metrics',
      'export' => 'Export analytics data and reports',
      'manage' => 'Configure analytics settings and advanced features',
      'global' => 'Access cross-account analytics (system admin only)'
    },
    'system' => {
      'admin' => 'Full system administration access',
      'settings' => 'Manage system-wide settings and configuration',
      'workers' => 'Manage background workers and job processing',
      'maintenance' => 'Perform system maintenance operations',
      'monitoring' => 'Access system monitoring and health metrics'
    },
    'audit_logs' => {
      'read' => 'View audit logs and security events',
      'export' => 'Export audit log data for compliance',
      'manage' => 'Configure audit logging settings',
      'delete' => 'Delete old audit log entries'
    },
    'webhooks' => {
      'create' => 'Create new webhook endpoints',
      'read' => 'View webhook configurations and delivery logs',
      'update' => 'Modify webhook settings and endpoints',
      'delete' => 'Remove webhook configurations',
      'manage' => 'Full webhook management including testing',
      'test' => 'Test webhook endpoints and delivery'
    },
    'api_keys' => {
      'create' => 'Generate new API keys',
      'read' => 'View API key information and usage',
      'update' => 'Modify API key settings and permissions',
      'delete' => 'Revoke and remove API keys',
      'regenerate' => 'Regenerate existing API keys'
    },
    'plans' => {
      'create' => 'Create new subscription plans',
      'read' => 'View plan information and pricing',
      'update' => 'Modify plan details and pricing',
      'delete' => 'Remove plans from the system',
      'manage' => 'Full plan management including features'
    },
    'reports' => {
      'create' => 'Generate new reports',
      'read' => 'View existing reports and templates',
      'export' => 'Export report data in various formats',
      'schedule' => 'Schedule automated report generation',
      'manage' => 'Full report management including templates'
    },
    'pages' => {
      'create' => 'Create new content pages',
      'read' => 'View page content and drafts',
      'update' => 'Edit page content and settings',
      'delete' => 'Remove pages from the system',
      'publish' => 'Publish and unpublish pages',
      'manage' => 'Full page management including templates'
    },
    'payments' => {
      'read' => 'View payment transactions and history',
      'process' => 'Process new payments and charges',
      'refund' => 'Issue refunds for transactions',
      'manage' => 'Full payment management including gateways'
    },
    'delegations' => {
      'create' => 'Create account delegation requests',
      'read' => 'View delegation status and history',
      'approve' => 'Approve or deny delegation requests',
      'manage' => 'Full delegation management'
    },
    'subscriptions' => {
      'read' => 'View subscription details and status',
      'update' => 'Modify subscription plans and settings',
      'cancel' => 'Cancel active subscriptions',
      'manage' => 'Full subscription lifecycle management'
    }
  }.freeze

  # Standard role definitions with their permissions
  STANDARD_ROLES = {
    'super_admin' => {
      description: 'Full system administration access across all accounts',
      permissions: [
        'system.*',
        'accounts.*',
        'users.*',
        'roles.*',
        'billing.*',
        'analytics.*',
        'audit_logs.*',
        'webhooks.*',
        'api_keys.*',
        'plans.*',
        'reports.*',
        'pages.*',
        'payments.*',
        'delegations.*',
        'subscriptions.*'
      ],
      system_role: true
    },
    'manager' => {
      description: 'Full management access within assigned account',
      permissions: [
        'accounts.read',
        'accounts.update',
        'accounts.billing',
        'users.create',
        'users.read',
        'users.update',
        'users.delete',
        'users.suspend',
        'users.invite',
        'roles.read',
        'roles.assign',
        'billing.read',
        'billing.update',
        'analytics.read',
        'analytics.export',
        'audit_logs.read',
        'webhooks.create',
        'webhooks.read',
        'webhooks.update',
        'webhooks.delete',
        'api_keys.create',
        'api_keys.read',
        'api_keys.update',
        'api_keys.delete',
        'reports.create',
        'reports.read',
        'reports.export',
        'reports.schedule',
        'pages.create',
        'pages.read',
        'pages.update',
        'pages.delete',
        'pages.publish',
        'subscriptions.read',
        'subscriptions.update'
      ],
      system_role: false
    },
    'member' => {
      description: 'Basic account member access with limited permissions',
      permissions: [
        'accounts.read',
        'users.read',
        'billing.read',
        'analytics.read',
        'reports.read',
        'pages.read',
        'subscriptions.read'
      ],
      system_role: false
    },
    'billing.manager' => {
      description: 'Specialized role for billing and payment management',
      permissions: [
        'accounts.read',
        'accounts.billing',
        'billing.*',
        'payments.*',
        'plans.read',
        'plans.update',
        'subscriptions.*',
        'analytics.read',
        'reports.create',
        'reports.read',
        'reports.export'
      ],
      system_role: false
    },
    'support.agent' => {
      description: 'Customer support role with user assistance permissions',
      permissions: [
        'accounts.read',
        'users.read',
        'users.suspend',
        'users.impersonate',
        'billing.read',
        'analytics.read',
        'audit_logs.read',
        'reports.read',
        'pages.read',
        'subscriptions.read'
      ],
      system_role: false
    },
    'content.manager' => {
      description: 'Content management role for pages and documentation',
      permissions: [
        'accounts.read',
        'users.read',
        'pages.*',
        'reports.create',
        'reports.read',
        'reports.export',
        'analytics.read'
      ],
      system_role: false
    },
    'analytics.viewer' => {
      description: 'Read-only access to analytics and reporting features',
      permissions: [
        'accounts.read',
        'analytics.read',
        'analytics.export',
        'reports.read',
        'reports.export',
        'billing.read',
        'subscriptions.read'
      ],
      system_role: false
    },
    'api.developer' => {
      description: 'API development and integration role',
      permissions: [
        'accounts.read',
        'api_keys.*',
        'webhooks.*',
        'analytics.read',
        'reports.read',
        'audit_logs.read'
      ],
      system_role: false
    },
    # Worker-specific roles
    'system.worker' => {
      description: 'System background job processor with full access',
      permissions: [
        'system.*',
        'accounts.*',
        'users.*',
        'billing.*',
        'analytics.*',
        'audit_logs.*',
        'webhooks.*',
        'api_keys.*',
        'plans.*',
        'reports.*',
        'pages.*',
        'payments.*',
        'subscriptions.*'
      ],
      system_role: true
    },
    'worker.standard' => {
      description: 'Standard worker for account-specific job processing',
      permissions: [
        'accounts.read',
        'users.read',
        'billing.read',
        'billing.process',
        'analytics.read',
        'reports.create',
        'reports.read',
        'subscriptions.read',
        'subscriptions.update'
      ],
      system_role: false
    },
    'worker.readonly' => {
      description: 'Read-only worker for monitoring and reporting',
      permissions: [
        'accounts.read',
        'users.read',
        'billing.read',
        'analytics.read',
        'reports.read',
        'subscriptions.read'
      ],
      system_role: false
    }
  }.freeze

  class << self
    # Get all permissions as flat array
    def all_permissions
      permissions = []
      PERMISSIONS.each do |resource, actions|
        actions.each do |action, _description|
          permissions << "#{resource}.#{action}"
        end
      end
      permissions
    end

    # Get permissions for a specific resource
    def permissions_for_resource(resource)
      return [] unless PERMISSIONS[resource]
      
      PERMISSIONS[resource].keys.map { |action| "#{resource}.#{action}" }
    end

    # Check if a permission exists
    def valid_permission?(permission)
      all_permissions.include?(permission)
    end

    # Get role definition
    def role_definition(role_name)
      STANDARD_ROLES[role_name]
    end

    # Get all standard role names
    def standard_role_names
      STANDARD_ROLES.keys
    end

    # Check if role is a system role
    def system_role?(role_name)
      definition = role_definition(role_name)
      definition&.dig(:system_role) || false
    end

    # Get permissions for a role, expanding wildcards
    def expanded_permissions_for_role(role_name)
      definition = role_definition(role_name)
      return [] unless definition

      permissions = []
      definition[:permissions].each do |permission|
        if permission.end_with?('.*')
          # Wildcard permission - add all permissions for resource
          resource = permission.sub('.*', '')
          permissions.concat(permissions_for_resource(resource))
        else
          permissions << permission
        end
      end
      
      permissions.uniq
    end

    # Validate permissions array
    def validate_permissions(permissions)
      invalid_permissions = permissions - all_permissions
      return { valid: true } if invalid_permissions.empty?
      
      { 
        valid: false, 
        invalid_permissions: invalid_permissions,
        message: "Invalid permissions: #{invalid_permissions.join(', ')}"
      }
    end

    # Get permission description
    def permission_description(permission)
      resource, action = permission.split('.', 2)
      return nil unless resource && action
      
      PERMISSIONS.dig(resource, action)
    end

    # Seed permissions and roles
    def seed_permissions_and_roles!
      Rails.logger.info "Seeding permissions and roles..."
      
      # Create permissions
      created_permissions = 0
      PERMISSIONS.each do |resource, actions|
        actions.each do |action, description|
          permission = Permission.find_or_create_by(
            resource: resource,
            action: action
          ) do |p|
            p.description = description
          end
          
          created_permissions += 1 if permission.previously_new_record?
        end
      end
      
      # Create roles with permissions
      created_roles = 0
      STANDARD_ROLES.each do |role_name, definition|
        role = Role.find_or_create_by(name: role_name) do |r|
          r.description = definition[:description]
          r.system_role = definition[:system_role]
        end
        
        if role.previously_new_record? || role.permissions.empty?
          created_roles += 1 if role.previously_new_record?
          
          # Clear existing permissions and reassign
          role.permissions.clear
          
          # Assign permissions to role
          expanded_permissions = expanded_permissions_for_role(role_name)
          expanded_permissions.each do |permission_name|
            resource, action = permission_name.split('.', 2)
            permission = Permission.find_by(resource: resource, action: action)
            
            if permission
              role.permissions << permission unless role.permissions.include?(permission)
            else
              Rails.logger.warn "Permission not found: #{permission_name}"
            end
          end
        end
      end
      
      Rails.logger.info "Created #{created_permissions} permissions and #{created_roles} roles"
      
      {
        permissions_created: created_permissions,
        roles_created: created_roles,
        total_permissions: all_permissions.count,
        total_roles: STANDARD_ROLES.count
      }
    end

    # Assign default roles to users (for fresh database)
    def assign_default_roles_to_users!
      Rails.logger.info "Assigning default roles to users..."
      
      assigned_count = 0
      User.includes(:user_roles).find_each do |user|
        # Skip if user already has roles
        next if user.user_roles.any?
        
        # Determine appropriate role based on position in account
        role_name = if user.account.users.order(:created_at).first == user
                     'manager'
                   else
                     'member'
                   end
        
        role = Role.find_by(name: role_name)
        if role
          user.assign_role(role)
          assigned_count += 1
          Rails.logger.info "Assigned #{role_name} role to user #{user.email}"
        else
          Rails.logger.warn "Role #{role_name} not found for user #{user.email}"
        end
      end
      
      Rails.logger.info "Assigned roles to #{assigned_count} users"
      assigned_count
    end

    private

  end
end