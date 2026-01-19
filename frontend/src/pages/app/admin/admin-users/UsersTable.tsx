import React from 'react';
import { Users, UserCheck, Shield, MoreHorizontal, Unlock, Mail, Ban, CheckCircle, Key } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { getUserInitials } from '@/shared/utils/userUtils';
import { usersApi } from '@/features/account/users/services/usersApi';
import { UsersTableProps } from './types';

export const UsersTable: React.FC<UsersTableProps> = ({
  users,
  selectedUsers,
  currentUserId,
  openDropdownUserId,
  actionLoading,
  onToggleSelectAll,
  onToggleUserSelection,
  onEditUser,
  onRolesModal,
  onImpersonateUser,
  onUserAction,
  onDeleteUser,
  onToggleDropdown
}) => (
  <div className="bg-theme-surface rounded-lg shadow-sm overflow-hidden">
    <div className="overflow-x-auto">
      <table className="min-w-full divide-y divide-theme">
        <thead className="bg-theme-background">
          <tr>
            <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
              <input
                type="checkbox"
                checked={selectedUsers.size === users.length && users.length > 0}
                onChange={onToggleSelectAll}
                className="rounded border-theme focus:ring-theme-focus"
              />
            </th>
            <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
              User
            </th>
            <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
              Role
            </th>
            <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
              Status
            </th>
            <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
              Last Login
            </th>
            <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
              Created
            </th>
            <th className="px-6 py-3 text-right text-xs font-medium text-theme-secondary uppercase tracking-wider">
              Actions
            </th>
          </tr>
        </thead>
        <tbody className="divide-y divide-theme">
          {users.map((user) => (
            <tr key={user.id} className="hover:bg-theme-surface-hover">
              <td className="px-6 py-4 whitespace-nowrap">
                <input
                  type="checkbox"
                  checked={selectedUsers.has(user.id)}
                  onChange={() => onToggleUserSelection(user.id)}
                  className="rounded border-theme focus:ring-theme-focus"
                />
              </td>
              <td className="px-6 py-4 whitespace-nowrap">
                <div className="flex items-center">
                  <div className="flex-shrink-0 h-10 w-10">
                    <div className="h-10 w-10 rounded-full bg-theme-interactive-primary flex items-center justify-center">
                      <span className="text-white text-sm font-medium">
                        {getUserInitials(user)}
                      </span>
                    </div>
                  </div>
                  <div className="ml-4">
                    <div className="text-sm font-medium text-theme-primary">
                      {user.name}
                    </div>
                    <div className="text-sm text-theme-secondary">{user.email}</div>
                    {!user.email_verified && (
                      <Badge variant="warning" className="mt-1">Unverified</Badge>
                    )}
                    {user.locked && (
                      <Badge variant="danger" className="mt-1 ml-2">Locked</Badge>
                    )}
                  </div>
                </div>
              </td>
              <td className="px-6 py-4">
                <div className="flex flex-wrap gap-1">
                  {(user.roles || []).length === 0 ? (
                    <Badge className="bg-theme-surface border-theme text-theme-tertiary">
                      No roles
                    </Badge>
                  ) : (
                    user.roles.map((role, index) => (
                      <Badge key={index} className={usersApi.getRoleColor([role])}>
                        {role.replace('.', ' ').replace(/\b\w/g, l => l.toUpperCase())}
                      </Badge>
                    ))
                  )}
                </div>
              </td>
              <td className="px-6 py-4 whitespace-nowrap">
                <Badge className={usersApi.getStatusColor(user.status)}>
                  {user.status}
                </Badge>
              </td>
              <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-secondary">
                {user.last_login_at
                  ? new Date(user.last_login_at).toLocaleDateString()
                  : 'Never'
                }
              </td>
              <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-secondary">
                {new Date(user.created_at).toLocaleDateString()}
              </td>
              <td className="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                <div className="flex items-center justify-end space-x-1">
                  {/* Primary Actions */}
                  <Button
                    variant="secondary"
                    size="sm"
                    onClick={() => onEditUser(user)}
                    title="Edit User"
                  >
                    Edit
                  </Button>

                  <Button
                    variant="secondary"
                    size="sm"
                    onClick={() => onRolesModal(user)}
                    title="Manage User Roles"
                  >
                    <Users className="h-4 w-4" />
                  </Button>

                  {/* Impersonate Button (admin only, not for self) */}
                  {user.id !== currentUserId && (
                    <Button
                      variant="secondary"
                      size="sm"
                      onClick={() => onImpersonateUser(user)}
                      disabled={actionLoading}
                      title="Impersonate User"
                    >
                      <UserCheck className="h-4 w-4" />
                    </Button>
                  )}

                  {/* Status Actions */}
                  {user.status === 'suspended' ? (
                    <Button
                      variant="secondary"
                      size="sm"
                      onClick={() => onUserAction(user, 'activate')}
                      disabled={actionLoading}
                      title="Activate User"
                    >
                      <Shield className="h-4 w-4" />
                    </Button>
                  ) : (
                    <Button
                      variant="secondary"
                      size="sm"
                      onClick={() => onUserAction(user, 'suspend')}
                      disabled={actionLoading}
                      title="Suspend User"
                    >
                      <Shield className="h-4 w-4" />
                    </Button>
                  )}

                  {/* Additional Actions Dropdown */}
                  <UserActionsDropdown
                    user={user}
                    isOpen={openDropdownUserId === user.id}
                    currentUserId={currentUserId}
                    actionLoading={actionLoading}
                    onToggle={() => onToggleDropdown(user.id)}
                    onUserAction={onUserAction}
                  />

                  <Button
                    variant="danger"
                    size="sm"
                    onClick={() => onDeleteUser(user)}
                    title="Delete User"
                  >
                    Delete
                  </Button>
                </div>
              </td>
            </tr>
          ))}
        </tbody>
      </table>

      {users.length === 0 && (
        <div className="text-center py-12">
          <div className="text-theme-secondary">No users found.</div>
        </div>
      )}
    </div>
  </div>
);

