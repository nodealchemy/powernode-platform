# frozen_string_literal: true

# Permission System V2 - Three-tier Architecture
# resource.action - Standard resource operations for regular users
# admin.action - Administrative operations for admin users  
# system.action - System-level operations for workers and automation

module Permissions
  # Resource Permissions - User-facing operations
  RESOURCE_PERMISSIONS = {
    # User Management
    'user.read' => 'View user profiles',
    'user.edit_self' => 'Edit own profile',
    'user.delete_self' => 'Delete own account',
    
    # Team Management
    'team.read' => 'View team members',
    'team.invite' => 'Invite team members',
    'team.remove' => 'Remove team members',
    'team.assign_roles' => 'Assign roles to team members',
    
    # Billing & Subscriptions
    'billing.read' => 'View billing information',
    'billing.update' => 'Update payment methods',
    'billing.cancel' => 'Cancel subscriptions',
    'plans.read' => 'View subscription plans',
    'plans.create' => 'Create subscription plans',
    'plans.manage' => 'Manage subscription plans',
    'invoice.read' => 'View invoices',
    'invoice.download' => 'Download invoices',
    
    # Content Management
    'page.create' => 'Create pages',
    'page.read' => 'View pages',
    'page.edit' => 'Edit pages',
    'page.delete' => 'Delete pages',
    'page.publish' => 'Publish pages',
    
    # Analytics & Reports
    'analytics.read' => 'View analytics dashboard',
    'analytics.export' => 'Export analytics data',
    'report.read' => 'View reports',
    'report.generate' => 'Generate reports',
    'report.export' => 'Export reports',
    
    # API Access
    'api.read' => 'Read API access',
    'api.write' => 'Write API access',
    'api.manage_keys' => 'Manage API keys',
    
    # Webhooks
    'webhook.read' => 'View webhooks',
    'webhook.create' => 'Create webhooks',
    'webhook.edit' => 'Edit webhooks',
    'webhook.delete' => 'Delete webhooks',
    
    # Audit Logs
    'audit.read' => 'View audit logs',
    'audit.export' => 'Export audit logs',
    'audit.manage' => 'Manage audit logs',
    
    # Knowledge Base
    'kb.read' => 'View published knowledge base articles',
    'kb.create' => 'Create knowledge base articles',
    'kb.edit' => 'Edit knowledge base articles',
    'kb.delete' => 'Delete knowledge base articles',
    'kb.publish' => 'Publish knowledge base articles',
    'kb.manage' => 'Manage knowledge base categories and settings',
    'kb.moderate' => 'Moderate knowledge base comments',
    
    # Marketplace - Apps
    'app.read' => 'View marketplace apps',
    'app.create' => 'Create marketplace apps',
    'app.edit' => 'Edit own apps',
    'app.delete' => 'Delete own apps',
    'app.publish' => 'Publish own apps',
    'app.manage_features' => 'Manage app features',
    'app.manage_plans' => 'Manage app plans',
    'app.read_analytics' => 'View app analytics',
    
    # Marketplace - App Subscriptions
    'subscription.read' => 'View app subscriptions',
    'subscription.create' => 'Subscribe to apps',
    'subscription.manage' => 'Manage subscriptions',
    'subscription.cancel' => 'Cancel subscriptions',
    'subscription.upgrade' => 'Upgrade subscriptions',
    'subscription.read_usage' => 'View subscription usage',
    
    # Marketplace - Reviews
    'review.read' => 'View app reviews',
    'review.create' => 'Write app reviews',
    'review.edit' => 'Edit own reviews',
    'review.delete' => 'Delete own reviews',
    'review.moderate' => 'Moderate reviews',
    
    # Marketplace - Listings
    'listing.read' => 'View marketplace listings',
    'listing.create' => 'Create marketplace listings',
    'listing.edit' => 'Edit own listings',
    'listing.delete' => 'Delete own listings'
  }.freeze

  # Admin Permissions - Administrative operations
  ADMIN_PERMISSIONS = {
    # General Admin Access
    'admin.access' => 'Access admin panel and features',
    
    # User Administration
    'admin.user.read' => 'View all users',
    'admin.user.create' => 'Create users',
    'admin.user.edit' => 'Edit any user',
    'admin.user.delete' => 'Delete users',
    'admin.user.impersonate' => 'Impersonate users',
    'admin.user.suspend' => 'Suspend users',
    
    # Account Administration
    'admin.account.read' => 'View all accounts',
    'admin.account.create' => 'Create accounts',
    'admin.account.edit' => 'Edit accounts',
    'admin.account.delete' => 'Delete accounts',
    'admin.account.suspend' => 'Suspend accounts',
    
    # Role & Permission Management
    'admin.role.read' => 'View roles',
    'admin.role.create' => 'Create roles',
    'admin.role.edit' => 'Edit roles',
    'admin.role.delete' => 'Delete roles',
    'admin.role.assign' => 'Assign roles',
    
    # Billing Administration
    'admin.billing.read' => 'View all billing',
    'admin.billing.override' => 'Override billing',
    'admin.billing.refund' => 'Process refunds',
    'admin.billing.credit' => 'Issue credits',
    'admin.billing.manage_gateways' => 'Manage payment gateways',
    
    # System Settings
    'admin.settings.read' => 'View settings',
    'admin.settings.edit' => 'Edit settings',
    'admin.settings.security' => 'Security settings',
    'admin.settings.email' => 'Email settings',
    'admin.settings.payment' => 'Payment gateway settings',
    
    # Audit & Compliance
    'admin.audit.read' => 'View all audit logs',
    'admin.audit.export' => 'Export audit logs',
    'admin.audit.delete' => 'Delete audit logs',
    'admin.audit.manage' => 'Manage audit system',
    'admin.compliance.read' => 'View compliance',
    'admin.compliance.report' => 'Generate compliance reports',
    
    # Maintenance Operations
    'admin.maintenance.mode' => 'Toggle maintenance mode',
    'admin.maintenance.backup' => 'Manage backups',
    'admin.maintenance.restore' => 'Restore from backup',
    'admin.maintenance.cleanup' => 'Run cleanup operations',
    'admin.maintenance.tasks' => 'Manage scheduled tasks',
    
    # Knowledge Base Administration
    'admin.kb.read' => 'View all knowledge base content',
    'admin.kb.manage' => 'Manage knowledge base system',
    'admin.kb.moderate' => 'Moderate all content and comments',
    'admin.kb.analytics' => 'Access knowledge base analytics',
    'admin.kb.settings' => 'Configure knowledge base settings',
    
    # Worker Management - consolidated under system.workers namespace
    
    # Marketplace Administration
    'admin.marketplace.read' => 'View marketplace management',
    'admin.marketplace.manage' => 'Manage marketplace settings',
    'admin.marketplace.export' => 'Export marketplace data',
    'admin.app.read' => 'View all apps',
    'admin.app.edit' => 'Edit any app',
    'admin.app.delete' => 'Delete any app',
    'admin.app.approve' => 'Approve apps for publication',
    'admin.app.suspend' => 'Suspend apps',
    'admin.listing.read' => 'View all listings',
    'admin.listing.edit' => 'Edit any listing',
    'admin.listing.delete' => 'Delete any listing',
    'admin.listing.approve' => 'Approve listings',
    'admin.listing.feature' => 'Feature listings',
    'admin.review.read' => 'View all reviews',
    'admin.review.moderate' => 'Moderate reviews',
    'admin.review.delete' => 'Delete reviews',
    'admin.subscription.read' => 'View all subscriptions',
    'admin.subscription.manage' => 'Manage any subscription'
  }.freeze

  # System Permissions - Worker & automation operations
  SYSTEM_PERMISSIONS = {
    # Worker Operations
    'system.worker.register' => 'Register as worker',
    'system.worker.heartbeat' => 'Send heartbeats',
    'system.worker.report' => 'Report status',
    'system.worker.execute' => 'Execute jobs',
    
    # Worker Management (for frontend admin interface)
    'system.workers.read' => 'View worker management interface',
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
        'user.read', 'user.edit_self',
        'team.read',
        'billing.read',
        'page.read',
        'analytics.read',
        'report.read',
        'api.read',
        'webhook.read',
        'invoice.read',
        'audit.read',
        'kb.read',
        # Marketplace permissions
        'app.read',
        'listing.read',
        'subscription.read', 'subscription.create', 'subscription.manage', 'subscription.cancel',
        'subscription.read_usage',
        'review.read'
      ]
    },

    # Team manager with extended permissions
    'manager' => {
      display_name: 'Manager',
      description: 'Team manager with content and team management capabilities',
      role_type: 'user',
      permissions: [
        # All member permissions
        'user.read', 'user.edit_self',
        'team.read', 'team.invite', 'team.remove', 'team.assign_roles',
        'billing.read', 'billing.update',
        'plans.read', 'plans.manage',
        'page.read', 'page.create', 'page.edit', 'page.delete', 'page.publish',
        'analytics.read', 'analytics.export',
        'report.read', 'report.generate', 'report.export',
        'api.read', 'api.write', 'api.manage_keys',
        'webhook.read', 'webhook.create', 'webhook.edit', 'webhook.delete',
        'invoice.read', 'invoice.download',
        'audit.read', 'audit.export', 'audit.manage',
        # Knowledge base permissions
        'kb.read', 'kb.create', 'kb.edit', 'kb.publish', 'kb.manage',
        # Marketplace permissions
        'app.read', 'app.create', 'app.edit', 'app.delete', 'app.publish',
        'app.manage_features', 'app.manage_plans', 'app.read_analytics',
        'listing.read', 'listing.create', 'listing.edit', 'listing.delete',
        'subscription.read', 'subscription.create', 'subscription.manage', 
        'subscription.cancel', 'subscription.upgrade', 'subscription.read_usage',
        'review.read', 'review.create', 'review.edit', 'review.delete', 'review.moderate'
      ]
    },

    # Billing administrator
    'billing_admin' => {
      display_name: 'Billing Administrator',
      description: 'Manages billing, subscriptions, and financial operations',
      role_type: 'user',
      permissions: [
        'user.read', 'user.edit_self',
        'team.read',
        'billing.read', 'billing.update', 'billing.cancel',
        'plans.read', 'plans.create', 'plans.manage',
        'invoice.read', 'invoice.download',
        'analytics.read',
        'report.read', 'report.generate',
        'admin.billing.read', 'admin.billing.override',
        'admin.billing.refund', 'admin.billing.credit',
        'audit.read'
      ]
    },

    # App developer with marketplace focus
    'developer' => {
      display_name: 'App Developer',
      description: 'App developer with marketplace publishing capabilities',
      role_type: 'user',
      permissions: [
        'user.read', 'user.edit_self',
        'team.read',
        'billing.read', 'billing.update',
        'plans.read',
        'page.read',
        'analytics.read', 'analytics.export',
        'report.read', 'report.generate',
        'api.read', 'api.write', 'api.manage_keys',
        'webhook.read', 'webhook.create', 'webhook.edit', 'webhook.delete',
        # Knowledge base permissions
        'kb.read', 'kb.create', 'kb.edit', 'kb.publish', 'kb.manage',
        'invoice.read', 'invoice.download',
        'audit.read',
        # Full marketplace permissions
        'app.read', 'app.create', 'app.edit', 'app.delete', 'app.publish',
        'app.manage_features', 'app.manage_plans', 'app.read_analytics',
        'listing.read', 'listing.create', 'listing.edit', 'listing.delete',
        'subscription.read', 'subscription.create', 'subscription.manage',
        'subscription.cancel', 'subscription.upgrade', 'subscription.read_usage',
        'review.read', 'review.create', 'review.edit', 'review.delete', 'review.moderate'
      ]
    },

    # Content manager with knowledge base focus
    'content_manager' => {
      display_name: 'Content Manager',
      description: 'Manages knowledge base content and documentation',
      role_type: 'user',
      permissions: [
        'user.read', 'user.edit_self',
        'team.read',
        'billing.read',
        'page.read', 'page.create', 'page.edit', 'page.publish',
        'analytics.read',
        'report.read',
        'api.read',
        'audit.read',
        # Full knowledge base permissions
        'kb.read', 'kb.create', 'kb.edit', 'kb.delete', 'kb.publish',
        'kb.manage', 'kb.moderate'
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
        'admin.user.read', 'admin.user.create', 'admin.user.edit', 'admin.user.suspend',
        'admin.role.read', 'admin.role.assign',
        'admin.billing.read', 'admin.billing.override',
        'admin.settings.read', 'admin.settings.edit',
        'admin.audit.read', 'admin.audit.export', 'admin.audit.manage',
        'admin.kb.read', 'admin.kb.manage', 'admin.kb.analytics'
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

    # Super administrator - special system role with programmatic access to all permissions
    'super_admin' => {
      display_name: 'Super Administrator',
      description: 'Special system role with programmatic access to ALL permissions. Cannot be edited or deleted.',
      role_type: 'admin',
      permissions: [], # No explicit permissions - grants all programmatically
      is_system: true,
      immutable: true # Cannot be edited or deleted
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