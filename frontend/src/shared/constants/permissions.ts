// Permission constants for Powernode platform
// These must match the backend permission system in server/config/permissions.rb

// Resource Permissions - Standard user operations
export const USER_PERMISSIONS = {
  VIEW: 'user.read',
  EDIT_SELF: 'user.edit_self',
  DELETE_SELF: 'user.delete_self'
} as const;

export const TEAM_PERMISSIONS = {
  VIEW: 'team.read',
  INVITE: 'team.invite',
  REMOVE: 'team.remove',
  ASSIGN_ROLES: 'team.assign_roles'
} as const;

export const BILLING_PERMISSIONS = {
  VIEW: 'billing.read',
  UPDATE: 'billing.update',
  CANCEL: 'billing.cancel'
} as const;

export const PLAN_PERMISSIONS = {
  VIEW: 'plans.read',
  CREATE: 'plans.create',
  MANAGE: 'plans.manage'
} as const;

export const PAGE_PERMISSIONS = {
  VIEW: 'page.read',
  CREATE: 'page.create',
  EDIT: 'page.edit',
  DELETE: 'page.delete',
  PUBLISH: 'page.publish'
} as const;

export const ANALYTICS_PERMISSIONS = {
  VIEW: 'analytics.read',
  EXPORT: 'analytics.export'
} as const;

export const REPORT_PERMISSIONS = {
  VIEW: 'report.read',
  GENERATE: 'report.generate',
  EXPORT: 'report.export'
} as const;

export const API_PERMISSIONS = {
  VIEW: 'api.read',
  WRITE: 'api.write',
  MANAGE_KEYS: 'api.manage_keys'
} as const;

export const WEBHOOK_PERMISSIONS = {
  VIEW: 'webhook.read',
  CREATE: 'webhook.create',
  EDIT: 'webhook.edit',
  DELETE: 'webhook.delete'
} as const;

export const INVOICE_PERMISSIONS = {
  VIEW: 'invoice.read',
  DOWNLOAD: 'invoice.download'
} as const;

export const AUDIT_PERMISSIONS = {
  VIEW: 'audit.read',
  EXPORT: 'audit.export',
  MANAGE: 'audit.manage'
} as const;

// Knowledge Base Permissions
export const KB_PERMISSIONS = {
  VIEW: 'kb.read',
  CREATE: 'kb.create',
  EDIT: 'kb.edit',
  DELETE: 'kb.delete',
  PUBLISH: 'kb.publish',
  MANAGE_CATEGORIES: 'kb.manage_categories',
  MODERATE_COMMENTS: 'kb.moderate_comments'
} as const;

// Marketplace Permissions
export const APP_PERMISSIONS = {
  VIEW: 'app.read',
  CREATE: 'app.create',
  EDIT: 'app.edit',
  DELETE: 'app.delete',
  PUBLISH: 'app.publish',
  MANAGE_FEATURES: 'app.manage_features',
  MANAGE_PLANS: 'app.manage_plans',
  READ_ANALYTICS: 'app.read_analytics'
} as const;

export const SUBSCRIPTION_PERMISSIONS = {
  VIEW: 'subscription.read',
  CREATE: 'subscription.create',
  MANAGE: 'subscription.manage',
  CANCEL: 'subscription.cancel',
  UPGRADE: 'subscription.upgrade',
  READ_USAGE: 'subscription.read_usage'
} as const;

export const REVIEW_PERMISSIONS = {
  VIEW: 'review.read',
  CREATE: 'review.create',
  EDIT: 'review.edit',
  DELETE: 'review.delete',
  MODERATE: 'review.moderate'
} as const;

export const LISTING_PERMISSIONS = {
  VIEW: 'listing.read',
  CREATE: 'listing.create',
  EDIT: 'listing.edit',
  DELETE: 'listing.delete'
} as const;

// Admin Permissions - Administrative operations
export const ADMIN_PERMISSIONS = {
  ACCESS: 'admin.access'
} as const;

export const ADMIN_USER_PERMISSIONS = {
  VIEW: 'admin.user.read',
  CREATE: 'admin.user.create',
  EDIT: 'admin.user.edit',
  DELETE: 'admin.user.delete',
  IMPERSONATE: 'admin.user.impersonate',
  SUSPEND: 'admin.user.suspend'
} as const;

