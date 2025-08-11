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

// Role definitions with their associated permissions
export const ROLE_PERMISSIONS: Record<string, Permission[]> = {
  'owner': [
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
  'admin': [
    PERMISSIONS.DASHBOARD_ACCESS,
    PERMISSIONS.BASIC_ANALYTICS,
    PERMISSIONS.ADVANCED_ANALYTICS,
    PERMISSIONS.USER_MANAGEMENT,
    PERMISSIONS.ACCOUNT_MANAGEMENT,
    PERMISSIONS.BILLING_MANAGEMENT,
    PERMISSIONS.SYSTEM_ADMINISTRATION,
    PERMISSIONS.SECURITY_ADMINISTRATION,
    PERMISSIONS.PRIORITY_SUPPORT
  ],
  'billing_manager': [
    PERMISSIONS.DASHBOARD_ACCESS,
    PERMISSIONS.BASIC_ANALYTICS,
    PERMISSIONS.ACCOUNT_MANAGEMENT,
    PERMISSIONS.BILLING_MANAGEMENT,
    PERMISSIONS.EMAIL_SUPPORT
  ],
  'sales_manager': [
    PERMISSIONS.DASHBOARD_ACCESS,
    PERMISSIONS.BASIC_ANALYTICS,
    PERMISSIONS.ADVANCED_ANALYTICS,
    PERMISSIONS.USER_MANAGEMENT,
    PERMISSIONS.ACCOUNT_MANAGEMENT,
    PERMISSIONS.EMAIL_SUPPORT
  ],
  'customer_manager': [
    PERMISSIONS.DASHBOARD_ACCESS,
    PERMISSIONS.BASIC_ANALYTICS,
    PERMISSIONS.USER_MANAGEMENT,
    PERMISSIONS.ACCOUNT_MANAGEMENT,
    PERMISSIONS.EMAIL_SUPPORT
  ],
  'content_manager': [
    PERMISSIONS.DASHBOARD_ACCESS,
    PERMISSIONS.BASIC_ANALYTICS,
    PERMISSIONS.ACCOUNT_MANAGEMENT,
    PERMISSIONS.EMAIL_SUPPORT
  ],
  'analyst': [
    PERMISSIONS.DASHBOARD_ACCESS,
    PERMISSIONS.BASIC_ANALYTICS,
    PERMISSIONS.ADVANCED_ANALYTICS
  ],
  'support': [
    PERMISSIONS.DASHBOARD_ACCESS,
    PERMISSIONS.BASIC_ANALYTICS,
    PERMISSIONS.USER_MANAGEMENT,
    PERMISSIONS.EMAIL_SUPPORT
  ],
  'viewer': [
    PERMISSIONS.DASHBOARD_ACCESS,
    PERMISSIONS.BASIC_ANALYTICS
  ],
  'user': [
    PERMISSIONS.DASHBOARD_ACCESS
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
  
  // Owner role has access to everything
  if (user.role === 'owner') return true;
  
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
  
  // Owner role has access to everything
  if (user.role === 'owner') return true;
  
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
  return getRolePermissions(user.role);
};

/**
 * Check if user can access admin features
 */
export const hasAdminAccess = (user: User | null): boolean => {
  return hasRoles(user, ['owner', 'admin']);
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