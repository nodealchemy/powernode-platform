import React, { useState, useEffect, useCallback } from 'react';
import { usersApi, User, UserFormData, UserStats } from '../../services/usersApi';
import { Button } from '../../components/ui/Button';
import { FormField } from '../../components/ui/FormField';
import { Modal } from '../../components/ui/Modal';
import { Badge } from '../../components/ui/Badge';
import { LoadingSpinner } from '../../components/ui/LoadingSpinner';

interface UsersPageProps {}

const UsersPage: React.FC<UsersPageProps> = () => {
  const [users, setUsers] = useState<User[]>([]);
  const [userStats, setUserStats] = useState<UserStats | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [selectedUser, setSelectedUser] = useState<User | null>(null);
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [showEditModal, setShowEditModal] = useState(false);
  const [showDeleteModal, setShowDeleteModal] = useState(false);
  const [actionLoading, setActionLoading] = useState(false);

  // Form state
  const [formData, setFormData] = useState<UserFormData>({
    first_name: '',
    last_name: '',
    email: '',
    phone: '',
    role: 'member',
    password: '',
    password_confirmation: ''
  });
  const [formErrors, setFormErrors] = useState<string[]>([]);

  // Load users and stats
  const loadData = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      
      const [usersResponse, statsResponse] = await Promise.all([
        usersApi.getUsers(),
        usersApi.getUserStats()
      ]);

      if (usersResponse.success) {
        setUsers(usersResponse.data);
      } else {
        throw new Error(usersResponse.message || 'Failed to load users');
      }

      if (statsResponse.success) {
        setUserStats(statsResponse.data);
      } else {
        console.warn('Failed to load user stats, using defaults');
        setUserStats(null);
      }
    } catch (err) {
      console.error('Error loading users:', err);
      setError('Failed to load users. Please check your connection and try again.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadData();
  }, [loadData]);

  // Handle form changes
  const handleFormChange = (field: keyof UserFormData, value: string | string[]) => {
    setFormData(prev => ({ ...prev, [field]: value }));
    // Clear form errors when user starts typing
    if (formErrors.length > 0) {
      setFormErrors([]);
    }
  };

  // Reset form
  const resetForm = () => {
    setFormData({
      first_name: '',
      last_name: '',
      email: '',
      phone: '',
      role: 'member',
      password: '',
      password_confirmation: ''
    });
    setFormErrors([]);
    setSelectedUser(null);
  };

  // Handle create user
  const handleCreateUser = async () => {
    const errors = usersApi.validateUserData(formData);
    if (errors.length > 0) {
      setFormErrors(errors);
      return;
    }

    try {
      setActionLoading(true);
      const response = await usersApi.createUser(formData);
      
      if (response.success) {
        await loadData();
        setShowCreateModal(false);
        resetForm();
      } else {
        setFormErrors([response.message || 'Failed to create user']);
      }
    } catch (err) {
      console.error('Error creating user:', err);
      setFormErrors(['Failed to create user. Please try again.']);
    } finally {
      setActionLoading(false);
    }
  };

  // Handle edit user
  const handleEditUser = async () => {
    if (!selectedUser) return;

    const updateData = {
      first_name: formData.first_name,
      last_name: formData.last_name,
      email: formData.email,
      phone: formData.phone,
      role: formData.role
    };

    try {
      setActionLoading(true);
      const response = await usersApi.updateUser(selectedUser.id, updateData);
      
      if (response.success) {
        await loadData();
        setShowEditModal(false);
        resetForm();
      } else {
        setFormErrors([response.message || 'Failed to update user']);
      }
    } catch (err) {
      console.error('Error updating user:', err);
      setFormErrors(['Failed to update user. Please try again.']);
    } finally {
      setActionLoading(false);
    }
  };

  // Handle delete user
  const handleDeleteUser = async () => {
    if (!selectedUser) return;

    try {
      setActionLoading(true);
      const response = await usersApi.deleteUser(selectedUser.id);
      
      if (response.success) {
        await loadData();
        setShowDeleteModal(false);
        resetForm();
      } else {
        setError(response.message || 'Failed to delete user');
      }
    } catch (err) {
      console.error('Error deleting user:', err);
      setError('Failed to delete user. Please try again.');
    } finally {
      setActionLoading(false);
    }
  };

  // Handle user action (suspend/activate/unlock)
  const handleUserAction = async (user: User, action: 'suspend' | 'activate' | 'unlock' | 'reset_password' | 'resend_verification') => {
    try {
      setActionLoading(true);
      let response;

      switch (action) {
        case 'suspend':
          response = await usersApi.suspendUser(user.id, 'Suspended by administrator');
          break;
        case 'activate':
          response = await usersApi.activateUser(user.id);
          break;
        case 'unlock':
          response = await usersApi.unlockUser(user.id);
          break;
        case 'reset_password':
          response = await usersApi.resetUserPassword(user.id);
          break;
        case 'resend_verification':
          response = await usersApi.resendVerification(user.id);
          break;
      }

      if (response.success) {
        await loadData();
      } else {
        setError(response.message || `Failed to ${action} user`);
      }
    } catch (err) {
      console.error(`Error ${action} user:`, err);
      setError(`Failed to ${action} user. Please try again.`);
    } finally {
      setActionLoading(false);
    }
  };

  // Open edit modal
  const openEditModal = (user: User) => {
    setSelectedUser(user);
    setFormData({
      first_name: user.first_name,
      last_name: user.last_name,
      email: user.email,
      phone: user.phone || '',
      role: user.role || 'member',
      password: '',
      password_confirmation: ''
    });
    setShowEditModal(true);
  };

  // Open delete modal
  const openDeleteModal = (user: User) => {
    setSelectedUser(user);
    setShowDeleteModal(true);
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-64">
        <LoadingSpinner size="lg" />
      </div>
    );
  }

  return (
    <div className="px-4 sm:px-6 lg:px-8 py-8 bg-theme-background min-h-screen">
      {/* Page Header */}
      <div className="mb-8">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-bold text-theme-primary">Users</h1>
            <p className="text-theme-secondary mt-1">Manage users within your account</p>
          </div>
          <Button 
            onClick={() => setShowCreateModal(true)}
            className="bg-theme-interactive-primary text-white hover:bg-theme-interactive-hover"
          >
            Add New User
          </Button>
        </div>

        {/* Stats Cards */}
        {userStats && (
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-4 mt-6">
            <div className="bg-theme-surface rounded-lg p-4 shadow-sm">
              <div className="text-2xl font-semibold text-theme-primary">{userStats.total_users}</div>
              <div className="text-theme-secondary text-sm">Total Users</div>
            </div>
            <div className="bg-theme-surface rounded-lg p-4 shadow-sm">
              <div className="text-2xl font-semibold text-green-600">{userStats.active_users}</div>
              <div className="text-theme-secondary text-sm">Active Users</div>
            </div>
            <div className="bg-theme-surface rounded-lg p-4 shadow-sm">
              <div className="text-2xl font-semibold text-red-600">{userStats.suspended_users}</div>
              <div className="text-theme-secondary text-sm">Suspended Users</div>
            </div>
            <div className="bg-theme-surface rounded-lg p-4 shadow-sm">
              <div className="text-2xl font-semibold text-yellow-600">{userStats.unverified_users}</div>
              <div className="text-theme-secondary text-sm">Unverified Users</div>
            </div>
            <div className="bg-theme-surface rounded-lg p-4 shadow-sm">
              <div className="text-2xl font-semibold text-blue-600">{userStats.recent_logins}</div>
              <div className="text-theme-secondary text-sm">Recent Logins</div>
            </div>
          </div>
        )}
      </div>

      {/* Error Display */}
      {error && (
        <div className="bg-orange-50 border border-orange-200 text-orange-700 px-4 py-3 rounded mb-4">
          <div className="flex">
            <div className="flex-shrink-0">
              <span className="text-orange-400">⚠️</span>
            </div>
            <div className="ml-3">
              <p className="text-sm">
                {error}
              </p>
            </div>
          </div>
        </div>
      )}

      {/* Users Table */}
      <div className="bg-theme-surface rounded-lg shadow-sm overflow-hidden">
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-theme">
            <thead className="bg-theme-background">
              <tr>
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
                    <div className="flex items-center">
                      <div className="flex-shrink-0 h-10 w-10">
                        <div className="h-10 w-10 rounded-full bg-theme-interactive-primary flex items-center justify-center">
                          <span className="text-white text-sm font-medium">
                            {user.first_name[0]}{user.last_name[0]}
                          </span>
                        </div>
                      </div>
                      <div className="ml-4">
                        <div className="text-sm font-medium text-theme-primary">
                          {user.full_name}
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
                    <Badge className={usersApi.getRoleColor(user.role)}>
                      {user.role.replace('_', ' ')}
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
                    <div className="flex items-center justify-end space-x-2">
                      <Button
                        variant="secondary"
                        size="sm"
                        onClick={() => openEditModal(user)}
                      >
                        Edit
                      </Button>
                      
                      {/* User Actions */}
                      {user.status === 'suspended' ? (
                        <Button
                          variant="secondary"
                          size="sm"
                          onClick={() => handleUserAction(user, 'activate')}
                          disabled={actionLoading}
                        >
                          Activate
                        </Button>
                      ) : (
                        <Button
                          variant="secondary"
                          size="sm"
                          onClick={() => handleUserAction(user, 'suspend')}
                          disabled={actionLoading}
                        >
                          Suspend
                        </Button>
                      )}

                      {user.locked && (
                        <Button
                          variant="secondary"
                          size="sm"
                          onClick={() => handleUserAction(user, 'unlock')}
                          disabled={actionLoading}
                        >
                          Unlock
                        </Button>
                      )}

                      {!user.email_verified && (
                        <Button
                          variant="secondary"
                          size="sm"
                          onClick={() => handleUserAction(user, 'resend_verification')}
                          disabled={actionLoading}
                        >
                          Resend
                        </Button>
                      )}

                      <Button
                        variant="secondary"
                        size="sm"
                        onClick={() => handleUserAction(user, 'reset_password')}
                        disabled={actionLoading}
                      >
                        Reset Password
                      </Button>

                      <Button
                        variant="danger"
                        size="sm"
                        onClick={() => openDeleteModal(user)}
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

      {/* Create User Modal */}
      <Modal
        isOpen={showCreateModal}
        onClose={() => {
          setShowCreateModal(false);
          resetForm();
        }}
        title="Create New User"
        maxWidth="md"
      >
        <div className="space-y-4">
          {formErrors.length > 0 && (
            <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded">
              <ul className="list-disc list-inside">
                {formErrors.map((error, index) => (
                  <li key={index}>{error}</li>
                ))}
              </ul>
            </div>
          )}

          <div className="grid grid-cols-2 gap-4">
            <FormField
              label="First Name"
              type="text"
              value={formData.first_name}
              onChange={(value) => handleFormChange('first_name', value)}
              required
            />
            <FormField
              label="Last Name"
              type="text"
              value={formData.last_name}
              onChange={(value) => handleFormChange('last_name', value)}
              required
            />
          </div>

          <FormField
            label="Email"
            type="email"
            value={formData.email}
            onChange={(value) => handleFormChange('email', value)}
            required
          />

          <FormField
            label="Phone (Optional)"
            type="tel"
            value={formData.phone}
            onChange={(value: string) => handleFormChange('phone', value)}
          />

          <FormField
            label="Role"
            type="select"
            value={formData.role || 'member'}
            onChange={(value: string) => handleFormChange('role', value)}
            options={usersApi.getAvailableRoles().map(role => ({
              value: role.value,
              label: role.label
            }))}
            required
          />

          <FormField
            label="Password"
            type="password"
            value={formData.password}
            onChange={(value) => handleFormChange('password', value)}
            required
          />

          <FormField
            label="Confirm Password"
            type="password"
            value={formData.password_confirmation}
            onChange={(value) => handleFormChange('password_confirmation', value)}
            required
          />

          <div className="flex justify-end space-x-3 mt-6">
            <Button
              variant="secondary"
              onClick={() => {
                setShowCreateModal(false);
                resetForm();
              }}
            >
              Cancel
            </Button>
            <Button
              onClick={handleCreateUser}
              disabled={actionLoading}
            >
              {actionLoading ? 'Creating...' : 'Create User'}
            </Button>
          </div>
        </div>
      </Modal>

      {/* Edit User Modal */}
      <Modal
        isOpen={showEditModal}
        onClose={() => {
          setShowEditModal(false);
          resetForm();
        }}
        title="Edit User"
        maxWidth="md"
      >
        <div className="space-y-4">
          {formErrors.length > 0 && (
            <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded">
              <ul className="list-disc list-inside">
                {formErrors.map((error, index) => (
                  <li key={index}>{error}</li>
                ))}
              </ul>
            </div>
          )}

          <div className="grid grid-cols-2 gap-4">
            <FormField
              label="First Name"
              type="text"
              value={formData.first_name}
              onChange={(value) => handleFormChange('first_name', value)}
              required
            />
            <FormField
              label="Last Name"
              type="text"
              value={formData.last_name}
              onChange={(value) => handleFormChange('last_name', value)}
              required
            />
          </div>

          <FormField
            label="Email"
            type="email"
            value={formData.email}
            onChange={(value) => handleFormChange('email', value)}
            required
          />

          <FormField
            label="Phone (Optional)"
            type="tel"
            value={formData.phone}
            onChange={(value: string) => handleFormChange('phone', value)}
          />

          <FormField
            label="Role"
            type="select"
            value={formData.role || 'member'}
            onChange={(value: string) => handleFormChange('role', value)}
            options={usersApi.getAvailableRoles().map(role => ({
              value: role.value,
              label: role.label
            }))}
            required
          />

          <div className="flex justify-end space-x-3 mt-6">
            <Button
              variant="secondary"
              onClick={() => {
                setShowEditModal(false);
                resetForm();
              }}
            >
              Cancel
            </Button>
            <Button
              onClick={handleEditUser}
              disabled={actionLoading}
            >
              {actionLoading ? 'Updating...' : 'Update User'}
            </Button>
          </div>
        </div>
      </Modal>

      {/* Delete Confirmation Modal */}
      <Modal
        isOpen={showDeleteModal}
        onClose={() => {
          setShowDeleteModal(false);
          resetForm();
        }}
        title="Delete User"
        maxWidth="sm"
      >
        <div className="text-theme-primary">
          Are you sure you want to delete <strong>{selectedUser?.full_name}</strong>? 
          This action cannot be undone.
        </div>
        <div className="flex justify-end space-x-3 mt-6">
          <Button
            variant="secondary"
            onClick={() => {
              setShowDeleteModal(false);
              resetForm();
            }}
          >
            Cancel
          </Button>
          <Button
            variant="danger"
            onClick={handleDeleteUser}
            disabled={actionLoading}
          >
            {actionLoading ? 'Deleting...' : 'Delete User'}
          </Button>
        </div>
      </Modal>
    </div>
  );
};

export default UsersPage;