// User Actions Dropdown Sub-component
interface UserActionsDropdownProps {
  user: UsersTableProps['users'][0];
  isOpen: boolean;
  currentUserId: string | undefined;
  actionLoading: boolean;
  onToggle: () => void;
  onUserAction: UsersTableProps['onUserAction'];
}

const UserActionsDropdown: React.FC<UserActionsDropdownProps> = ({
  user,
  isOpen,
  currentUserId,
  actionLoading,
  onToggle,
  onUserAction
}) => (
  <div className="relative inline-block text-left user-dropdown">
    <Button
      variant="secondary"
      size="sm"
      title="More Actions"
      onClick={onToggle}
    >
      <MoreHorizontal className="h-4 w-4" />
    </Button>

    {isOpen && (
      <div className="absolute right-0 mt-2 w-48 rounded-md shadow-lg bg-theme-surface ring-1 ring-black ring-opacity-5 z-50">
        <div className="py-1" role="menu">
          {/* Status Actions */}
          {user.status === 'active' && user.id !== currentUserId && (
            <button
              onClick={() => onUserAction(user, 'suspend')}
              className="flex items-center w-full px-4 py-2 text-sm text-theme-primary hover:bg-theme-surface-hover"
              role="menuitem"
              disabled={actionLoading}
            >
              <Ban className="h-4 w-4 mr-2 text-theme-error" />
              Suspend User
            </button>
          )}

          {user.status === 'suspended' && (
            <button
              onClick={() => onUserAction(user, 'activate')}
              className="flex items-center w-full px-4 py-2 text-sm text-theme-primary hover:bg-theme-surface-hover"
              role="menuitem"
              disabled={actionLoading}
            >
              <CheckCircle className="h-4 w-4 mr-2 text-theme-success" />
              Activate User
            </button>
          )}

          {/* Unlock Account */}
          {user.locked && (
            <button
              onClick={() => onUserAction(user, 'unlock')}
              className="flex items-center w-full px-4 py-2 text-sm text-theme-primary hover:bg-theme-surface-hover"
              role="menuitem"
              disabled={actionLoading}
            >
              <Unlock className="h-4 w-4 mr-2 text-theme-warning" />
              Unlock Account
            </button>
          )}

          {/* Email Actions */}
          {!user.email_verified && (
            <button
              onClick={() => onUserAction(user, 'resend_verification')}
              className="flex items-center w-full px-4 py-2 text-sm text-theme-primary hover:bg-theme-surface-hover"
              role="menuitem"
              disabled={actionLoading}
            >
              <Mail className="h-4 w-4 mr-2 text-theme-info" />
              Resend Verification
            </button>
          )}

          <button
            onClick={() => onUserAction(user, 'reset_password')}
            className="flex items-center w-full px-4 py-2 text-sm text-theme-primary hover:bg-theme-surface-hover"
            role="menuitem"
            disabled={actionLoading}
          >
            <Key className="h-4 w-4 mr-2 text-theme-interactive-primary" />
            Reset Password
          </button>
        </div>
      </div>
    )}
  </div>
);
