import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';

/**
 * Hook for checking user permissions
 * Permissions are inherited from roles assigned to the user
 */
export const usePermissions = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  
  /**
   * Check if user has a specific permission
   * @param permission - Permission in resource.action format (e.g., 'users.create')
   */
  const hasPermission = (permission: string): boolean => {
    if (!user?.permissions) return false;
    
    // Check for exact permission
    if (user.permissions.includes(permission)) return true;
    
    // Check for wildcard permissions (e.g., 'users.*' matches 'users.create')
    const [resource, action] = permission.split('.');
    if (resource && action) {
      // Check for resource wildcard
      if (user.permissions.includes(`${resource}.*`)) return true;
      // Check for system wildcard
      if (user.permissions.includes('*.*') || user.permissions.includes('system.*')) {
        return true;
      }
    }
    
    return false;
  };
  
  /**
   * Check if user has any of the specified permissions
   * @param permissions - Array of permissions to check
   */
  const hasAnyPermission = (permissions: string[]): boolean => {
    return permissions.some(permission => hasPermission(permission));
  };
  
  /**
   * Check if user has all of the specified permissions
   * @param permissions - Array of permissions to check
   */
  const hasAllPermissions = (permissions: string[]): boolean => {
    return permissions.every(permission => hasPermission(permission));
  };
  
  // DEPRECATED: Role-based methods removed - use permission-based methods only
  // These methods are kept for backward compatibility but should not be used for access control
  
  /**
   * Check if user can perform an action on a resource
   * @param resource - Resource name (e.g., 'users')
   * @param action - Action name (e.g., 'create')
   */
  const canAccess = (resource: string, action: string): boolean => {
    return hasPermission(`${resource}.${action}`);
  };
  
  /**
   * Check if user has system administrator permissions
   */
  const isSystemAdmin = (): boolean => {
    return hasPermission('system.admin');
  };
  
  /**
   * Check if user has account management permissions
   */
  const isAccountManager = (): boolean => {
    return hasPermission('team.assign_roles') || hasPermission('admin.user.update');
  };
  
  /**
   * Check if user has administrative access
   */
  const isAdmin = (): boolean => {
    return hasPermission('admin.access');
  };
  
  /**
   * Get all permissions for the current user
   */
  const getAllPermissions = (): string[] => {
    return user?.permissions || [];
  };
  
  /**
   * Get all roles for the current user
   */
  const getAllRoles = (): string[] => {
    return user?.roles || [];
  };
  
  return {
    // Permission-based access control methods
    hasPermission,
    hasAnyPermission,
    hasAllPermissions,
    canAccess,
    
    // Convenience methods (permission-based)
    isSystemAdmin,
    isAccountManager,
    isAdmin,
    
    // Data accessors
    getAllPermissions,
    permissions: user?.permissions || [],
    
    // DEPRECATED: Role information for display only (not for access control)
    getAllRoles,
    roles: user?.roles || [],
  };
};