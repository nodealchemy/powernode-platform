# frozen_string_literal: true

# Permission System V2 - Three-tier Architecture
# resource.action - Standard resource operations for regular users
# admin.action - Administrative operations for admin users  
# system.action - System-level operations for workers and automation

module Permissions
  # Resource Permissions - User-facing operations
  RESOURCE_PERMISSIONS = {
    # User Management
    'user.view' => 'View user profiles',
    'user.edit_self' => 'Edit own profile',
    'user.delete_self' => 'Delete own account',
    
    # Team Management
    'team.view' => 'View team members',
    'team.invite' => 'Invite team members',
    'team.remove' => 'Remove team members',
    'team.assign_roles' => 'Assign roles to team members',
    
    # Billing & Subscriptions
    'billing.view' => 'View billing information',
    'billing.update' => 'Update payment methods',
    'billing.cancel' => 'Cancel subscriptions',
    'plans.view' => 'View subscription plans',
    'plans.create' => 'Create subscription plans',
    'plans.manage' => 'Manage subscription plans',
    'invoice.view' => 'View invoices',
    'invoice.download' => 'Download invoices',
    
    # Content Management
    'page.create' => 'Create pages',
    'page.view' => 'View pages',
    'page.edit' => 'Edit pages',
    'page.delete' => 'Delete pages',
    'page.publish' => 'Publish pages',
    
    # Analytics & Reports
    'analytics.view' => 'View analytics dashboard',
    'analytics.export' => 'Export analytics data',
    'report.view' => 'View reports',
    'report.generate' => 'Generate reports',
    'report.export' => 'Export reports',
    
    # API Access
    'api.read' => 'Read API access',
    'api.write' => 'Write API access',
    'api.manage_keys' => 'Manage API keys',
    
    # Webhooks
    'webhook.view' => 'View webhooks',
    'webhook.create' => 'Create webhooks',
    'webhook.edit' => 'Edit webhooks',
    'webhook.delete' => 'Delete webhooks',
    
    # Audit Logs
    'audit.view' => 'View audit logs',
    'audit.export' => 'Export audit logs'
  }.freeze

  # Admin Permissions - Administrative operations
  ADMIN_PERMISSIONS = {
    # General Admin Access
    'admin.access' => 'Access admin panel and features',
    
    # User Administration
    'admin.user.view' => 'View all users',
    'admin.user.create' => 'Create users',
    'admin.user.edit' => 'Edit any user',
    'admin.user.delete' => 'Delete users',
    'admin.user.impersonate' => 'Impersonate users',
    'admin.user.suspend' => 'Suspend users',
    
    # Account Administration
    'admin.account.view' => 'View all accounts',
    'admin.account.create' => 'Create accounts',
    'admin.account.edit' => 'Edit accounts',
    'admin.account.delete' => 'Delete accounts',
    'admin.account.suspend' => 'Suspend accounts',
    
    # Role & Permission Management
    'admin.role.view' => 'View roles',
    'admin.role.create' => 'Create roles',
    'admin.role.edit' => 'Edit roles',
    'admin.role.delete' => 'Delete roles',
    'admin.role.assign' => 'Assign roles',
    
    # Billing Administration
    'admin.billing.view' => 'View all billing',
    'admin.billing.override' => 'Override billing',
    'admin.billing.refund' => 'Process refunds',
    'admin.billing.credit' => 'Issue credits',
    'admin.billing.manage_gateways' => 'Manage payment gateways',
    
    # System Settings
    'admin.settings.view' => 'View settings',
    'admin.settings.edit' => 'Edit settings',
    'admin.settings.security' => 'Security settings',
    'admin.settings.email' => 'Email settings',
    'admin.settings.payment' => 'Payment gateway settings',
    
    # Audit & Compliance
    'admin.audit.view' => 'View all audit logs',
    'admin.audit.export' => 'Export audit logs',
    'admin.audit.delete' => 'Delete audit logs',
    'admin.compliance.view' => 'View compliance',
    'admin.compliance.report' => 'Generate compliance reports',
    
    # Maintenance Operations
    'admin.maintenance.mode' => 'Toggle maintenance mode',
    'admin.maintenance.backup' => 'Manage backups',
    'admin.maintenance.restore' => 'Restore from backup',
    'admin.maintenance.cleanup' => 'Run cleanup operations',
    'admin.maintenance.tasks' => 'Manage scheduled tasks',
    
    # Worker Management
    'admin.worker.view' => 'View workers',
    'admin.worker.create' => 'Create workers',
    'admin.worker.edit' => 'Edit workers',
    'admin.worker.delete' => 'Delete workers',
    'admin.worker.suspend' => 'Suspend workers'
  }.freeze

  # System Permissions - Worker & automation operations
  SYSTEM_PERMISSIONS = {
    # Worker Operations
    'system.worker.register' => 'Register as worker',
    'system.worker.heartbeat' => 'Send heartbeats',
    'system.worker.report' => 'Report status',
    'system.worker.execute' => 'Execute jobs',
    
    # Worker Management (for frontend admin interface)
    'system.workers.view' => 'View worker management interface',
    'system.workers.create' => 'Create new workers',
    'system.workers.edit' => 'Edit worker configurations',
    'system.workers.delete' => 'Delete workers',
    'system.workers.suspend' => 'Suspend workers',
    'system.workers.activate' => 'Activate workers',
    'system.workers.regenerate' => 'Regenerate worker tokens',
    
    # Database Operations
    'system.database.read' => 'Direct database read',
    'system.database.write' => 'Direct database write',
    'system.database.backup' => 'Perform backups',
    'system.database.restore' => 'Perform restores',
    'system.database.optimize' => 'Optimize database',
    
    # Job Processing
    'system.jobs.process' => 'Process background jobs',
    'system.jobs.retry' => 'Retry failed jobs',
    'system.jobs.cancel' => 'Cancel jobs',
    'system.jobs.schedule' => 'Schedule jobs',
    
    # System Monitoring
    'system.health.check' => 'Perform health checks',
    'system.health.report' => 'Report health status',
    'system.metrics.collect' => 'Collect metrics',
    'system.metrics.report' => 'Report metrics',
    
    # Cache & Storage
    'system.cache.read' => 'Read from cache',
    'system.cache.write' => 'Write to cache',
    'system.cache.clear' => 'Clear cache',
    'system.storage.read' => 'Read from storage',
    'system.storage.write' => 'Write to storage',
    'system.storage.clean' => 'Clean storage',
    
    # Service Control
    'system.service.restart' => 'Restart services',
    'system.service.reload' => 'Reload configurations',
    'system.service.status' => 'Check service status',
    
    # Integration Operations
    'system.webhook.process' => 'Process webhooks',
    'system.webhook.retry' => 'Retry webhooks',
    'system.email.send' => 'Send emails',
    'system.notification.send' => 'Send notifications',
    
    # Internal API Access
    'system.api.internal' => 'Access internal APIs',
    'system.api.service' => 'Service-to-service communication'
  }.freeze

  # All permissions combined
  ALL_PERMISSIONS = {
    **RESOURCE_PERMISSIONS,
    **ADMIN_PERMISSIONS,
    **SYSTEM_PERMISSIONS
  }.freeze

  # Role Definitions
  ROLES = {
    # Regular user with basic access
    'member' => {
      display_name: 'Member',
      description: 'Basic account member with standard access',
      role_type: 'user',
      permissions: [
        'user.view', 'user.edit_self',
        'team.view',
        'billing.view',
        'page.view',
        'analytics.view',
        'report.view',
        'api.read',
        'webhook.view',
        'invoice.view',
        'audit.view'
      ]
    },

    # Team manager with extended permissions
    'manager' => {
      display_name: 'Manager',
      description: 'Team manager with content and team management capabilities',
      role_type: 'user',
      permissions: [
        # All member permissions
        'user.view', 'user.edit_self',
        'team.view', 'team.invite', 'team.remove', 'team.assign_roles',
        'billing.view', 'billing.update',
        'plans.view', 'plans.manage',
        'page.view', 'page.create', 'page.edit', 'page.delete', 'page.publish',
        'analytics.view', 'analytics.export',
        'report.view', 'report.generate', 'report.export',
        'api.read', 'api.write', 'api.manage_keys',
        'webhook.view', 'webhook.create', 'webhook.edit', 'webhook.delete',
        'invoice.view', 'invoice.download',
        'audit.view', 'audit.export'
      ]
    },

    # Billing administrator
    'billing_admin' => {
      display_name: 'Billing Administrator',
      description: 'Manages billing, subscriptions, and financial operations',
      role_type: 'user',
      permissions: [
        'user.view', 'user.edit_self',
        'team.view',
        'billing.view', 'billing.update', 'billing.cancel',
        'plans.view', 'plans.create', 'plans.manage',
        'invoice.view', 'invoice.download',
        'analytics.view',
        'report.view', 'report.generate',
        'admin.billing.view', 'admin.billing.override',
        'admin.billing.refund', 'admin.billing.credit',
        'audit.view'
      ]
    },

    # Account owner with full account access
    'owner' => {
      display_name: 'Account Owner',
      description: 'Account owner with full account management capabilities',
      role_type: 'user',
      permissions: [
        # All resource permissions
        *RESOURCE_PERMISSIONS.keys,
        # Selected admin permissions for account management
        'admin.user.view', 'admin.user.create', 'admin.user.edit', 'admin.user.suspend',
        'admin.role.view', 'admin.role.assign',
        'admin.billing.view', 'admin.billing.override',
        'admin.settings.view', 'admin.settings.edit',
        'admin.audit.view', 'admin.audit.export'
      ]
    },

    # System administrator
    'admin' => {
      display_name: 'Administrator',
      description: 'System administrator with full administrative access',
      role_type: 'admin',
      permissions: [
        # All resource permissions
        *RESOURCE_PERMISSIONS.keys,
        # All admin permissions except super admin operations
        *ADMIN_PERMISSIONS.keys.reject { |p| p.start_with?('admin.maintenance.') }
      ]
    },

    # Super administrator with system access
    'super_admin' => {
      display_name: 'Super Administrator',
      description: 'Super administrator with full system access',
      role_type: 'admin',
      permissions: [
        # All resource permissions
        *RESOURCE_PERMISSIONS.keys,
        # All admin permissions
        *ADMIN_PERMISSIONS.keys,
        # System worker management permissions
        'system.workers.view', 'system.workers.create', 'system.workers.edit',
        'system.workers.delete', 'system.workers.suspend', 'system.workers.activate',
        'system.workers.regenerate'
      ]
    },

    # System worker role
    'system_worker' => {
      display_name: 'System Worker',
      description: 'Automated worker with system-level access',
      role_type: 'system',
      permissions: [
        *SYSTEM_PERMISSIONS.keys
      ]
    },

    # Limited worker role for specific tasks
    'task_worker' => {
      display_name: 'Task Worker',
      description: 'Worker limited to specific task execution',
      role_type: 'system',
      permissions: [
        'system.worker.register',
        'system.worker.heartbeat',
        'system.worker.report',
        'system.worker.execute',
        'system.jobs.process',
        'system.health.report',
        'system.api.internal'
      ]
    }
  }.freeze

  # Helper methods
  class << self
    def permission_exists?(permission)
      ALL_PERMISSIONS.key?(permission)
    end

    def permission_description(permission)
      ALL_PERMISSIONS[permission]
    end

    def permissions_for_role(role_name)
      ROLES.dig(role_name, :permissions) || []
    end

    def role_exists?(role_name)
      ROLES.key?(role_name)
    end

    def role_info(role_name)
      ROLES[role_name]
    end

    def permissions_by_category
      {
        'Resource Permissions' => RESOURCE_PERMISSIONS,
        'Admin Permissions' => ADMIN_PERMISSIONS,
        'System Permissions' => SYSTEM_PERMISSIONS
      }
    end

    def resource_permissions
      RESOURCE_PERMISSIONS.keys
    end

    def admin_permissions
      ADMIN_PERMISSIONS.keys
    end

    def system_permissions
      SYSTEM_PERMISSIONS.keys
    end

    def user_roles
      ROLES.select { |_, info| info[:role_type] == 'user' }.keys
    end

    def admin_roles
      ROLES.select { |_, info| info[:role_type] == 'admin' }.keys
    end

    def system_roles
      ROLES.select { |_, info| info[:role_type] == 'system' }.keys
    end
  end
end