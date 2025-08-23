// Permission constants for Powernode platform
// These must match the backend permission system in server/config/permissions.rb

// User & Team Management Permissions
export const USER_PERMISSIONS = {
  CREATE: 'users.create',
  READ: 'users.read', 
  UPDATE: 'users.update',
  DELETE: 'users.delete',
  MANAGE: 'users.manage'
} as const;

export const TEAM_PERMISSIONS = {
  INVITE: 'team.invite',
  REMOVE: 'team.remove', 
  MANAGE: 'team.manage',
  ROLES: 'team.roles'
} as const;

// Administrative Permissions
export const ADMIN_PERMISSIONS = {
  ACCESS: 'admin.access',
  USERS: 'admin.users',
  SYSTEM: 'admin.system', 
  SETTINGS: 'admin.settings'
} as const;

export const SYSTEM_PERMISSIONS = {
  ADMIN: 'system.admin',
  MAINTENANCE: 'system.maintenance',
  ACCOUNTS: 'accounts.manage'
} as const;

// Content & Resource Management Permissions
export const CONTENT_PERMISSIONS = {
  PAGES_CREATE: 'pages.create',
  PAGES_UPDATE: 'pages.update',
  PAGES_DELETE: 'pages.delete',
  CONTENT_MANAGE: 'content.manage'
} as const;

export const INFRASTRUCTURE_PERMISSIONS = {
  WORKERS_READ: 'workers.read',
  WORKERS_CREATE: 'workers.create', 
  WORKERS_MANAGE: 'workers.manage',
  VOLUMES_READ: 'volumes.read',
  VOLUMES_MANAGE: 'volumes.manage'
} as const;

// Business Operations Permissions
export const BILLING_PERMISSIONS = {
  READ: 'billing.read',
  UPDATE: 'billing.update',
  MANAGE: 'billing.manage',
  INVOICES: 'invoices.create',
  PAYMENTS: 'payments.process'
} as const;

export const ANALYTICS_PERMISSIONS = {
  READ: 'analytics.read',
  EXPORT: 'analytics.export', 
  REPORTS_GENERATE: 'reports.generate',
  REPORTS_DOWNLOAD: 'reports.download'
} as const;

// Security & Audit Permissions
export const SECURITY_PERMISSIONS = {
  AUDIT_READ: 'audit.read',
  AUDIT_EXPORT: 'audit.export',
  SECURITY_MANAGE: 'security.manage'
} as const;

// All permission constants grouped for easy access
export const PERMISSIONS = {
  USERS: USER_PERMISSIONS,
  TEAM: TEAM_PERMISSIONS,
  ADMIN: ADMIN_PERMISSIONS,
  SYSTEM: SYSTEM_PERMISSIONS,
  CONTENT: CONTENT_PERMISSIONS,
  INFRASTRUCTURE: INFRASTRUCTURE_PERMISSIONS,
  BILLING: BILLING_PERMISSIONS,
  ANALYTICS: ANALYTICS_PERMISSIONS,
  SECURITY: SECURITY_PERMISSIONS
} as const;

// Utility type for all permissions
export type Permission = 
  | typeof USER_PERMISSIONS[keyof typeof USER_PERMISSIONS]
  | typeof TEAM_PERMISSIONS[keyof typeof TEAM_PERMISSIONS]
  | typeof ADMIN_PERMISSIONS[keyof typeof ADMIN_PERMISSIONS]
  | typeof SYSTEM_PERMISSIONS[keyof typeof SYSTEM_PERMISSIONS]
  | typeof CONTENT_PERMISSIONS[keyof typeof CONTENT_PERMISSIONS]
  | typeof INFRASTRUCTURE_PERMISSIONS[keyof typeof INFRASTRUCTURE_PERMISSIONS]
  | typeof BILLING_PERMISSIONS[keyof typeof BILLING_PERMISSIONS]
  | typeof ANALYTICS_PERMISSIONS[keyof typeof ANALYTICS_PERMISSIONS]
  | typeof SECURITY_PERMISSIONS[keyof typeof SECURITY_PERMISSIONS];

// Helper function to check if a string is a valid permission
export const isValidPermission = (permission: string): permission is Permission => {
  const allPermissions = [
    ...Object.values(USER_PERMISSIONS),
    ...Object.values(TEAM_PERMISSIONS),
    ...Object.values(ADMIN_PERMISSIONS),
    ...Object.values(SYSTEM_PERMISSIONS),
    ...Object.values(CONTENT_PERMISSIONS),
    ...Object.values(INFRASTRUCTURE_PERMISSIONS),
    ...Object.values(BILLING_PERMISSIONS),
    ...Object.values(ANALYTICS_PERMISSIONS),
    ...Object.values(SECURITY_PERMISSIONS)
  ];
  return allPermissions.includes(permission as Permission);
};

// Common permission combinations for convenience
export const PERMISSION_GROUPS = {
  // Full user management (create, read, update, delete)
  USER_MANAGEMENT: [
    USER_PERMISSIONS.CREATE,
    USER_PERMISSIONS.READ,
    USER_PERMISSIONS.UPDATE,
    USER_PERMISSIONS.DELETE
  ],
  
  // Team management permissions
  TEAM_MANAGEMENT: [
    TEAM_PERMISSIONS.INVITE,
    TEAM_PERMISSIONS.REMOVE,
    TEAM_PERMISSIONS.MANAGE,
    USER_PERMISSIONS.READ
  ],
  
  // Admin panel access
  ADMIN_ACCESS: [
    ADMIN_PERMISSIONS.ACCESS,
    ADMIN_PERMISSIONS.USERS,
    ADMIN_PERMISSIONS.SYSTEM
  ],
  
  // Content management
  CONTENT_MANAGEMENT: [
    CONTENT_PERMISSIONS.PAGES_CREATE,
    CONTENT_PERMISSIONS.PAGES_UPDATE,
    CONTENT_PERMISSIONS.PAGES_DELETE,
    CONTENT_PERMISSIONS.CONTENT_MANAGE
  ],
  
  // Infrastructure management
  INFRASTRUCTURE_MANAGEMENT: [
    INFRASTRUCTURE_PERMISSIONS.WORKERS_MANAGE,
    INFRASTRUCTURE_PERMISSIONS.VOLUMES_MANAGE
  ],
  
  // Billing operations
  BILLING_OPERATIONS: [
    BILLING_PERMISSIONS.READ,
    BILLING_PERMISSIONS.UPDATE,
    BILLING_PERMISSIONS.MANAGE
  ],
  
  // Analytics access
  ANALYTICS_ACCESS: [
    ANALYTICS_PERMISSIONS.READ,
    ANALYTICS_PERMISSIONS.EXPORT,
    ANALYTICS_PERMISSIONS.REPORTS_GENERATE
  ]
} as const;