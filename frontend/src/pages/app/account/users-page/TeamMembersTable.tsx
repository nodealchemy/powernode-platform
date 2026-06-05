import React, { useState } from 'react';
import { UserCheck, Shield, Settings, BadgeCheck, KeyRound, ChevronRight, ChevronDown } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { EntityLink } from '@/shared/components/entity';
import { getUserInitials } from '@/shared/utils/userUtils';
import { usersApi } from '@/features/account/users/services/usersApi';
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
}) => {
  const [expandedUsers, setExpandedUsers] = useState<Set<string>>(new Set());

  const toggleRowExpansion = (userId: string) => {
    setExpandedUsers((prev) => {
      const next = new Set(prev);
      if (next.has(userId)) {
        next.delete(userId);
      } else {
        next.add(userId);
      }
      return next;
    });
  };

  return (
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
          {users.map((user) => {
            const isExpanded = expandedUsers.has(user.id);
            return (
            <React.Fragment key={user.id}>
            <tr className="hover:bg-theme-surface-hover">
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
                  <button
                    type="button"
                    onClick={() => toggleRowExpansion(user.id)}
                    className="mr-3 text-theme-secondary hover:text-theme-primary transition-colors"
                    title={isExpanded ? 'Collapse details' : 'Expand details'}
                    aria-label={isExpanded ? 'Collapse details' : 'Expand details'}
                  >
                    {isExpanded ? (
                      <ChevronDown className="h-4 w-4" />
                    ) : (
                      <ChevronRight className="h-4 w-4" />
                    )}
                  </button>
                  <div className="flex-shrink-0 h-10 w-10">
                    <div className="h-10 w-10 rounded-full bg-theme-interactive-primary flex items-center justify-center">
                      <span className="text-theme-on-primary text-sm font-medium">
                        {getUserInitials(user)}
                      </span>
                    </div>
                  </div>
                  <div className="ml-4">
                    <div className="text-sm font-medium text-theme-primary">
                      <EntityLink
                        type="user"
                        id={user.id}
                        label={user.name}
                        className="text-sm font-medium text-theme-primary"
                      />
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
                      variant="secondary"
                      size="sm"
                      onClick={() => onUserAction(user, 'reset_password')}
                      disabled={actionLoading}
                      title="Reset Password"
                    >
                      <KeyRound className="h-4 w-4" />
                    </Button>
                  )}

                  {process.env.NODE_ENV === 'development' && !user.email_verified && user.id !== currentUserId && (
                    <Button
                      variant="secondary"
                      size="sm"
                      onClick={() => onUserAction(user, 'manual_verify')}
                      disabled={actionLoading}
                      title="Verify Email (dev only)"
                    >
                      <BadgeCheck className="h-4 w-4" />
                    </Button>
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
            {isExpanded && (
              <tr className="bg-theme-background">
                <td colSpan={7} className="px-6 py-4">
                  <dl className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-x-6 gap-y-3 text-sm">
                    <div>
                      <dt className="text-theme-secondary">Status</dt>
                      <dd className="text-theme-primary">{user.status}</dd>
                    </div>
                    <div>
                      <dt className="text-theme-secondary">Roles</dt>
                      <dd className="text-theme-primary">
                        {(user.roles || []).length > 0 ? user.roles.join(', ') : 'No roles'}
                      </dd>
                    </div>
                    <div>
                      <dt className="text-theme-secondary">Email Verified</dt>
                      <dd className="text-theme-primary">{user.email_verified ? 'Yes' : 'No'}</dd>
                    </div>
                    {user.phone && (
                      <div>
                        <dt className="text-theme-secondary">Phone</dt>
                        <dd className="text-theme-primary">{user.phone}</dd>
                      </div>
                    )}
                    <div>
                      <dt className="text-theme-secondary">Account Locked</dt>
                      <dd className="text-theme-primary">{user.locked ? 'Yes' : 'No'}</dd>
                    </div>
                    <div>
                      <dt className="text-theme-secondary">Failed Login Attempts</dt>
                      <dd className="text-theme-primary">{user.failed_login_attempts}</dd>
                    </div>
                    {user.account?.name && (
                      <div>
                        <dt className="text-theme-secondary">Account</dt>
                        <dd className="text-theme-primary">{user.account.name}</dd>
                      </div>
                    )}
                    <div>
                      <dt className="text-theme-secondary">Last Login</dt>
                      <dd className="text-theme-primary">
                        {user.last_login_at
                          ? new Date(user.last_login_at).toLocaleString()
                          : 'Never'}
                      </dd>
                    </div>
                    <div>
                      <dt className="text-theme-secondary">Created</dt>
                      <dd className="text-theme-primary">
                        {new Date(user.created_at).toLocaleString()}
                      </dd>
                    </div>
                    <div>
                      <dt className="text-theme-secondary">Updated</dt>
                      <dd className="text-theme-primary">
                        {new Date(user.updated_at).toLocaleString()}
                      </dd>
                    </div>
                  </dl>
                </td>
              </tr>
            )}
            </React.Fragment>
            );
          })}
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
};