export const ADMIN_ACCOUNT_PERMISSIONS = {
  VIEW: 'admin.account.read',
  CREATE: 'admin.account.create',
  EDIT: 'admin.account.edit',
  DELETE: 'admin.account.delete',
  SUSPEND: 'admin.account.suspend'
} as const;

export const ADMIN_ROLE_PERMISSIONS = {
  VIEW: 'admin.role.read',
  CREATE: 'admin.role.create',
  EDIT: 'admin.role.edit',
  DELETE: 'admin.role.delete',
  ASSIGN: 'admin.role.assign'
} as const;

export const ADMIN_BILLING_PERMISSIONS = {
  VIEW: 'admin.billing.read',
  OVERRIDE: 'admin.billing.override',
  REFUND: 'admin.billing.refund',
  CREDIT: 'admin.billing.credit',
  MANAGE_GATEWAYS: 'admin.billing.manage_gateways'
} as const;

export const ADMIN_SETTINGS_PERMISSIONS = {
  VIEW: 'admin.settings.read',
  EDIT: 'admin.settings.edit',
  SECURITY: 'admin.settings.security',
  EMAIL: 'admin.settings.email',
  PAYMENT: 'admin.settings.payment'
} as const;

export const ADMIN_KB_PERMISSIONS = {
  VIEW: 'admin.kb.read',
  MANAGE: 'admin.kb.manage',
  MODERATE: 'admin.kb.moderate',
  ANALYTICS: 'admin.kb.analytics',
  SETTINGS: 'admin.kb.settings'
} as const;

export const ADMIN_AUDIT_PERMISSIONS = {
  VIEW: 'admin.audit.read',
  EXPORT: 'admin.audit.export',
  DELETE: 'admin.audit.delete',
  MANAGE: 'admin.audit.manage'
} as const;

export const ADMIN_MAINTENANCE_PERMISSIONS = {
  MODE: 'admin.maintenance.mode',
  BACKUP: 'admin.maintenance.backup',
  RESTORE: 'admin.maintenance.restore',
  CLEANUP: 'admin.maintenance.cleanup',
  TASKS: 'admin.maintenance.tasks'
} as const;

// System Permissions - Worker & automation operations
export const SYSTEM_WORKER_PERMISSIONS = {
  VIEW: 'system.workers.read',
  CREATE: 'system.workers.create',
  EDIT: 'system.workers.edit',
  DELETE: 'system.workers.delete',
  SUSPEND: 'system.workers.suspend',
  ACTIVATE: 'system.workers.activate',
  REGENERATE: 'system.workers.regenerate'
} as const;

// All permission constants grouped for easy access
export const PERMISSIONS = {
  USER: USER_PERMISSIONS,
  TEAM: TEAM_PERMISSIONS,
  BILLING: BILLING_PERMISSIONS,
  PLANS: PLAN_PERMISSIONS,
  PAGE: PAGE_PERMISSIONS,
  ANALYTICS: ANALYTICS_PERMISSIONS,
  REPORT: REPORT_PERMISSIONS,
  API: API_PERMISSIONS,
  WEBHOOK: WEBHOOK_PERMISSIONS,
  INVOICE: INVOICE_PERMISSIONS,
  AUDIT: AUDIT_PERMISSIONS,
  KB: KB_PERMISSIONS,
  APP: APP_PERMISSIONS,
  SUBSCRIPTION: SUBSCRIPTION_PERMISSIONS,
  REVIEW: REVIEW_PERMISSIONS,
  LISTING: LISTING_PERMISSIONS,
  ADMIN: ADMIN_PERMISSIONS,
  ADMIN_USER: ADMIN_USER_PERMISSIONS,
  ADMIN_ACCOUNT: ADMIN_ACCOUNT_PERMISSIONS,
  ADMIN_ROLE: ADMIN_ROLE_PERMISSIONS,
  ADMIN_BILLING: ADMIN_BILLING_PERMISSIONS,
  ADMIN_SETTINGS: ADMIN_SETTINGS_PERMISSIONS,
  ADMIN_KB: ADMIN_KB_PERMISSIONS,
  ADMIN_AUDIT: ADMIN_AUDIT_PERMISSIONS,
  ADMIN_MAINTENANCE: ADMIN_MAINTENANCE_PERMISSIONS,
  SYSTEM_WORKERS: SYSTEM_WORKER_PERMISSIONS
} as const;

