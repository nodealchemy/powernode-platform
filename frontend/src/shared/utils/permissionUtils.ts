import { User } from '@/shared/services/slices/authSlice';
import { PERMISSIONS } from '@/shared/constants/permissions';

/**
 * Check if a user has specific permissions using the new permission-based system
 * Supports wildcard permissions (e.g., 'users.*' matches 'users.create', 'users.read', etc.)
 * Also supports system.admin permission which grants all permissions
 */
export const hasPermissions = (user: User | null, requiredPermissions?: string[]): boolean => {
  if (!user) return false;
  if (!requiredPermissions || requiredPermissions.length === 0) return true;

  // system.admin permission grants access to all permissions
  if (user.permissions?.includes('system.admin')) return true;

  // Check if user has the required permissions
  return requiredPermissions.some(required => {
    // Direct permission check
    if (user.permissions?.includes(required)) return true;

    // Check for wildcard permissions
    const requiredParts = required.split('.');
    if (requiredParts.length === 2) {
      const wildcardPermission = `${requiredParts[0]}.*`;
      if (user.permissions?.includes(wildcardPermission)) return true;

      // Check for all permissions wildcard
      if (user.permissions?.includes('*')) return true;
    }

    return false;
  });
};


/**
 * Comprehensive access check - user must satisfy permission requirements
 * This is the primary access control function for the platform
 */
export const hasAccess = (
  user: User | null, 
  requiredPermissions?: string[]
): boolean => {
  if (!user) return false;
  
  // Check permission requirements
  if (requiredPermissions && requiredPermissions.length > 0) {
    return hasPermissions(user, requiredPermissions);
  }
  
  // If no requirements specified, allow access
  return true;
};
/**
 * Check if user can access admin features (system-wide)
 */
export const hasAdminAccess = (user: User | null): boolean => {
  return hasPermissions(user, ['admin.access']);
};

/**
 * Check if user can manage their account's team
 */
export const hasTeamManagementAccess = (user: User | null): boolean => {
  return hasPermissions(user, ['team.invite']) || hasPermissions(user, ['team.assign_roles']) || hasPermissions(user, ['admin.user.update']);
};

/**
 * Check if user has account management permissions
 */
export const isAccountManager = (user: User | null): boolean => {
  if (!user) return false;
  return hasPermissions(user, ['team.assign_roles']) || hasPermissions(user, ['admin.user.update']);
};

/**
 * Check if user can access billing features
 */
export const hasBillingAccess = (user: User | null): boolean => {
  return hasPermissions(user, ['billing.read']);
};

/**
 * Check if user can access analytics features
 */
export const hasAnalyticsAccess = (user: User | null): boolean => {
  return hasPermissions(user, ['analytics.read']);
};

/**
 * Check if user can view knowledge base
 */
export const hasKnowledgeBaseAccess = (user: User | null): boolean => {
  return hasPermissions(user, ['kb.read']);
};
/**
 * Check if user can manage knowledge base
 */
export const canManageKnowledgeBase = (user: User | null): boolean => {
  return hasPermissions(user, ['kb.create', 'kb.update', 'kb.publish']);
};
/**
 * Check if user has permission for a specific action on a resource
 * @param user The current user
 * @param resource The resource name (e.g., 'users', 'billing')
 * @param action The action name (e.g., 'create', 'read', 'update', 'delete')
 */
export const canPerformAction = (
  user: User | null,
  resource: string,
  action: string
): boolean => {
  if (!user) return false;
  
  const permission = `${resource}.${action}`;
  return hasPermissions(user, [permission]);
};

/**
 * Get all permissions for a specific resource
 */
export const getResourcePermissions = (
  user: User | null,
  resource: string
): string[] => {
  if (!user || !user.permissions) return [];
  
  return user.permissions.filter(permission => {
    return permission.startsWith(`${resource}.`) || permission === `${resource}.*`;
  });
};
// ========================================
// Enhanced Permission Utilities with Constants
// ========================================

/**
 * Check if user can manage users (create, update, delete)
 */
export const canManageUsers = (user: User | null): boolean => {
  return hasPermissions(user, [PERMISSIONS.ADMIN_USER.CREATE]);
};

/**
 * Check if user can manage team (invite, remove, manage roles)
 */
export const canManageTeam = (user: User | null): boolean => {
  return hasPermissions(user, [PERMISSIONS.TEAM.INVITE]);
};
/**
 * Check if user can manage billing
 */
export const canManageBilling = (user: User | null): boolean => {
  return hasPermissions(user, [PERMISSIONS.BILLING.UPDATE]);
};
/**
 * Check if user can export analytics
 */
export const canExportAnalytics = (user: User | null): boolean => {
  return hasPermissions(user, [PERMISSIONS.ANALYTICS.EXPORT]);
};