import React, { useState, useEffect, useCallback } from 'react';
import { useSelector, useDispatch } from 'react-redux';
import { RootState, AppDispatch } from '@/shared/services';
import { startImpersonation } from '@/shared/services/slices/authSlice';
import { usersApi, User, UserFormData, UserStats } from '@/features/users/services/usersApi';
import { Button } from '@/shared/components/ui/Button';
import { Modal } from '@/shared/components/ui/Modal';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { UserPlus, RefreshCw, Search, Filter, Download, UserCheck, Shield, Users } from 'lucide-react';
import UserRolesModal from '@/features/users/components/UserRolesModal';

interface AdminUsersPageProps {}

const AdminUsersPage: React.FC<AdminUsersPageProps> = () => {
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
  const [actionLoading, setActionLoading] = useState(false);
  // Roles state for Create Modal (Edit roles moved to separate modal)
  const [availableRoles, setAvailableRoles] = useState<Array<{ value: string; label: string; description: string }>>([]);
  const [rolesLoading, setRolesLoading] = useState(true);

  // Filtering and search state
  const [searchTerm, setSearchTerm] = useState('');
  const [statusFilter, setStatusFilter] = useState<'all' | 'active' | 'suspended' | 'inactive'>('all');
  // roleFilter removed - role management in separate modal
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

  // Load available roles for Create Modal
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

  // Load users and stats
  const loadData = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      
      const [usersResponse, statsResponse] = await Promise.all([
        usersApi.getAllUsers(),
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

    // Role filtering removed - managed in separate modal

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
  }, [users, searchTerm, statusFilter, sortBy, sortOrder]);

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
    const headers = ['Name', 'Email', 'Phone', 'Role', 'Status', 'Verified', 'Last Login', 'Created Date'];
    const rows = usersToExport.map(user => [
      user.full_name,
      user.email,
      user.phone || '',
      usersApi.formatRoles(user.roles || []),
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
    } catch (err: any) {
      console.error('User creation error:', err);
      
      // Handle different error types
      if (err.code === 'ERR_NETWORK' || err.code === 'ERR_FAILED') {
        setFormErrors(['Network error: Unable to connect to the server. Please check your connection.']);
      } else if (err.response?.status === 401) {
        setFormErrors(['Authentication error: Your session may have expired. Please refresh the page.']);
      } else if (err.response?.status === 403) {
        setFormErrors(['Permission denied: You do not have permission to create users.']);
      } else if (err.response?.status === 422) {
        // Validation errors from backend
        const validationErrors = err.response?.data?.errors || err.response?.data?.message;
        if (typeof validationErrors === 'object') {
          setFormErrors(Object.values(validationErrors).flat());
        } else if (validationErrors) {
          setFormErrors([validationErrors]);
        } else {
          setFormErrors(['Validation error: Please check your input.']);
        }
      } else if (err.response?.data?.message) {
        setFormErrors([err.response.data.message]);
      } else if (err.message) {
        setFormErrors([`Error: ${err.message}`]);
      } else {
        setFormErrors(['An unexpected error occurred while creating the user.']);
      }
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
      setFormErrors([]);
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
      roles: ['account.member'], // Not used in edit form anymore
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

  const openRolesModal = (user: User) => {
    setSelectedUser(user);
    setShowRolesModal(true);
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
        // roleFilter removed
        setSortBy('name');
        setSortOrder('asc');
      },
      variant: 'secondary',
      disabled: searchTerm === '' && statusFilter === 'all' && sortBy === 'name' && sortOrder === 'asc'
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
    { label: 'Admin', href: '/admin', icon: '⚙️' },
    { label: 'Users', icon: '👥' }
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

                {/* Role Filter removed - managed via dedicated roles modal */}

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
                        onClick={() => openEditModal(user)}
                        title="Edit User"
                      >
                        Edit
                      </Button>

                      <Button
                        variant="secondary"
                        size="sm"
                        onClick={() => openRolesModal(user)}
                        title="Manage User Roles"
                      >
                        <Users className="h-4 w-4" />
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
        <div className="space-y-6 p-1">
          {formErrors.length > 0 && (
            <div className="bg-theme-error-background border border-theme-error-border text-theme-error px-4 py-3 rounded">
              <ul className="list-disc list-inside">
                {formErrors.map((error, index) => (
                  <li key={index}>{error}</li>
                ))}
              </ul>
            </div>
          )}

          <div className="bg-theme-background border border-theme rounded-xl p-6 space-y-5">
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <label className="block text-sm font-semibold text-theme-primary">
                  First Name <span className="text-theme-error">*</span>
                </label>
                <input
                  type="text"
                  value={formData.first_name}
                  onChange={(e) => handleFormChange('first_name', e.target.value)}
                  className="w-full px-4 py-3 bg-theme-surface border-2 border-theme rounded-lg text-theme-primary placeholder-theme-tertiary focus:outline-none focus:border-theme-interactive-primary focus:bg-theme-background transition-all duration-200"
                  placeholder="Enter first name"
                  required
                />
              </div>
              <div className="space-y-2">
                <label className="block text-sm font-semibold text-theme-primary">
                  Last Name <span className="text-theme-error">*</span>
                </label>
                <input
                  type="text"
                  value={formData.last_name}
                  onChange={(e) => handleFormChange('last_name', e.target.value)}
                  className="w-full px-4 py-3 bg-theme-surface border-2 border-theme rounded-lg text-theme-primary placeholder-theme-tertiary focus:outline-none focus:border-theme-interactive-primary focus:bg-theme-background transition-all duration-200"
                  placeholder="Enter last name"
                  required
                />
              </div>
            </div>

            <div className="space-y-2">
              <label className="block text-sm font-semibold text-theme-primary">
                Email Address <span className="text-theme-error">*</span>
              </label>
              <input
                type="email"
                value={formData.email}
                onChange={(e) => handleFormChange('email', e.target.value)}
                className="w-full px-4 py-3 bg-theme-surface border-2 border-theme rounded-lg text-theme-primary placeholder-theme-tertiary focus:outline-none focus:border-theme-interactive-primary focus:bg-theme-background transition-all duration-200"
                placeholder="Enter email address"
                required
              />
            </div>

            <div className="space-y-2">
              <label className="block text-sm font-semibold text-theme-primary">
                Phone Number
              </label>
              <input
                type="tel"
                value={formData.phone || ''}
                onChange={(e) => handleFormChange('phone', e.target.value)}
                className="w-full px-4 py-3 bg-theme-surface border-2 border-theme rounded-lg text-theme-primary placeholder-theme-tertiary focus:outline-none focus:border-theme-interactive-primary focus:bg-theme-background transition-all duration-200"
                placeholder="Enter phone number (optional)"
              />
            </div>

            <div className="space-y-2">
              <label className="block text-sm font-semibold text-theme-primary">
                Roles <span className="text-theme-error">*</span>
                {rolesLoading && <span className="text-xs text-theme-secondary ml-2">(Loading...)</span>}
              </label>
              {rolesLoading ? (
                <div className="w-full px-4 py-3 bg-theme-surface border-2 border-theme rounded-lg flex items-center justify-center text-theme-secondary">
                  <svg className="animate-spin h-4 w-4 mr-2" fill="none" viewBox="0 0 24 24">
                    <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                  </svg>
                  Loading roles...
                </div>
              ) : (
                <select
                  value={formData.roles?.[0] || (availableRoles[0]?.value || 'account.member')}
                  onChange={(e) => setFormData(prev => ({ ...prev, roles: [e.target.value] }))}
                  className="w-full px-4 py-3 bg-theme-surface border-2 border-theme rounded-lg text-theme-primary focus:outline-none focus:border-theme-interactive-primary focus:bg-theme-background transition-all duration-200 appearance-none cursor-pointer"
                  required
                  disabled={availableRoles.length === 0}
                >
                  {availableRoles.length === 0 ? (
                    <option value="">No roles available</option>
                  ) : (
                    availableRoles.map(role => (
                      <option key={role.value} value={role.value}>
                        {role.label}
                      </option>
                    ))
                  )}
                </select>
              )}
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <label className="block text-sm font-semibold text-theme-primary">
                  Password <span className="text-theme-error">*</span>
                </label>
                <input
                  type="password"
                  value={formData.password}
                  onChange={(e) => handleFormChange('password', e.target.value)}
                  className="w-full px-4 py-3 bg-theme-surface border-2 border-theme rounded-lg text-theme-primary placeholder-theme-tertiary focus:outline-none focus:border-theme-interactive-primary focus:bg-theme-background transition-all duration-200"
                  placeholder="Enter password"
                  required
                />
              </div>
              <div className="space-y-2">
                <label className="block text-sm font-semibold text-theme-primary">
                  Confirm Password <span className="text-theme-error">*</span>
                </label>
                <input
                  type="password"
                  value={formData.password_confirmation}
                  onChange={(e) => handleFormChange('password_confirmation', e.target.value)}
                  className="w-full px-4 py-3 bg-theme-surface border-2 border-theme rounded-lg text-theme-primary placeholder-theme-tertiary focus:outline-none focus:border-theme-interactive-primary focus:bg-theme-background transition-all duration-200"
                  placeholder="Confirm password"
                  required
                />
              </div>
            </div>
          </div>

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
        title="Edit User Profile"
        maxWidth="4xl"
        variant="centered"
      >
        <div className="space-y-8 p-2">
          {formErrors.length > 0 && (
            <div className="bg-theme-error-background border border-theme-error-border text-theme-error px-4 py-3 rounded">
              <ul className="list-disc list-inside">
                {formErrors.map((error, index) => (
                  <li key={index}>{error}</li>
                ))}
              </ul>
            </div>
          )}

          <div className="space-y-8">
            {/* Personal Information Section */}
            <div className="space-y-8">
              {/* Personal Information Section */}
              <div className="bg-theme-background border-2 border-theme rounded-2xl p-8">
                <div className="flex items-center space-x-3 mb-6">
                  <div className="relative">
                    <div className="absolute inset-0 bg-gradient-to-br from-theme-interactive-primary/15 to-theme-interactive-primary/5 rounded-xl blur-md"></div>
                    <div className="relative w-10 h-10 bg-theme-surface/50 backdrop-blur-sm rounded-xl flex items-center justify-center">
                      <svg className="w-5 h-5 text-theme-interactive-primary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
                      </svg>
                    </div>
                  </div>
                  <div>
                    <h3 className="text-lg font-semibold text-theme-primary">Personal Information</h3>
                    <p className="text-sm text-theme-secondary">Update the user's basic profile information</p>
                  </div>
                </div>

                <div className="space-y-6">
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                    <div className="space-y-3">
                      <label className="block text-sm font-semibold text-theme-primary">
                        First Name <span className="text-theme-error">*</span>
                      </label>
                      <input
                        type="text"
                        value={formData.first_name}
                        onChange={(e) => handleFormChange('first_name', e.target.value)}
                        className="w-full px-4 py-4 bg-theme-surface border-2 border-theme rounded-xl text-theme-primary placeholder-theme-tertiary focus:outline-none focus:border-theme-interactive-primary focus:bg-theme-background focus:shadow-lg transition-all duration-300"
                        placeholder="Enter first name"
                        required
                      />
                    </div>
                    <div className="space-y-3">
                      <label className="block text-sm font-semibold text-theme-primary">
                        Last Name <span className="text-theme-error">*</span>
                      </label>
                      <input
                        type="text"
                        value={formData.last_name}
                        onChange={(e) => handleFormChange('last_name', e.target.value)}
                        className="w-full px-4 py-4 bg-theme-surface border-2 border-theme rounded-xl text-theme-primary placeholder-theme-tertiary focus:outline-none focus:border-theme-interactive-primary focus:bg-theme-background focus:shadow-lg transition-all duration-300"
                        placeholder="Enter last name"
                        required
                      />
                    </div>
                  </div>

                  <div className="space-y-3">
                    <label className="block text-sm font-semibold text-theme-primary">
                      Email Address <span className="text-theme-error">*</span>
                    </label>
                    <div className="relative">
                      <input
                        type="email"
                        value={formData.email}
                        onChange={(e) => handleFormChange('email', e.target.value)}
                        className="w-full pl-12 pr-4 py-4 bg-theme-surface border-2 border-theme rounded-xl text-theme-primary placeholder-theme-tertiary focus:outline-none focus:border-theme-interactive-primary focus:bg-theme-background focus:shadow-lg transition-all duration-300"
                        placeholder="Enter email address"
                        required
                      />
                      <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none">
                        <svg className="h-5 w-5 text-theme-tertiary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M16 12a4 4 0 10-8 0 4 4 0 008 0zm0 0v1.5a2.5 2.5 0 005 0V12a9 9 0 10-9 9m4.5-1.206a8.959 8.959 0 01-4.5 1.207" />
                        </svg>
                      </div>
                    </div>
                  </div>

                  <div className="space-y-3">
                    <label className="block text-sm font-semibold text-theme-primary">
                      Phone Number
                    </label>
                    <div className="relative">
                      <input
                        type="tel"
                        value={formData.phone || ''}
                        onChange={(e) => handleFormChange('phone', e.target.value)}
                        className="w-full pl-12 pr-4 py-4 bg-theme-surface border-2 border-theme rounded-xl text-theme-primary placeholder-theme-tertiary focus:outline-none focus:border-theme-interactive-primary focus:bg-theme-background focus:shadow-lg transition-all duration-300"
                        placeholder="Enter phone number (optional)"
                      />
                      <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none">
                        <svg className="h-5 w-5 text-theme-tertiary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 5a2 2 0 012-2h3.28a1 1 0 01.948.684l1.498 4.493a1 1 0 01-.502 1.21l-2.257 1.13a11.042 11.042 0 005.516 5.516l1.13-2.257a1 1 0 011.21-.502l4.493 1.498a1 1 0 01.684.949V19a2 2 0 01-2 2h-1C9.716 21 3 14.284 3 6V5z" />
                        </svg>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>

          {/* Footer Actions */}
          <div className="flex items-center justify-between pt-8 mt-8 border-t-2 border-theme">
            <div className="text-sm text-theme-secondary">
              Make sure all information is accurate before updating the user profile.
            </div>
            <div className="flex space-x-4">
              <Button
                variant="secondary"
                size="lg"
                onClick={() => {
                  setShowEditModal(false);
                  resetForm();
                }}className="px-8"
              >
                Cancel
              </Button>
              <Button
                variant="primary"
                size="lg"
                onClick={handleEditUser}
                disabled={actionLoading}
                className="px-8"
              >
                {actionLoading ? (
                  <div className="flex items-center space-x-2">
                    <svg className="animate-spin -ml-1 mr-2 h-4 w-4 text-white" fill="none" viewBox="0 0 24 24">
                      <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                      <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                    </svg>
                    <span>Updating...</span>
                  </div>
                ) : (
                  <div className="flex items-center space-x-2">
                    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
                    </svg>
                    <span>Update User</span>
                  </div>
                )}
              </Button>
            </div>
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

      {/* User Roles Management Modal */}
      <UserRolesModal
        user={selectedUser}
        isOpen={showRolesModal}
        onClose={() => {
          setShowRolesModal(false);
          setSelectedUser(null);
        }}
        onUserUpdated={() => {
          loadData();
        }}
      />
        </>
      )}
    </PageContainer>
  );
};

export { AdminUsersPage };