// Utility type for all permissions
export type Permission = 
  | typeof USER_PERMISSIONS[keyof typeof USER_PERMISSIONS]
  | typeof TEAM_PERMISSIONS[keyof typeof TEAM_PERMISSIONS]
  | typeof BILLING_PERMISSIONS[keyof typeof BILLING_PERMISSIONS]
  | typeof PLAN_PERMISSIONS[keyof typeof PLAN_PERMISSIONS]
  | typeof PAGE_PERMISSIONS[keyof typeof PAGE_PERMISSIONS]
  | typeof ANALYTICS_PERMISSIONS[keyof typeof ANALYTICS_PERMISSIONS]
  | typeof REPORT_PERMISSIONS[keyof typeof REPORT_PERMISSIONS]
  | typeof API_PERMISSIONS[keyof typeof API_PERMISSIONS]
  | typeof WEBHOOK_PERMISSIONS[keyof typeof WEBHOOK_PERMISSIONS]
  | typeof INVOICE_PERMISSIONS[keyof typeof INVOICE_PERMISSIONS]
  | typeof AUDIT_PERMISSIONS[keyof typeof AUDIT_PERMISSIONS]
  | typeof KB_PERMISSIONS[keyof typeof KB_PERMISSIONS]
  | typeof APP_PERMISSIONS[keyof typeof APP_PERMISSIONS]
  | typeof SUBSCRIPTION_PERMISSIONS[keyof typeof SUBSCRIPTION_PERMISSIONS]
  | typeof REVIEW_PERMISSIONS[keyof typeof REVIEW_PERMISSIONS]
  | typeof LISTING_PERMISSIONS[keyof typeof LISTING_PERMISSIONS]
  | typeof ADMIN_PERMISSIONS[keyof typeof ADMIN_PERMISSIONS]
  | typeof ADMIN_USER_PERMISSIONS[keyof typeof ADMIN_USER_PERMISSIONS]
  | typeof ADMIN_ACCOUNT_PERMISSIONS[keyof typeof ADMIN_ACCOUNT_PERMISSIONS]
  | typeof ADMIN_ROLE_PERMISSIONS[keyof typeof ADMIN_ROLE_PERMISSIONS]
  | typeof ADMIN_BILLING_PERMISSIONS[keyof typeof ADMIN_BILLING_PERMISSIONS]
  | typeof ADMIN_SETTINGS_PERMISSIONS[keyof typeof ADMIN_SETTINGS_PERMISSIONS]
  | typeof ADMIN_KB_PERMISSIONS[keyof typeof ADMIN_KB_PERMISSIONS]
  | typeof ADMIN_AUDIT_PERMISSIONS[keyof typeof ADMIN_AUDIT_PERMISSIONS]
  | typeof ADMIN_MAINTENANCE_PERMISSIONS[keyof typeof ADMIN_MAINTENANCE_PERMISSIONS]
  | typeof SYSTEM_WORKER_PERMISSIONS[keyof typeof SYSTEM_WORKER_PERMISSIONS];

