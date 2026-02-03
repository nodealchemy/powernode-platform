import React, { useState, useEffect, useCallback } from 'react';
import { useSelector } from 'react-redux';
import { Navigate } from 'react-router-dom';
import { RootState } from '@/shared/services';
import { hasPermissions } from '@/shared/utils/permissionUtils';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { Plus, RefreshCw, Edit2, Trash2, Users, Shield } from 'lucide-react';
import { rolesApi, Role, Permission } from '@/features/admin/roles/services/rolesApi';
import { RoleFormModal } from '@/features/admin/roles/components/RoleFormModal';
import { RoleUsersModal } from '@/features/admin/roles/components/RoleUsersModal';

export const AdminRolesPage: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  const { showNotification } = useNotifications();
  const { confirm, ConfirmationDialog } = useConfirmation();

  // WebSocket for real-time updates
  usePageWebSocket({
    pageType: 'admin',
    onDataUpdate: () => {
      // Trigger data refresh if needed
    }
  });

  const [roles, setRoles] = useState<Role[]>([]);
  const [permissions, setPermissions] = useState<Permission[]>([]);
  const [loading, setLoading] = useState(true);
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [showEditModal, setShowEditModal] = useState(false);
  const [showUsersModal, setShowUsersModal] = useState(false);
  const [selectedRole, setSelectedRole] = useState<Role | null>(null);

  // Use a ref to access showNotification without causing re-renders
  const showNotificationRef = React.useRef(showNotification);
  React.useEffect(() => {
    showNotificationRef.current = showNotification;
  }, [showNotification]);

  const loadRoles = useCallback(async () => {
    try {
      setLoading(true);
      const [rolesResponse, permissionsResponse] = await Promise.all([
        rolesApi.getRoles(),
        rolesApi.getPermissions()
      ]);
      setRoles(rolesResponse.data || []);
      setPermissions(permissionsResponse.data || []);
    } catch (_error) {
      showNotificationRef.current('Failed to load roles', 'error');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadRoles();
  }, [loadRoles]);

  // Check if user has role management permissions
  const canManageRoles = hasPermissions(user, ['admin.role.create', 'admin.role.update', 'admin.role.delete']);
  const canReadRoles = hasPermissions(user, ['admin.role.read']);

  // Redirect if user doesn't have permission to view roles
  if (!canReadRoles) {
    return <Navigate to="/app" replace />;
  }

  const handleCreateRole = () => {
    setSelectedRole(null);
    setShowCreateModal(true);
  };

  const handleEditRole = (role: Role) => {
    if (!canManageRoles) {
      showNotification('You do not have permission to edit roles', 'error');
      return;
    }
    
    if (isBuiltInRole(role)) {
      showNotification('Built-in roles cannot be modified', 'warning');
      return;
    }
    
    setSelectedRole(role);
    setShowEditModal(true);
  };

  const handleDeleteRole = async (role: Role) => {
    if (!canManageRoles) {
      showNotification('You do not have permission to delete roles', 'error');
      return;
    }

    if (isBuiltInRole(role)) {
      showNotification('Built-in roles cannot be deleted', 'warning');
      return;
    }

    if (role.users_count > 0) {
      showNotification('Cannot delete role that is assigned to users', 'error');
      return;
    }

    confirm({
      title: 'Delete Role',
      message: `Are you sure you want to delete the role "${role.name}"? This action cannot be undone.`,
      confirmLabel: 'Delete',
      variant: 'danger',
      onConfirm: async () => {
        try {
          await rolesApi.deleteRole(role.id);
          showNotification('Role deleted successfully', 'success');
          loadRoles();
        } catch (error) {
          showNotification(error instanceof Error ? error.message : 'Failed to delete role', 'error');
        }
      }
    });
  };

  const handleViewUsers = (role: Role) => {
    setSelectedRole(role);
    setShowUsersModal(true);
  };

  const handleRoleSaved = () => {
    setShowCreateModal(false);
    setShowEditModal(false);
    loadRoles();
    showNotification('Role saved successfully', 'success');
  };

  const getPageActions = (): PageAction[] => {
    const actions: PageAction[] = [
      {
        id: 'refresh',
        label: 'Refresh',
        onClick: loadRoles,
        variant: 'secondary',
        icon: RefreshCw,
        disabled: loading
      }
    ];

    if (canManageRoles) {
      actions.push({
        id: 'create-role',
        label: 'Create Role',
        onClick: handleCreateRole,
        variant: 'primary',
        icon: Plus
      });
    }

    return actions;
  };

  const getBreadcrumbs = () => [
    { label: 'Dashboard', href: '/app' },
    { label: 'Admin', href: '/app/admin' },
    { label: 'Roles & Permissions' }
  ];

  const groupPermissionsByResource = (permissions: Permission[]) => {
    const grouped: Record<string, Permission[]> = {};
    permissions.forEach(permission => {
      if (!grouped[permission.resource]) {
        grouped[permission.resource] = [];
      }
      grouped[permission.resource].push(permission);
    });
    return grouped;
  };

  // Built-in roles that cannot be modified or deleted
  const BUILT_IN_ROLES = ['admin', 'billing_admin', 'manager', 'member', 'owner', 'super_admin'];
  
  const isBuiltInRole = (role: Role) => {
    return BUILT_IN_ROLES.includes(role.name) || role.system_role;
  };

  if (loading) {
    return (
      <PageContainer
        title="Roles & Permissions"
        breadcrumbs={getBreadcrumbs()}
        actions={getPageActions()}
      >
        <div className="flex justify-center items-center h-64">
          <LoadingSpinner size="lg" />
        </div>
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title="Roles & Permissions"
      description="Manage system roles and their associated permissions"
      breadcrumbs={getBreadcrumbs()}
      actions={getPageActions()}
    >
      <div className="space-y-6">
        {/* Built-in Roles Section */}
        <div>
          <div className="flex items-center space-x-2 mb-4">
            <Shield className="w-5 h-5 text-theme-interactive-primary" />
            <h2 className="text-lg font-semibold text-theme-primary">Built-in Roles</h2>
            <Badge variant="secondary" size="sm">
              {roles.filter(r => isBuiltInRole(r)).length}
            </Badge>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {roles.filter(r => isBuiltInRole(r)).map(role => (
              <div key={role.id} className="bg-gradient-to-br from-theme-surface to-theme-surface-hover border border-theme rounded-lg p-5 hover:shadow-lg transition-shadow">
                <div className="flex items-start justify-between mb-3">
                  <div className="flex items-center space-x-2">
                    <div className="relative">
                      <div className="absolute inset-0 bg-gradient-to-br from-theme-interactive-primary/15 to-theme-interactive-primary/5 rounded-lg blur-md"></div>
                      <div className="relative w-8 h-8 bg-theme-surface/50 backdrop-blur-sm rounded-lg flex items-center justify-center">
                        <Shield className="w-4 h-4 text-theme-interactive-primary" />
                      </div>
                    </div>
                    <h3 className="font-semibold text-theme-primary capitalize">{role.name.replace(/_/g, ' ')}</h3>
                  </div>
                  <Badge variant="primary" size="xs">
                    System
                  </Badge>
                </div>
                <p className="text-sm text-theme-secondary mb-4 line-clamp-2">{role.description}</p>
                <div className="flex items-center justify-between pt-3 border-t border-theme">
                  <div className="flex items-center space-x-2">
                    <Badge variant="secondary" size="xs">
                      {role.permissions.length} permissions
                    </Badge>
                    <Badge variant={role.users_count > 0 ? 'success' : 'secondary'} size="xs">
                      {role.users_count} {role.users_count === 1 ? 'user' : 'users'}
                    </Badge>
                  </div>
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => handleViewUsers(role)}
                  >
                    <Users className="w-4 h-4" />
                  </Button>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Custom Roles Section */}
        <div>
          <div className="flex items-center justify-between mb-4">
            <div className="flex items-center space-x-2">
              <Shield className="w-5 h-5 text-theme-secondary" />
              <h2 className="text-lg font-semibold text-theme-primary">Custom Roles</h2>
              <Badge variant="secondary" size="sm">
                {roles.filter(r => !isBuiltInRole(r)).length}
              </Badge>
            </div>
            {canManageRoles && roles.filter(r => !isBuiltInRole(r)).length > 0 && (
              <Button onClick={handleCreateRole} variant="primary" size="sm">
                <Plus className="w-4 h-4 mr-2" />
                New Role
              </Button>
            )}
          </div>
          {roles.filter(r => !isBuiltInRole(r)).length === 0 ? (
            <div className="bg-theme-surface border-2 border-dashed border-theme rounded-lg p-12 text-center">
              <div className="w-16 h-16 bg-theme-surface-hover rounded-full flex items-center justify-center mx-auto mb-4">
                <Shield className="w-8 h-8 text-theme-tertiary" />
              </div>
              <h3 className="text-lg font-semibold text-theme-primary mb-2">No custom roles yet</h3>
              <p className="text-theme-secondary mb-6 max-w-md mx-auto">
                Create custom roles to define specific permission sets tailored to your organization's needs.
              </p>
              {canManageRoles && (
                <Button onClick={handleCreateRole} variant="primary">
                  <Plus className="w-4 h-4 mr-2" />
                  Create Your First Role
                </Button>
              )}
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              {roles.filter(r => !isBuiltInRole(r)).map(role => (
                <div key={role.id} className="bg-theme-surface border border-theme rounded-lg p-5 hover:shadow-md transition-shadow">
                  <div className="flex items-start justify-between mb-3">
                    <div className="flex items-center space-x-2">
                      <div className="relative">
                        <div className="absolute inset-0 bg-gradient-to-br from-theme-secondary/15 to-theme-secondary/5 rounded-lg blur-md"></div>
                        <div className="relative w-8 h-8 bg-theme-surface/50 backdrop-blur-sm rounded-lg flex items-center justify-center">
                          <Shield className="w-4 h-4 text-theme-secondary" />
                        </div>
                      </div>
                      <h3 className="font-semibold text-theme-primary">{role.name}</h3>
                    </div>
                    {canManageRoles && (
                      <div className="flex items-center space-x-1">
                        <Button
                          variant="ghost"
                          size="xs"
                          onClick={() => handleEditRole(role)}
                        >
                          <Edit2 className="w-3.5 h-3.5" />
                        </Button>
                        <Button
                          variant="ghost"
                          size="xs"
                          onClick={() => handleDeleteRole(role)}
                          className="hover:text-theme-error"
                        >
                          <Trash2 className="w-3.5 h-3.5" />
                        </Button>
                      </div>
                    )}
                  </div>
                  <p className="text-sm text-theme-secondary mb-4 line-clamp-2">{role.description}</p>
                  <div className="flex items-center justify-between pt-3 border-t border-theme">
                    <div className="flex items-center space-x-2">
                      <Badge variant="secondary" size="xs">
                        {role.permissions.length} permissions
                      </Badge>
                      <Badge variant={role.users_count > 0 ? 'success' : 'secondary'} size="xs">
                        {role.users_count} {role.users_count === 1 ? 'user' : 'users'}
                      </Badge>
                    </div>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => handleViewUsers(role)}
                    >
                      <Users className="w-4 h-4" />
                    </Button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Permissions Reference */}
        <div>
          <div className="flex items-center justify-between mb-4">
            <div className="flex items-center space-x-2">
              <Shield className="w-5 h-5 text-theme-interactive-primary" />
              <h2 className="text-lg font-semibold text-theme-primary">Permission Reference</h2>
              <Badge variant="info" size="sm">
                {permissions.length} total
              </Badge>
            </div>
          </div>
          <div className="bg-theme-surface border border-theme rounded-lg p-6">
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6">
              {Object.entries(groupPermissionsByResource(permissions)).map(([resource, perms]) => (
                <div key={resource} className="space-y-3">
                  <div className="flex items-center space-x-2 pb-2 border-b border-theme">
                    <div className="relative">
                      <div className="absolute inset-0 bg-gradient-to-br from-theme-interactive-primary/15 to-theme-interactive-primary/5 rounded blur-md"></div>
                      <div className="relative w-6 h-6 bg-theme-surface/50 backdrop-blur-sm rounded flex items-center justify-center">
                        <Shield className="w-3 h-3 text-theme-interactive-primary" />
                      </div>
                    </div>
                    <h4 className="font-semibold text-theme-primary capitalize text-sm">
                      {resource.replace(/_/g, ' ')}
                    </h4>
                    <Badge variant="secondary" size="xs">
                      {perms.length}
                    </Badge>
                  </div>
                  <div className="space-y-2">
                    {perms.map(permission => (
                      <div key={permission.id} className="group hover:bg-theme-surface-hover p-2 rounded-md transition-colors">
                        <code className="text-xs font-medium text-theme-interactive-primary">
                          {permission.action}
                        </code>
                        <p className="text-xs text-theme-secondary mt-0.5 leading-relaxed">
                          {permission.description}
                        </p>
                      </div>
                    ))}
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>

      {/* Modals */}
      {showCreateModal && (
        <RoleFormModal
          permissions={permissions}
          onSave={handleRoleSaved}
          onClose={() => setShowCreateModal(false)}
        />
      )}

      {showEditModal && selectedRole && (
        <RoleFormModal
          role={selectedRole}
          permissions={permissions}
          onSave={handleRoleSaved}
          onClose={() => setShowEditModal(false)}
        />
      )}

      {showUsersModal && selectedRole && (
        <RoleUsersModal
          role={selectedRole}
          onClose={() => setShowUsersModal(false)}
        />
      )}
      {ConfirmationDialog}
    </PageContainer>
  );
};

export default AdminRolesPage;