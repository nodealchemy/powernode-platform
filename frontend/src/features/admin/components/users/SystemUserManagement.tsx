import React, { useState, useEffect } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { usersApi, User, AdminAccount } from '@/features/account/users/services/usersApi';
import { hasAdminAccess } from '@/shared/utils/permissionUtils';
import { getUserInitials } from '@/shared/utils/userUtils';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { ImpersonateUserModal } from './ImpersonateUserModal';
import { CreateUserModal } from './CreateUserModal';

export const SystemUserManagement: React.FC = () => {
  const { user: currentUser } = useSelector((state: RootState) => state.auth);
  const { confirm, ConfirmationDialog } = useConfirmation();
  const [users, setUsers] = useState<User[]>([]);
  const [accounts, setAccounts] = useState<AdminAccount[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedUser, setSelectedUser] = useState<User | null>(null);
  const [showDetailsModal, setShowDetailsModal] = useState(false);
  const [showImpersonateModal, setShowImpersonateModal] = useState(false);
  const [showCreateUserModal, setShowCreateUserModal] = useState(false);
  const [impersonateUserId, setImpersonateUserId] = useState<string | null>(null);
  const [filters, setFilters] = useState({
    search: '',
    accountId: '',
    role: '',
    status: '',
  });

  // Check admin access
  const isAdmin = hasAdminAccess(currentUser);

  useEffect(() => {
    if (!isAdmin) {
      return;
    }
    loadSystemData();
  }, [isAdmin]);

  const loadSystemData = async () => {
    try {
      setLoading(true);
      // Load all users system-wide
      const [usersResponse, accountsResponse] = await Promise.all([
        usersApi.getAllUsers(),
        usersApi.getAllAccounts(),
      ]);
      
      if (usersResponse.success) {
        setUsers(usersResponse.data);
      }
      if (accountsResponse?.success) {
        setAccounts(accountsResponse.data?.accounts || []);
      }
    } catch (error) {
    } finally {
      setLoading(false);
    }
  };

  const handleSuspendUser = async (userId: string) => {
    confirm({
      title: 'Suspend User',
      message: 'Are you sure you want to suspend this user?',
      confirmLabel: 'Suspend',
      variant: 'warning',
      onConfirm: async () => {
        try {
          await usersApi.suspendUser(userId);
          loadSystemData();
        } catch (error) {
        }
      }
    });
  };

  const handleActivateUser = async (userId: string) => {
    try {
      await usersApi.activateUser(userId);
      loadSystemData();
    } catch (error) {
    }
  };

  const handleDeleteUser = async (userId: string) => {
    confirm({
      title: 'Delete User',
      message: 'Are you sure you want to permanently delete this user? This action cannot be undone.',
      confirmLabel: 'Delete',
      variant: 'danger',
      onConfirm: async () => {
        try {
          await usersApi.deleteUser(userId);
          loadSystemData();
        } catch (error) {
        }
      }
    });
  };

  const handleImpersonateUser = (userId: string) => {
    setImpersonateUserId(userId);
    setShowImpersonateModal(true);
  };

  const getRoleBadge = (user: User) => {
    const roleColors = {
      'system.admin': 'bg-theme-error bg-opacity-10 text-theme-error',
      'account.manager': 'bg-theme-success bg-opacity-10 text-theme-success',
      'account.member': 'bg-theme-info bg-opacity-10 text-theme-info',
      'billing.manager': 'bg-theme-warning bg-opacity-10 text-theme-warning',
    };

    if (user.roles && user.roles.length > 0) {
      const formatRoleName = (role: string) => role.replace('.', ' ').replace(/\b\w/g, l => l.toUpperCase());
      
      return (
        <div className="flex flex-wrap gap-1">
          {user.roles.slice(0, 2).map((role, index) => (
            <span key={index} className={`text-xs px-2 py-1 rounded-full ${roleColors[role as keyof typeof roleColors] || roleColors['account.member']}`}>
              {formatRoleName(role)}
            </span>
          ))}
          {user.roles.length > 2 && (
            <span className="text-xs px-2 py-1 rounded-full bg-theme-surface text-theme-tertiary">
              +{user.roles.length - 2}
            </span>
          )}
        </div>
      );
    }
    
    // Fallback for users without roles
    return (
      <span className="text-xs px-2 py-1 rounded-full bg-theme-surface text-theme-tertiary">
        No roles
      </span>
    );
  };

  const getStatusBadge = (status: string) => {
    const statusColors = {
      active: 'bg-theme-success bg-opacity-10 text-theme-success',
      invited: 'bg-theme-warning bg-opacity-10 text-theme-warning',
      suspended: 'bg-theme-error bg-opacity-10 text-theme-error',
      inactive: 'bg-theme-surface text-theme-tertiary',
    };

    return (
      <span className={`text-xs px-2 py-1 rounded-full ${statusColors[status as keyof typeof statusColors] || statusColors.inactive}`}>
        {status.charAt(0).toUpperCase() + status.slice(1)}
      </span>
    );
  };

  const filteredUsers = users.filter(user => {
    if (filters.search && !user.email.toLowerCase().includes(filters.search.toLowerCase()) &&
        !user.name?.toLowerCase().includes(filters.search.toLowerCase())) {
      return false;
    }
    if (filters.accountId && user.account?.id !== filters.accountId) return false;
    if (filters.role && !user.roles?.includes(filters.role)) return false;
    if (filters.status && user.status !== filters.status) return false;
    return true;
  });

  if (!isAdmin) {
    return (
      <div className="bg-theme-error bg-opacity-10 border border-theme-error border-opacity-30 rounded-lg p-6">
        <div className="flex items-center space-x-3">
          <span className="text-theme-error text-2xl">🚫</span>
          <div>
            <h3 className="text-lg font-semibold text-theme-error">Access Denied</h3>
            <p className="text-theme-error opacity-80">
              You do not have permission to access system user management.
            </p>
          </div>
        </div>
      </div>
    );
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-theme-secondary">Loading system users...</div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="bg-theme-surface rounded-lg p-6">
        <div className="flex justify-end mb-6">
          <button 
            onClick={() => setShowCreateUserModal(true)}
            className="btn-theme btn-theme-primary"
          >
            Create User
          </button>
        </div>

        {/* System Statistics */}
        <div className="grid grid-cols-1 md:grid-cols-5 gap-4 mb-6">
          <div className="bg-theme-background rounded-lg p-4">
            <h3 className="text-sm font-medium text-theme-tertiary mb-1">Total Users</h3>
            <p className="text-2xl font-bold text-theme-primary">{users.length}</p>
          </div>
          <div className="bg-theme-background rounded-lg p-4">
            <h3 className="text-sm font-medium text-theme-tertiary mb-1">Active</h3>
            <p className="text-2xl font-bold text-theme-success">
              {users.filter(u => u.status === 'active').length}
            </p>
          </div>
          <div className="bg-theme-background rounded-lg p-4">
            <h3 className="text-sm font-medium text-theme-tertiary mb-1">Suspended</h3>
            <p className="text-2xl font-bold text-theme-error">
              {users.filter(u => u.status === 'suspended').length}
            </p>
          </div>
          <div className="bg-theme-background rounded-lg p-4">
            <h3 className="text-sm font-medium text-theme-tertiary mb-1">Total Accounts</h3>
            <p className="text-2xl font-bold text-theme-interactive-primary">{accounts.length}</p>
          </div>
          <div className="bg-theme-background rounded-lg p-4">
            <h3 className="text-sm font-medium text-theme-tertiary mb-1">System Admins</h3>
            <p className="text-2xl font-bold text-theme-interactive-secondary">
              {users.filter(u => u.roles?.some(role => role.includes('admin') || role.includes('manager'))).length}
            </p>
          </div>
        </div>

        {/* Filters */}
        <div className="bg-theme-background rounded-lg p-4 mb-6">
          <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">Search</label>
              <input
                type="text"
                placeholder="Search by name or email..."
                value={filters.search}
                onChange={(e) => setFilters({ ...filters, search: e.target.value })}
                className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">Account</label>
              <select
                value={filters.accountId}
                onChange={(e) => setFilters({ ...filters, accountId: e.target.value })}
                className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary"
              >
                <option value="">All Accounts</option>
                {accounts.map(account => (
                  <option key={account.id} value={account.id}>{account.name}</option>
                ))}
              </select>
            </div>
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">Role</label>
              <select
                value={filters.role}
                onChange={(e) => setFilters({ ...filters, role: e.target.value })}
                className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary"
              >
                <option value="">All Roles</option>
                <option value="system.admin">System Admin</option>
                <option value="account.manager">Account Manager</option>
                <option value="account.member">Account Member</option>
                <option value="billing.manager">Billing Manager</option>
              </select>
            </div>
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">Status</label>
              <select
                value={filters.status}
                onChange={(e) => setFilters({ ...filters, status: e.target.value })}
                className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary"
              >
                <option value="">All Statuses</option>
                <option value="active">Active</option>
                <option value="invited">Invited</option>
                <option value="suspended">Suspended</option>
                <option value="inactive">Inactive</option>
              </select>
            </div>
          </div>
        </div>

        {/* Users Table */}
        <div className="bg-theme-background rounded-lg overflow-hidden">
          <table className="w-full">
            <thead className="bg-theme-surface border-b border-theme">
              <tr>
                <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">User</th>
                <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Account</th>
                <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Role</th>
                <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Status</th>
                <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Created</th>
                <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Last Login</th>
                <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-theme">
              {filteredUsers.map((user) => (
                <tr key={user.id} className="hover:bg-theme-surface-hover">
                  <td className="py-3 px-4">
                    <div className="flex items-center space-x-3">
                      <div className="h-8 w-8 rounded-full bg-gradient-to-br from-theme-interactive-primary to-theme-interactive-secondary flex items-center justify-center">
                        <span className="text-white text-xs font-bold">
                          {getUserInitials(user)}
                        </span>
                      </div>
                      <div>
                        <p className="font-medium text-theme-primary">
                          {user.name}
                        </p>
                        <p className="text-sm text-theme-secondary">{user.email}</p>
                      </div>
                    </div>
                  </td>
                  <td className="py-3 px-4">
                    <p className="text-sm text-theme-primary">{user.account?.name || 'N/A'}</p>
                  </td>
                  <td className="py-3 px-4">
                    {getRoleBadge(user)}
                  </td>
                  <td className="py-3 px-4">
                    {getStatusBadge(user.status)}
                  </td>
                  <td className="py-3 px-4 text-sm text-theme-secondary">
                    {new Date(user.created_at).toLocaleDateString()}
                  </td>
                  <td className="py-3 px-4 text-sm text-theme-secondary">
                    {user.last_login_at ? new Date(user.last_login_at).toLocaleDateString() : 'Never'}
                  </td>
                  <td className="py-3 px-4">
                    <div className="flex items-center space-x-2">
                      <button
                        onClick={() => {
                          setSelectedUser(user);
                          setShowDetailsModal(true);
                        }}className="text-theme-link hover:text-theme-link-hover text-sm"
                      >
                        View
                      </button>
                      {user.status === 'active' ? (
                        <button
                          onClick={() => handleSuspendUser(user.id)}
                          className="text-theme-warning hover:text-theme-warning-hover text-sm"
                        >
                          Suspend
                        </button>
                      ) : (
                        <button
                          onClick={() => handleActivateUser(user.id)}
                          className="text-theme-success hover:text-theme-success-hover text-sm"
                        >
                          Activate
                        </button>
                      )}
                      <button
                        onClick={() => handleImpersonateUser(user.id)}
                        className="text-theme-info hover:text-theme-info-hover text-sm"
                        title="Impersonate User"
                      >
                        Impersonate
                      </button>
                      <button
                        onClick={() => handleDeleteUser(user.id)}
                        className="text-theme-error hover:text-theme-error-hover text-sm"
                      >
                        Delete
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>

          {filteredUsers.length === 0 && (
            <div className="p-8 text-center">
              <p className="text-theme-secondary">No users found</p>
              <p className="text-sm text-theme-tertiary mt-1">
                Try adjusting your filters or search criteria
              </p>
            </div>
          )}
        </div>
      </div>

      {/* User Details Modal */}
      {showDetailsModal && selectedUser && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
          <div className="bg-theme-surface rounded-lg p-6 w-full max-w-2xl max-h-[90vh] overflow-y-auto">
            <div className="flex justify-between items-center mb-6">
              <h3 className="text-lg font-semibold text-theme-primary">User Details</h3>
              <button
                onClick={() => {
                  setShowDetailsModal(false);
                  setSelectedUser(null);
                }}className="text-theme-secondary hover:text-theme-primary"
              >
                <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>

            <div className="space-y-6">
              <div>
                <h4 className="text-sm font-medium text-theme-tertiary mb-3">Personal Information</h4>
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <label className="block text-sm text-theme-secondary">Name</label>
                    <p className="text-theme-primary">{selectedUser.name}</p>
                  </div>
                  <div>
                    <label className="block text-sm text-theme-secondary">Email</label>
                    <p className="text-theme-primary">{selectedUser.email}</p>
                  </div>
                  <div>
                    <label className="block text-sm text-theme-secondary">Phone</label>
                    <p className="text-theme-primary">{selectedUser.phone || 'N/A'}</p>
                  </div>
                  <div>
                    <label className="block text-sm text-theme-secondary">User ID</label>
                    <div className="flex items-center space-x-2">
                      <p className="text-theme-primary font-mono text-xs break-all">{selectedUser.id}</p>
                      <button
                        onClick={() => navigator.clipboard.writeText(selectedUser.id)}
                        className="text-theme-link hover:text-theme-link-hover text-xs"
                        title="Copy User ID"
                      >
                        Copy
                      </button>
                    </div>
                  </div>
                </div>
              </div>

              <div>
                <h4 className="text-sm font-medium text-theme-tertiary mb-3">Account Information</h4>
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <label className="block text-sm text-theme-secondary">Account</label>
                    <p className="text-theme-primary">{selectedUser.account?.name || 'N/A'}</p>
                  </div>
                  <div>
                    <label className="block text-sm text-theme-secondary">Roles</label>
                    <div className="mt-1">
                      {getRoleBadge(selectedUser)}
                    </div>
                  </div>
                  <div>
                    <label className="block text-sm text-theme-secondary">Status</label>
                    <div className="mt-1">{getStatusBadge(selectedUser.status)}</div>
                  </div>
                  <div>
                    <label className="block text-sm text-theme-secondary">Email Verified</label>
                    <p className="text-theme-primary">{selectedUser.email_verified ? 'Yes' : 'No'}</p>
                  </div>
                </div>
              </div>

              <div>
                <h4 className="text-sm font-medium text-theme-tertiary mb-3">Activity</h4>
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <label className="block text-sm text-theme-secondary">Created</label>
                    <p className="text-theme-primary">{new Date(selectedUser.created_at).toLocaleString()}</p>
                  </div>
                  <div>
                    <label className="block text-sm text-theme-secondary">Last Login</label>
                    <p className="text-theme-primary">
                      {selectedUser.last_login_at ? new Date(selectedUser.last_login_at).toLocaleString() : 'Never'}
                    </p>
                  </div>
                  <div>
                    <label className="block text-sm text-theme-secondary">Failed Login Attempts</label>
                    <p className="text-theme-primary">{selectedUser.failed_login_attempts || 0}</p>
                  </div>
                  <div>
                    <label className="block text-sm text-theme-secondary">Account Locked</label>
                    <p className="text-theme-primary">{selectedUser.locked ? 'Yes' : 'No'}</p>
                  </div>
                </div>
              </div>
            </div>

            <div className="flex justify-end space-x-3 mt-6 pt-6 border-t border-theme">
              <button
                onClick={() => {
                  setShowDetailsModal(false);
                  setSelectedUser(null);
                }}className="btn-theme btn-theme-secondary"
              >
                Close
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Impersonate User Modal */}
      <ImpersonateUserModal
        isOpen={showImpersonateModal}
        onClose={() => {
          setShowImpersonateModal(false);
          setImpersonateUserId(null);
        }}
        preselectedUserId={impersonateUserId || undefined}
      />

      {/* Create User Modal */}
      <CreateUserModal
        isOpen={showCreateUserModal}
        onClose={() => setShowCreateUserModal(false)}
        onSuccess={() => {
          loadSystemData(); // Reload users list after successful creation
        }}
        accounts={accounts}
      />
      {ConfirmationDialog}
    </div>
  );
};