// Helper function to check if a string is a valid permission
export const isValidPermission = (permission: string): permission is Permission => {
  const allPermissions = [
    ...Object.values(USER_PERMISSIONS),
    ...Object.values(TEAM_PERMISSIONS),
    ...Object.values(BILLING_PERMISSIONS),
    ...Object.values(PLAN_PERMISSIONS),
    ...Object.values(PAGE_PERMISSIONS),
    ...Object.values(ANALYTICS_PERMISSIONS),
    ...Object.values(REPORT_PERMISSIONS),
    ...Object.values(API_PERMISSIONS),
    ...Object.values(WEBHOOK_PERMISSIONS),
    ...Object.values(INVOICE_PERMISSIONS),
    ...Object.values(AUDIT_PERMISSIONS),
    ...Object.values(KB_PERMISSIONS),
    ...Object.values(APP_PERMISSIONS),
    ...Object.values(SUBSCRIPTION_PERMISSIONS),
    ...Object.values(REVIEW_PERMISSIONS),
    ...Object.values(LISTING_PERMISSIONS),
    ...Object.values(ADMIN_PERMISSIONS),
    ...Object.values(ADMIN_USER_PERMISSIONS),
    ...Object.values(ADMIN_ACCOUNT_PERMISSIONS),
    ...Object.values(ADMIN_ROLE_PERMISSIONS),
    ...Object.values(ADMIN_BILLING_PERMISSIONS),
    ...Object.values(ADMIN_SETTINGS_PERMISSIONS),
    ...Object.values(ADMIN_KB_PERMISSIONS),
    ...Object.values(ADMIN_AUDIT_PERMISSIONS),
    ...Object.values(ADMIN_MAINTENANCE_PERMISSIONS),
    ...Object.values(SYSTEM_WORKER_PERMISSIONS)
  ];
  return allPermissions.includes(permission as Permission);
};

// Common permission combinations for convenience
export const PERMISSION_GROUPS = {
  // Basic user operations
  BASIC_USER: [
    USER_PERMISSIONS.VIEW,
    USER_PERMISSIONS.EDIT_SELF,
    TEAM_PERMISSIONS.VIEW,
    BILLING_PERMISSIONS.VIEW,
    PAGE_PERMISSIONS.VIEW,
    ANALYTICS_PERMISSIONS.VIEW,
    REPORT_PERMISSIONS.VIEW,
    API_PERMISSIONS.VIEW,
    WEBHOOK_PERMISSIONS.VIEW,
    INVOICE_PERMISSIONS.VIEW,
    AUDIT_PERMISSIONS.VIEW,
    KB_PERMISSIONS.VIEW
  ],
  
  // Content management permissions
  CONTENT_MANAGEMENT: [
    KB_PERMISSIONS.VIEW,
    KB_PERMISSIONS.CREATE,
    KB_PERMISSIONS.EDIT,
    KB_PERMISSIONS.PUBLISH,
    KB_PERMISSIONS.MANAGE_CATEGORIES,
    PAGE_PERMISSIONS.CREATE,
    PAGE_PERMISSIONS.EDIT,
    PAGE_PERMISSIONS.PUBLISH
  ],
  
  // Team management permissions
  TEAM_MANAGEMENT: [
    TEAM_PERMISSIONS.VIEW,
    TEAM_PERMISSIONS.INVITE,
    TEAM_PERMISSIONS.REMOVE,
    TEAM_PERMISSIONS.ASSIGN_ROLES,
    USER_PERMISSIONS.VIEW
  ],
  
  // Admin panel access
  ADMIN_ACCESS: [
    ADMIN_PERMISSIONS.ACCESS,
    ADMIN_USER_PERMISSIONS.VIEW,
    ADMIN_ACCOUNT_PERMISSIONS.VIEW,
    ADMIN_SETTINGS_PERMISSIONS.VIEW,
    ADMIN_AUDIT_PERMISSIONS.VIEW
  ],
  
  // Knowledge base admin permissions
  KB_ADMINISTRATION: [
    ADMIN_KB_PERMISSIONS.VIEW,
    ADMIN_KB_PERMISSIONS.MANAGE,
    ADMIN_KB_PERMISSIONS.MODERATE,
    ADMIN_KB_PERMISSIONS.ANALYTICS,
    ADMIN_KB_PERMISSIONS.SETTINGS
  ],
  
  // Billing operations
  BILLING_OPERATIONS: [
    BILLING_PERMISSIONS.VIEW,
    BILLING_PERMISSIONS.UPDATE,
    BILLING_PERMISSIONS.CANCEL,
    INVOICE_PERMISSIONS.VIEW,
    INVOICE_PERMISSIONS.DOWNLOAD
  ],
  
  // Analytics access
  ANALYTICS_ACCESS: [
    ANALYTICS_PERMISSIONS.VIEW,
    ANALYTICS_PERMISSIONS.EXPORT,
    REPORT_PERMISSIONS.VIEW,
    REPORT_PERMISSIONS.GENERATE,
    REPORT_PERMISSIONS.EXPORT
  ]
} as const;