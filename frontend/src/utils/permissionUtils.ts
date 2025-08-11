import { User } from '../store/slices/authSlice';

// Permission constants
export const PERMISSIONS = {
  // Core access
  DASHBOARD_ACCESS: 'dashboard_access',
  
  // Analytics permissions
  BASIC_ANALYTICS: 'basic_analytics',
  ADVANCED_ANALYTICS: 'advanced_analytics',
  GLOBAL_ANALYTICS: 'global_analytics',
  
  // Management permissions
  USER_MANAGEMENT: 'user_management',
  ACCOUNT_MANAGEMENT: 'account_management',
  BILLING_MANAGEMENT: 'billing_management',
  
  // Administrative permissions
  SYSTEM_ADMINISTRATION: 'system_administration',
  SECURITY_ADMINISTRATION: 'security_administration',
  PLATFORM_MONITORING: 'platform_monitoring',
  
  // Technical permissions
  API_ACCESS: 'api_access',
  CUSTOM_INTEGRATIONS: 'custom_integrations',
  
  // Support permissions
  EMAIL_SUPPORT: 'email_support',
  PRIORITY_SUPPORT: 'priority_support',
  DEDICATED_SUPPORT: 'dedicated_support'
} as const;

export type Permission = typeof PERMISSIONS[keyof typeof PERMISSIONS];

// Role definitions with their associated permissions (single role system)
export const ROLE_PERMISSIONS: Record<string, Permission[]> = {
  'admin': [
    PERMISSIONS.DASHBOARD_ACCESS,
    PERMISSIONS.BASIC_ANALYTICS,
    PERMISSIONS.ADVANCED_ANALYTICS,
    PERMISSIONS.GLOBAL_ANALYTICS,
    PERMISSIONS.USER_MANAGEMENT,
    PERMISSIONS.ACCOUNT_MANAGEMENT,
    PERMISSIONS.BILLING_MANAGEMENT,
    PERMISSIONS.SYSTEM_ADMINISTRATION,
    PERMISSIONS.SECURITY_ADMINISTRATION,
    PERMISSIONS.PLATFORM_MONITORING,
    PERMISSIONS.API_ACCESS,
    PERMISSIONS.CUSTOM_INTEGRATIONS,
    PERMISSIONS.PRIORITY_SUPPORT,
    PERMISSIONS.DEDICATED_SUPPORT
  ],
  'owner': [
    PERMISSIONS.DASHBOARD_ACCESS,
    PERMISSIONS.BASIC_ANALYTICS,
    PERMISSIONS.ADVANCED_ANALYTICS,
    PERMISSIONS.USER_MANAGEMENT,
    PERMISSIONS.ACCOUNT_MANAGEMENT,
    PERMISSIONS.BILLING_MANAGEMENT,
    PERMISSIONS.API_ACCESS,
    PERMISSIONS.CUSTOM_INTEGRATIONS,
    PERMISSIONS.PRIORITY_SUPPORT
  ],
  'member': [
    PERMISSIONS.DASHBOARD_ACCESS,
    PERMISSIONS.BASIC_ANALYTICS
  ]
};

/**
 * Get permissions for a given role
 */
export const getRolePermissions = (role: string): Permission[] => {
  return ROLE_PERMISSIONS[role as keyof typeof ROLE_PERMISSIONS] || [PERMISSIONS.DASHBOARD_ACCESS];
};

/**
 * Check if a user has specific permissions
 */
export const hasPermissions = (user: User | null, requiredPermissions?: string[]): boolean => {
  if (!user || !requiredPermissions || requiredPermissions.length === 0) return true;
  
  // Admin role has access to everything
  if (user.role === 'admin') return true;
  
  // Get permissions for user role
  const userPermissions = getRolePermissions(user.role);
  
  return requiredPermissions.some(permission => userPermissions.includes(permission as Permission));
};

/**
 * Check if a user has specific roles
 */
export const hasRoles = (user: User | null, requiredRoles?: string[]): boolean => {
  if (!user || !requiredRoles || requiredRoles.length === 0) return true;
  
  return requiredRoles.includes(user.role);
};

/**
 * Comprehensive permission check - user must satisfy both role and permission requirements
 */
export const hasAccess = (
  user: User | null, 
  requiredPermissions?: string[], 
  requiredRoles?: string[]
): boolean => {
  if (!user) return false;
  
  // Admin role has access to everything
  if (user.role === 'admin') return true;
  
  // Check role requirements first
  if (requiredRoles && requiredRoles.length > 0) {
    if (!hasRoles(user, requiredRoles)) return false;
  }
  
  // Check permission requirements
  if (requiredPermissions && requiredPermissions.length > 0) {
    return hasPermissions(user, requiredPermissions);
  }
  
  return true;
};

/**
 * Get all permissions for a user
 */
export const getUserPermissions = (user: User | null): Permission[] => {
  if (!user) return [];
  
  // Get permissions for user role
  return getRolePermissions(user.role);
};

/**
 * Check if user can access admin features (system-wide)
 * Note: 'admin' role is for system administrators only
 * 'owner' role is for account owners and does NOT have system admin access
 */
export const hasAdminAccess = (user: User | null): boolean => {
  // Only system administrators should have access to system-wide admin features
  return hasRoles(user, ['admin']);
};

/**
 * Check if user can manage their account's team
 */
export const hasTeamManagementAccess = (user: User | null): boolean => {
  return hasRoles(user, ['owner', 'admin']);
};

/**
 * Check if user is account owner
 */
export const isAccountOwner = (user: User | null): boolean => {
  if (!user) return false;
  
  return user.role === 'owner';
};

/**
 * Check if user can access billing features
 */
export const hasBillingAccess = (user: User | null): boolean => {
  return hasPermissions(user, [PERMISSIONS.BILLING_MANAGEMENT]);
};

/**
 * Check if user can access analytics features
 */
export const hasAnalyticsAccess = (user: User | null): boolean => {
  return hasPermissions(user, [PERMISSIONS.BASIC_ANALYTICS]);
};

/**
 * Check if user can access advanced analytics features
 */
export const hasAdvancedAnalyticsAccess = (user: User | null): boolean => {
  return hasPermissions(user, [PERMISSIONS.ADVANCED_ANALYTICS]);
};

/**
 * Debug utility - Get user roles information
 */
export const getUserRolesInfo = (user: User | null) => {
  if (!user) return { hasUser: false };
  
  return {
    hasUser: true,
    email: user.email,
    role: user.role,
    isAdmin: hasAdminAccess(user),
    isOwner: isAccountOwner(user),
    allPermissions: getUserPermissions(user)
  };
};