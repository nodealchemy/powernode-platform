import React, { useState, useEffect, useCallback } from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { rolesApi, Role, UserWithRoles } from '../services/rolesApi';
import { usersApi } from '@/features/account/users/services/usersApi';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { hasPermissions } from '@/shared/utils/permissionUtils';
import { X, UserMinus, UserPlus, Users, Search, Mail, Shield, User } from 'lucide-react';

interface RoleUsersModalProps {
  role: Role;
  onClose: () => void;
}

export const RoleUsersModal: React.FC<RoleUsersModalProps> = ({
  role,
  onClose
}) => {
  const { user: currentUser } = useSelector((state: RootState) => state.auth);
  const { showNotification } = useNotifications();
  const [users, setUsers] = useState<UserWithRoles[]>([]);
  const [availableUsers, setAvailableUsers] = useState<UserWithRoles[]>([]);
  const [loading, setLoading] = useState(true);
  const [actionInProgress, setActionInProgress] = useState<string | null>(null);
  const [showAddUser, setShowAddUser] = useState(false);
  const [searchTerm, setSearchTerm] = useState('');

  const canManageUsers = hasPermissions(currentUser, ['users.update']);

  const loadUsers = useCallback(async () => {
    try {
      setLoading(true);
      
      // Get users assigned to this role
      const roleUsersResponse = await usersApi.getUsersByRole(role.id);
      const roleUsers = roleUsersResponse.data || [];
      
      // Get all users for the "available" list
      const allUsersResponse = await usersApi.getUsers();
      const allUsers = allUsersResponse.data || [];
      
      // Filter out users who already have this role
      const usersWithoutRole = allUsers.filter((user) => 
        !roleUsers.some((roleUser) => roleUser.id === user.id)
      );
      
      setUsers(roleUsers as UserWithRoles[]);
      setAvailableUsers(usersWithoutRole as UserWithRoles[]);
    } catch {
      showNotification('Failed to load users', 'error');
    } finally {
      setLoading(false);
    }
  }, [role.id, showNotification]);

  useEffect(() => {
    loadUsers();
  }, [loadUsers]);

  const handleRemoveUser = async (userId: string) => {
    if (!canManageUsers) {
      showNotification('You do not have permission to manage user roles', 'error');
      return;
    }

    try {
      setActionInProgress(userId);
      await rolesApi.removeRoleFromUser(role.id, userId);
      showNotification('User removed from role successfully', 'success');
      loadUsers();
    } catch {
      const httpError = error as { response?: { data?: { error?: string } } };
      showNotification(httpError?.response?.data?.error || 'Failed to remove user from role', 'error');
    } finally {
      setActionInProgress(null);
    }
  };

  const handleAddUser = async (userId: string) => {
    if (!canManageUsers) {
      showNotification('You do not have permission to manage user roles', 'error');
      return;
    }

    try {
      setActionInProgress(userId);
      await rolesApi.assignRoleToUser(role.id, userId);
      showNotification('User added to role successfully', 'success');
      setShowAddUser(false);
      setSearchTerm('');
      loadUsers();
    } catch {
      const httpError = error as { response?: { data?: { error?: string } } };
      showNotification(httpError?.response?.data?.error || 'Failed to add user to role', 'error');
    } finally {
      setActionInProgress(null);
    }
  };

  const filteredAvailableUsers = availableUsers.filter(user => {
    const searchLower = searchTerm.toLowerCase();
    return (
      user.email.toLowerCase().includes(searchLower) ||
      user.name?.toLowerCase().includes(searchLower)
    );
  });

  if (loading) {
    return (
      <Modal title={`Users with ${role.name} Role`} isOpen={true} onClose={onClose} maxWidth="lg">
        <div className="flex justify-center items-center h-64">
          <LoadingSpinner size="lg" />
        </div>
      </Modal>
    );
  }

  return (
    <Modal 
      title={`Users with ${role.name} Role`} 
      isOpen={true} 
      onClose={onClose} 
      maxWidth="lg"
    >
      <div className="space-y-6">
        {/* Role Info */}
        <div className="bg-gradient-to-r from-theme-surface to-theme-surface-hover border border-theme rounded-lg p-5">
          <div className="flex items-center justify-between">
            <div className="flex items-start space-x-3">
              <Shield className="w-6 h-6 text-theme-interactive-primary mt-0.5" />
              <div>
                <div className="flex items-center space-x-2">
                  <h3 className="font-semibold text-lg text-theme-primary">{role.name}</h3>
                  {role.system_role && (
                    <Badge variant="primary" size="xs">
                      Built-in
                    </Badge>
                  )}
                </div>
                <p className="text-sm text-theme-secondary mt-1">{role.description}</p>
                <div className="flex items-center space-x-2 mt-2">
                  <Badge variant="info" size="sm">
                    {role.permissions.length} permissions
                  </Badge>
                </div>
              </div>
            </div>
            <div className="text-center">
              <div className="text-3xl font-bold text-theme-interactive-primary">{users.length}</div>
              <div className="text-xs text-theme-tertiary uppercase tracking-wider">Users</div>
            </div>
          </div>
        </div>

        {/* Add User Section */}
        {canManageUsers && !role.system_role && (
          <div>
            {!showAddUser ? (
              <Button
                onClick={() => setShowAddUser(true)}
                variant="secondary"
                className="w-full"
              >
                <UserPlus className="w-4 h-4 mr-2" />
                Add User to Role
              </Button>
            ) : (
              <div className="bg-theme-surface border border-theme rounded-lg p-4">
                <div className="flex items-center justify-between mb-4">
                  <h4 className="font-medium text-theme-primary flex items-center space-x-2">
                    <UserPlus className="w-4 h-4 text-theme-interactive-primary" />
                    <span>Add User to Role</span>
                  </h4>
                  <Button
                    type="button"
                    variant="ghost"
                    size="sm"
                    onClick={() => {
                      setShowAddUser(false);
                      setSearchTerm('');
                    }}
                  >
                    <X className="w-4 h-4" />
                  </Button>
                </div>
                
                <div className="relative mb-3">
                  <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 w-4 h-4 text-theme-tertiary" />
                  <input
                    type="text"
                    value={searchTerm}
                    onChange={(e) => setSearchTerm(e.target.value)}
                    placeholder="Search users by name or email..."
                    className="w-full pl-10 pr-3 py-2 bg-theme-background border border-theme rounded-md text-theme-primary placeholder-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary focus:border-theme-interactive-primary transition-colors"
                  />
                </div>
                
                <div className="max-h-48 overflow-y-auto space-y-2">
                  {filteredAvailableUsers.length === 0 ? (
                    <p className="text-sm text-theme-tertiary text-center py-4">
                      No available users found
                    </p>
                  ) : (
                    filteredAvailableUsers.map(user => (
                      <div
                        key={user.id}
                        className="flex items-center justify-between p-3 bg-theme-background hover:bg-theme-surface-hover rounded-md transition-colors"
                      >
                        <div className="flex items-center space-x-3">
                          <div className="w-8 h-8 bg-theme-interactive-primary bg-opacity-10 rounded-full flex items-center justify-center">
                            <User className="w-4 h-4 text-theme-interactive-primary" />
                          </div>
                          <div>
                            <div className="font-medium text-theme-primary">
                              {user.name}
                            </div>
                            <div className="text-xs text-theme-tertiary flex items-center space-x-1">
                              <Mail className="w-3 h-3" />
                              <span>{user.email}</span>
                            </div>
                          </div>
                        </div>
                        <Button
                          size="sm"
                          variant="primary"
                          onClick={() => handleAddUser(user.id)}
                          disabled={actionInProgress === user.id}
                        >
                          {actionInProgress === user.id ? 'Adding...' : 'Add'}
                        </Button>
                      </div>
                    ))
                  )}
                </div>
              </div>
            )}
          </div>
        )}

        {/* Users List */}
        <div>
          <div className="flex items-center justify-between mb-4">
            <h4 className="font-medium text-theme-primary flex items-center space-x-2">
              <Users className="w-4 h-4 text-theme-interactive-primary" />
              <span>Assigned Users</span>
            </h4>
            <Badge variant="secondary" size="sm">
              {users.length} {users.length === 1 ? 'user' : 'users'}
            </Badge>
          </div>
          
          {users.length === 0 ? (
            <div className="bg-theme-surface border-2 border-dashed border-theme rounded-lg p-8 text-center">
              <div className="w-16 h-16 bg-theme-surface-hover rounded-full flex items-center justify-center mx-auto mb-3">
                <Users className="w-8 h-8 text-theme-tertiary" />
              </div>
              <p className="text-theme-secondary font-medium">No users assigned</p>
              <p className="text-sm text-theme-tertiary mt-1">Add users to grant them this role's permissions</p>
            </div>
          ) : (
            <div className="space-y-2">
              {users.map(user => (
                <div
                  key={user.id}
                  className="flex items-center justify-between bg-theme-surface border border-theme rounded-lg p-4 hover:bg-theme-surface-hover transition-colors"
                >
                  <div className="flex items-center space-x-3">
                    <div className="w-10 h-10 bg-gradient-to-br from-theme-interactive-primary to-theme-interactive-primary-hover rounded-full flex items-center justify-center text-white font-semibold">
                      {user.name?.[0]?.toUpperCase() || user.email?.[0]?.toUpperCase()}
                    </div>
                    <div>
                      <div className="flex items-center space-x-2">
                        <span className="font-medium text-theme-primary">
                          {user.name}
                        </span>
                        {user.id === currentUser?.id && (
                          <Badge variant="primary" size="xs">
                            You
                          </Badge>
                        )}
                      </div>
                      <div className="text-sm text-theme-tertiary flex items-center space-x-1 mt-0.5">
                        <Mail className="w-3 h-3" />
                        <span>{user.email}</span>
                      </div>
                      {user.roles && user.roles.length > 1 && (
                        <div className="mt-2 flex items-center flex-wrap gap-1">
                          {user.roles.filter(r => r !== role.name).map(r => (
                            <Badge key={r} variant="secondary" size="xs">
                              {r}
                            </Badge>
                          ))}
                        </div>
                      )}
                    </div>
                  </div>
                  
                  {canManageUsers && !role.system_role && user.id !== currentUser?.id && (
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={() => handleRemoveUser(user.id)}
                      disabled={actionInProgress === user.id}
                    >
                      <UserMinus className="w-4 h-4 mr-1" />
                      {actionInProgress === user.id ? 'Removing...' : 'Remove'}
                    </Button>
                  )}
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="flex justify-end pt-4 border-t border-theme">
          <Button variant="secondary" onClick={onClose}>
            <X className="w-4 h-4 mr-2" />
            Close
          </Button>
        </div>
      </div>
    </Modal>
  );
};

