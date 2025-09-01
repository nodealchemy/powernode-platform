import React, { useState, useEffect, useCallback } from 'react';
import { useSelector, useDispatch } from 'react-redux';
import { RootState, AppDispatch } from '@/shared/services';
import { startImpersonation } from '@/shared/services/slices/authSlice';
import { usersApi, User, UserFormData, UserStats } from '@/features/users/services/usersApi';
import { Button } from '@/shared/components/ui/Button';
import { FormField } from '@/shared/components/ui/FormField';
import { Modal } from '@/shared/components/ui/Modal';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { UserRolesModal } from '@/features/users/components/UserRolesModal';
import { UserPlus, RefreshCw, Search, Filter, Download, UserCheck, Shield, Settings } from 'lucide-react';

interface UsersPageProps {}

const UsersPage: React.FC<UsersPageProps> = () => {
  const dispatch = useDispatch<AppDispatch>();
  const { user: currentUser } = useSelector((state: RootState) => state.auth);
  const [users, setUsers] = useState<User[]>([]);
  const [filteredUsers, setFilteredUsers] = useState<User[]>([]);
  const [userStats, setUserStats] = useState<UserStats | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [selectedUser, setSelectedUser] = useState<User | null>(null);
  const [selectedUsers, setSelectedUsers] = useState<Set<string>>(new Set());
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [showEditModal, setShowEditModal] = useState(false);
  const [showDeleteModal, setShowDeleteModal] = useState(false);
  const [showRolesModal, setShowRolesModal] = useState(false);
  const [selectedUserForRoles, setSelectedUserForRoles] = useState<User | null>(null);
  const [actionLoading, setActionLoading] = useState(false);

  // Filtering and search state
  const [searchTerm, setSearchTerm] = useState('');
  const [statusFilter, setStatusFilter] = useState<'all' | 'active' | 'suspended' | 'inactive'>('all');
  const [roleFilter, setRoleFilter] = useState<string>('all');
  const [sortBy, setSortBy] = useState<'name' | 'email' | 'created_at' | 'last_login_at'>('name');
  const [sortOrder, setSortOrder] = useState<'asc' | 'desc'>('asc');
  const [showFilters, setShowFilters] = useState(false);

  // Form state
  const [formData, setFormData] = useState<UserFormData>({
    first_name: '',
    last_name: '',
    email: '',
    phone: '',
    roles: ['account.member'],
    password: '',
    password_confirmation: ''
  });
  const [formErrors, setFormErrors] = useState<string[]>([]);
  const [availableRoles, setAvailableRoles] = useState<Array<{ value: string; label: string; description: string }>>([]);
  const [rolesLoading, setRolesLoading] = useState(true);

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
        setUserStats(null);
      }
    } catch (err) {
      setError('Failed to load users. Please check your connection and try again.');
    } finally {
      setLoading(false);
    }
  }, []);

  // Load available roles
  const loadAvailableRoles = useCallback(async () => {
    try {
      setRolesLoading(true);
      const roles = await usersApi.getAvailableRoles();
      setAvailableRoles(roles);
    } catch (error) {
      setAvailableRoles([]);
    } finally {
      setRolesLoading(false);
    }
  }, []);

  useEffect(() => {
    loadData();
    loadAvailableRoles();
  }, [loadData, loadAvailableRoles]);

  // Filter and sort users
  useEffect(() => {
    let filtered = [...users];

    // Apply search filter
    if (searchTerm) {
      filtered = filtered.filter(user => 
        user.full_name.toLowerCase().includes(searchTerm.toLowerCase()) ||
        user.email.toLowerCase().includes(searchTerm.toLowerCase()) ||
        user.phone?.toLowerCase().includes(searchTerm.toLowerCase())
      );
    }

    // Apply status filter
    if (statusFilter !== 'all') {
      filtered = filtered.filter(user => user.status === statusFilter);
    }

    // Apply role filter
    if (roleFilter !== 'all') {
      filtered = filtered.filter(user => user.roles?.includes(roleFilter));
    }

    // Apply sorting
    filtered.sort((a, b) => {
      let aVal: any, bVal: any;

      switch (sortBy) {
        case 'name':
          aVal = a.full_name.toLowerCase();
          bVal = b.full_name.toLowerCase();
          break;
        case 'email':
          aVal = a.email.toLowerCase();
          bVal = b.email.toLowerCase();
          break;
        case 'created_at':
          aVal = new Date(a.created_at);
          bVal = new Date(b.created_at);
          break;
        case 'last_login_at':
          aVal = a.last_login_at ? new Date(a.last_login_at) : new Date(0);
          bVal = b.last_login_at ? new Date(b.last_login_at) : new Date(0);
          break;
        default:
          return 0;
      }

      if (aVal < bVal) return sortOrder === 'asc' ? -1 : 1;
      if (aVal > bVal) return sortOrder === 'asc' ? 1 : -1;
      return 0;
    });

    setFilteredUsers(filtered);
  }, [users, searchTerm, statusFilter, roleFilter, sortBy, sortOrder]);

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
      roles: ['account.member'],
      password: '',
      password_confirmation: ''
    });
    setFormErrors([]);
    setSelectedUser(null);
  };

  // Handle bulk selection
  const toggleUserSelection = (userId: string) => {
    const newSelected = new Set(selectedUsers);
    if (newSelected.has(userId)) {
      newSelected.delete(userId);
    } else {
      newSelected.add(userId);
    }
    setSelectedUsers(newSelected);
  };

  const toggleSelectAll = () => {
    if (selectedUsers.size === filteredUsers.length) {
      setSelectedUsers(new Set());
    } else {
      setSelectedUsers(new Set(filteredUsers.map(u => u.id)));
    }
  };

  // Handle bulk actions
  const handleBulkAction = async (action: 'suspend' | 'activate' | 'delete' | 'export') => {
    if (selectedUsers.size === 0) return;

    try {
      setActionLoading(true);
      const userIds = Array.from(selectedUsers);

      switch (action) {
        case 'suspend':
          await Promise.all(userIds.map(id => usersApi.suspendUser(id, 'Bulk suspended by administrator')));
          break;
        case 'activate':
          await Promise.all(userIds.map(id => usersApi.activateUser(id)));
          break;
        case 'delete':
          if (window.confirm(`Are you sure you want to delete ${selectedUsers.size} users? This action cannot be undone.`)) {
            await Promise.all(userIds.map(id => usersApi.deleteUser(id)));
          } else {
            return;
          }
          break;
        case 'export':
          const selectedUserData = filteredUsers.filter(u => selectedUsers.has(u.id));
          exportUsers(selectedUserData);
          return;
      }

      await loadData();
      setSelectedUsers(new Set());
    } catch (err) {
      setError(`Failed to ${action} selected users. Please try again.`);
    } finally {
      setActionLoading(false);
    }
  };

  // Export users to CSV
  const exportUsers = (usersToExport: User[] = filteredUsers) => {
    const headers = ['Name', 'Email', 'Phone', 'Roles', 'Status', 'Verified', 'Last Login', 'Created Date'];
    const rows = usersToExport.map(user => [
      user.full_name,
      user.email,
      user.phone || '',
      user.roles?.[0] || 'account.member',
      user.status,
      user.email_verified ? 'Yes' : 'No',
      user.last_login_at ? new Date(user.last_login_at).toLocaleDateString() : 'Never',
      new Date(user.created_at).toLocaleDateString()
    ]);

    const csvContent = [headers, ...rows]
      .map(row => row.map(field => `"${field}"`).join(','))
      .join('\n');

    const blob = new Blob([csvContent], { type: 'text/csv' });
    const url = window.URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `users_export_${new Date().toISOString().split('T')[0]}.csv`;
    link.click();
    window.URL.revokeObjectURL(url);
  };

  // Handle user impersonation
  const handleImpersonateUser = async (user: User) => {
    if (user.id === currentUser?.id) {
      setError('Cannot impersonate yourself');
      return;
    }

    try {
      setActionLoading(true);
      const response = await dispatch(startImpersonation({ 
        user_id: user.id, 
        reason: 'Admin impersonation' 
      })).unwrap();
      
      // The Redux action automatically handles token storage
      window.location.href = '/app';
    } catch (err: any) {
      setError(err || 'Failed to impersonate user. Please try again.');
    } finally {
      setActionLoading(false);
    }
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
      phone: formData.phone
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
      setError(`Failed to ${action} user. Please try again.`);
    } finally {
      setActionLoading(false);
    }
  };

  // Open edit modal
  const openEditModal = (user: User) => {
    setSelectedUser(user);
    setFormData({
      first_name: user.first_name || '',
      last_name: user.last_name || '',
      email: user.email,
      phone: user.phone || '',
      roles: ['account.member'], // Default role for consistency
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

  // Open roles modal
  const openRolesModal = (user: User) => {
    setSelectedUserForRoles(user);
    setShowRolesModal(true);
  };

  // Handle role modal close and refresh
  const handleRoleModalClose = () => {
    setShowRolesModal(false);
    setSelectedUserForRoles(null);
  };

  const handleUserRolesUpdated = async () => {
    await loadData();
  };

  const pageActions: PageAction[] = [
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: loadData,
      variant: 'secondary',
      icon: RefreshCw,
      disabled: loading
    },
    {
      id: 'export',
      label: 'Export All',
      onClick: () => exportUsers(),
      variant: 'secondary',
      icon: Download,
      disabled: loading || filteredUsers.length === 0
    },
    {
      id: 'filters',
      label: showFilters ? 'Hide Filters' : 'Show Filters',
      onClick: () => setShowFilters(!showFilters),
      variant: 'secondary',
      icon: Filter
    },
    {
      id: 'clear-filters',
      label: 'Clear Filters',
      onClick: () => {
        setSearchTerm('');
        setStatusFilter('all');
        setRoleFilter('all');
        setSortBy('name');
        setSortOrder('asc');
      },
      variant: 'secondary',
      disabled: searchTerm === '' && statusFilter === 'all' && roleFilter === 'all' && sortBy === 'name' && sortOrder === 'asc'
    },
    {
      id: 'sort-toggle',
      label: sortOrder === 'asc' ? 'Sort Desc' : 'Sort Asc',
      onClick: () => setSortOrder(sortOrder === 'asc' ? 'desc' : 'asc'),
      variant: 'secondary',
      disabled: loading
    },
    {
      id: 'add-user',
      label: 'Add New User',
      onClick: () => setShowCreateModal(true),
      variant: 'primary',
      icon: UserPlus
    }
  ];

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app', icon: '🏠' },
    { label: 'Administration', icon: '⚙️' },
    { label: 'User Management', icon: '👥' }
  ];

  const getPageDescription = () => {
    if (loading) return "Loading user management dashboard...";
    const totalUsers = filteredUsers.length;
    const selectedCount = selectedUsers.size;
    
    if (selectedCount > 0) {
      return `${selectedCount} of ${totalUsers} users selected • Full administrative user management`;
    }
    
    return `${totalUsers} users • Full administrative user management with bulk operations, filtering, and impersonation`;
  };

  return (
    <PageContainer
      title="User Management"
      description={getPageDescription()}
      breadcrumbs={breadcrumbs}
      actions={loading ? [] : pageActions}
    >
      {loading ? (
        <div className="flex items-center justify-center min-h-64">
          <LoadingSpinner size="lg" />
        </div>
      ) : (
        <>
          {/* Enhanced Filtering Interface */}
          {showFilters && (
            <div className="bg-theme-surface rounded-xl p-6 shadow-sm mb-6">
              <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center">
                <Filter className="h-5 w-5 mr-2" />
                Advanced Filters
              </h3>
              
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
                {/* Search */}
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-2">Search</label>
                  <div className="relative">
                    <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-theme-tertiary" />
                    <input
                      type="text"
                      placeholder="Search users..."
                      value={searchTerm}
                      onChange={(e) => setSearchTerm(e.target.value)}
                      className="input-theme pl-10"
                    />
                  </div>
                </div>

                {/* Status Filter */}
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-2">Status</label>
                  <select
                    value={statusFilter}
                    onChange={(e) => setStatusFilter(e.target.value as any)}
                    className="select-theme"
                  >
                    <option value="all">All Statuses</option>
                    <option value="active">Active</option>
                    <option value="suspended">Suspended</option>
                    <option value="inactive">Inactive</option>
                  </select>
                </div>

                {/* Role Filter */}
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-2">Roles</label>
                  <select
                    value={roleFilter}
                    onChange={(e) => setRoleFilter(e.target.value)}
                    className="select-theme"
                  >
                    <option value="all">All Roles</option>
                    {rolesLoading ? (
                      <option value="">Loading roles...</option>
                    ) : (
                      availableRoles.map(role => (
                        <option key={role.value} value={role.value}>{role.label}</option>
                      ))
                    )}
                  </select>
                </div>

                {/* Sort Options */}
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-2">Sort By</label>
                  <div className="flex gap-2">
                    <select
                      value={sortBy}
                      onChange={(e) => setSortBy(e.target.value as any)}
                      className="select-theme w-full"
                    >
                      <option value="name">Name</option>
                      <option value="email">Email</option>
                      <option value="created_at">Created Date</option>
                      <option value="last_login_at">Last Login</option>
                    </select>
                  </div>
                </div>
              </div>

              <div className="flex justify-center items-center mt-4">
                <span className="text-sm text-theme-secondary">
                  Showing {filteredUsers.length} of {users.length} users
                </span>
              </div>
            </div>
          )}

          {/* Stats Cards */}
          {userStats && (
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-4 mb-8">
              <div className="bg-theme-surface rounded-lg p-4 shadow-sm">
            <div className="text-2xl font-semibold text-theme-primary">{userStats.total_users}</div>
            <div className="text-theme-secondary text-sm">Total Users</div>
          </div>
          <div className="bg-theme-surface rounded-lg p-4 shadow-sm">
            <div className="text-2xl font-semibold text-theme-success">{userStats.active_users}</div>
            <div className="text-theme-secondary text-sm">Active Users</div>
          </div>
          <div className="bg-theme-surface rounded-lg p-4 shadow-sm">
            <div className="text-2xl font-semibold text-theme-error">{userStats.suspended_users}</div>
            <div className="text-theme-secondary text-sm">Suspended Users</div>
          </div>
          <div className="bg-theme-surface rounded-lg p-4 shadow-sm">
            <div className="text-2xl font-semibold text-theme-warning">{userStats.unverified_users}</div>
            <div className="text-theme-secondary text-sm">Unverified Users</div>
          </div>
          <div className="bg-theme-surface rounded-lg p-4 shadow-sm">
            <div className="text-2xl font-semibold text-theme-info">{userStats.recent_logins}</div>
            <div className="text-theme-secondary text-sm">Recent Logins</div>
          </div>
        </div>
      )}

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

          {/* Bulk Operations Bar */}
          {selectedUsers.size > 0 && (
            <div className="bg-theme-info-background border border-theme-info-border rounded-lg p-4 mb-6">
              <div className="flex items-center justify-between">
                <div className="flex items-center space-x-4">
                  <span className="text-theme-info font-medium">
                    {selectedUsers.size} user{selectedUsers.size > 1 ? 's' : ''} selected
                  </span>
                  <button
                    onClick={() => setSelectedUsers(new Set())}
                    className="text-theme-tertiary hover:text-theme-secondary text-sm"
                  >
                    Clear selection
                  </button>
                </div>
                <div className="flex items-center space-x-2">
                  <Button
                    variant="secondary"
                    size="sm"
                    onClick={() => handleBulkAction('export')}
                    disabled={actionLoading}
                  >
                    <Download className="h-4 w-4 mr-1" />
                    Export Selected
                  </Button>
                  <Button
                    variant="secondary"
                    size="sm"
                    onClick={() => handleBulkAction('activate')}
                    disabled={actionLoading}
                  >
                    <UserCheck className="h-4 w-4 mr-1" />
                    Activate
                  </Button>
                  <Button
                    variant="secondary"
                    size="sm"
                    onClick={() => handleBulkAction('suspend')}
                    disabled={actionLoading}
                  >
                    <Shield className="h-4 w-4 mr-1" />
                    Suspend
                  </Button>
                  <Button
                    variant="danger"
                    size="sm"
                    onClick={() => handleBulkAction('delete')}
                    disabled={actionLoading}
                  >
                    Delete Selected
                  </Button>
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
                  <input
                    type="checkbox"
                    checked={selectedUsers.size === filteredUsers.length && filteredUsers.length > 0}
                    onChange={toggleSelectAll}
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
              {filteredUsers.map((user) => (
                <tr key={user.id} className="hover:bg-theme-surface-hover">
                  <td className="px-6 py-4 whitespace-nowrap">
                    <input
                      type="checkbox"
                      checked={selectedUsers.has(user.id)}
                      onChange={() => toggleUserSelection(user.id)}
                      className="rounded border-theme focus:ring-theme-focus"
                    />
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <div className="flex items-center">
                      <div className="flex-shrink-0 h-10 w-10">
                        <div className="h-10 w-10 rounded-full bg-theme-interactive-primary flex items-center justify-center">
                          <span className="text-white text-sm font-medium">
                            {(user.first_name?.[0] || user.email[0]).toUpperCase()}
                            {user.last_name?.[0]?.toUpperCase() || ''}
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
                      {/* Primary Actions */}
                      <Button
                        variant="secondary"
                        size="sm"
                        onClick={() => openEditModal(user)}
                        title="Edit User"
                      >
                        Edit
                      </Button>
                      
                      <Button
                        variant="secondary"
                        size="sm"
                        onClick={() => openRolesModal(user)}
                        title="Manage Roles"
                      >
                        <Settings className="h-4 w-4" />
                      </Button>

                      {/* Impersonate Button (admin only, not for self) */}
                      {user.id !== currentUser?.id && (
                        <Button
                          variant="secondary"
                          size="sm"
                          onClick={() => handleImpersonateUser(user)}
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
                          onClick={() => handleUserAction(user, 'activate')}
                          disabled={actionLoading}
                          title="Activate User"
                        >
                          <Shield className="h-4 w-4" />
                        </Button>
                      ) : (
                        <Button
                          variant="secondary"
                          size="sm"
                          onClick={() => handleUserAction(user, 'suspend')}
                          disabled={actionLoading}
                          title="Suspend User"
                        >
                          <Shield className="h-4 w-4" />
                        </Button>
                      )}

                      {/* Additional Actions Dropdown */}
                      <div className="relative inline-block text-left">
                        <Button
                          variant="secondary"
                          size="sm"
                          title="More Actions"
                        >
                          ⋯
                        </Button>
                        {/* TODO: Implement dropdown menu for additional actions */}
                      </div>

                      <Button
                        variant="danger"
                        size="sm"
                        onClick={() => openDeleteModal(user)}
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

          {filteredUsers.length === 0 && (
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
            <div className="bg-theme-error-background border border-theme-error-border text-theme-error px-4 py-3 rounded">
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

          <div className="bg-theme-info-background border border-theme-info-border rounded-lg p-4">
            <div className="flex items-center space-x-3">
              <Settings className="h-5 w-5 text-theme-info flex-shrink-0" />
              <div>
                <h4 className="font-medium text-theme-info">Default Role Assignment</h4>
                <p className="text-sm text-theme-info mt-1">
                  New users will be assigned the default "Account Member" role. You can manage additional roles after creation using the "Manage Roles" button.
                </p>
              </div>
            </div>
          </div>

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
              }}>
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
            <div className="bg-theme-error-background border border-theme-error-border text-theme-error px-4 py-3 rounded">
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

          <div className="bg-theme-warning-background border border-theme-warning-border rounded-lg p-4">
            <div className="flex items-center space-x-3">
              <Settings className="h-5 w-5 text-theme-warning flex-shrink-0" />
              <div>
                <h4 className="font-medium text-theme-warning">Role Management</h4>
                <p className="text-sm text-theme-warning mt-1">
                  Use the "Manage Roles" button in the user table to modify role assignments for this user.
                </p>
              </div>
            </div>
          </div>

          <div className="flex justify-end space-x-3 mt-6">
            <Button
              variant="secondary"
              onClick={() => {
                setShowEditModal(false);
                resetForm();
              }}>
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
            }}>
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

      {/* User Roles Modal */}
      <UserRolesModal
        user={selectedUserForRoles}
        isOpen={showRolesModal}
        onClose={handleRoleModalClose}
        onUserUpdated={handleUserRolesUpdated}
      />
        </>
      )}
    </PageContainer>
  );
};

export { UsersPage };