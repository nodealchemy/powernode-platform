import React, { useState, useEffect } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '../../store';
import { usersApi, User, AdminAccount } from '../../services/usersApi';
import { hasAdminAccess } from '../../utils/permissionUtils';
import ImpersonateUserModal from './ImpersonateUserModal';
import CreateUserModal from './CreateUserModal';

export const SystemUserManagement: React.FC = () => {
  const { user: currentUser } = useSelector((state: RootState) => state.auth);
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
      console.error('Unauthorized access to system user management');
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
      console.error('Failed to load system data:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleSuspendUser = async (userId: string) => {
    if (!window.confirm('Are you sure you want to suspend this user?')) return;

    try {
      await usersApi.suspendUser(userId);
      loadSystemData();
    } catch (error) {
      console.error('Failed to suspend user:', error);
    }
  };

  const handleActivateUser = async (userId: string) => {
    try {
      await usersApi.activateUser(userId);
      loadSystemData();
    } catch (error) {
      console.error('Failed to activate user:', error);
    }
  };

  const handleDeleteUser = async (userId: string) => {
    if (!window.confirm('Are you sure you want to permanently delete this user? This action cannot be undone.')) return;

    try {
      await usersApi.deleteUser(userId);
      loadSystemData();
    } catch (error) {
      console.error('Failed to delete user:', error);
    }
  };

  const handleImpersonateUser = (userId: string) => {
    setImpersonateUserId(userId);
    setShowImpersonateModal(true);
  };

  const getRoleBadge = (role: string) => {
    const roleColors = {
      admin: 'bg-theme-error bg-opacity-10 text-theme-error',
      owner: 'bg-theme-success bg-opacity-10 text-theme-success',
      member: 'bg-theme-info bg-opacity-10 text-theme-info',
    };

    return (
      <span className={`text-xs px-2 py-1 rounded-full ${roleColors[role as keyof typeof roleColors] || roleColors.member}`}>
        {role.charAt(0).toUpperCase() + role.slice(1)}
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
        !`${user.first_name} ${user.last_name}`.toLowerCase().includes(filters.search.toLowerCase())) {
      return false;
    }
    if (filters.accountId && user.account?.id !== filters.accountId) return false;
    if (filters.role && user.role !== filters.role) return false;
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
        <div className="flex justify-between items-center mb-6">
          <div>
            <h2 className="text-xl font-semibold text-theme-primary">System User Management</h2>
            <p className="text-theme-secondary mt-1">Manage all users across the entire system</p>
          </div>
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
              {users.filter(u => u.role === 'admin' || u.role === 'owner').length}
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
                <option value="owner">Owner</option>
                <option value="admin">Admin</option>
                <option value="manager">Manager</option>
                <option value="member">Member</option>
                <option value="viewer">Viewer</option>
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
                          {user.first_name?.[0]}{user.last_name?.[0]}
                        </span>
                      </div>
                      <div>
                        <p className="font-medium text-theme-primary">
                          {user.first_name} {user.last_name}
                        </p>
                        <p className="text-sm text-theme-secondary">{user.email}</p>
                      </div>
                    </div>
                  </td>
                  <td className="py-3 px-4">
                    <p className="text-sm text-theme-primary">{user.account?.name || 'N/A'}</p>
                  </td>
                  <td className="py-3 px-4">
                    {getRoleBadge(user.role)}
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
                        }}
                        className="text-theme-link hover:text-theme-link-hover text-sm"
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
                }}
                className="text-theme-secondary hover:text-theme-primary"
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
                    <p className="text-theme-primary">{selectedUser.first_name} {selectedUser.last_name}</p>
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
                    <label className="block text-sm text-theme-secondary">Role</label>
                    <div className="mt-1">
                      {getRoleBadge(selectedUser.role)}
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
                }}
                className="btn-theme btn-theme-secondary"
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
    </div>
  );
};

export default SystemUserManagement;