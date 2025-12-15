import React from 'react';
import { UserCheck, Shield, Settings } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { getUserInitials } from '@/shared/utils/userUtils';
import { usersApi } from '@/features/users/services/usersApi';
import { TeamMembersTableProps } from './types';

export const TeamMembersTable: React.FC<TeamMembersTableProps> = ({
  users,
  selectedUsers,
  currentUserId,
  actionLoading,
  onToggleSelectAll,
  onToggleUserSelection,
  onEditUser,
  onRolesModal,
  onImpersonateUser,
  onUserAction,
  onDeleteUser
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
              Roles
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
              <td className="px-6 py-4 whitespace-nowrap">
                <Badge className={usersApi.getRoleColor(user.roles?.[0] || 'account.member')}>
                  {usersApi.formatRoles(user.roles || [])}
                </Badge>
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
                    title="Manage Roles"
                  >
                    <Settings className="h-4 w-4" />
                  </Button>

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

                  {user.id !== currentUserId && (
                    user.status === 'suspended' ? (
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
                    )
                  )}

                  {user.id !== currentUserId && (
                    <Button
                      variant="danger"
                      size="sm"
                      onClick={() => onDeleteUser(user)}
                      disabled={actionLoading}
                      title="Delete User"
                    >
                      Delete
                    </Button>
                  )}
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
