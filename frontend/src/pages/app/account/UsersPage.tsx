import React, { useState, useEffect, useCallback, useMemo } from 'react';
import { useSelector, useDispatch } from 'react-redux';
import { RootState, AppDispatch } from '@/shared/services';
import { startImpersonation } from '@/shared/services/slices/authSlice';
import { usersApi, User, UserFormData, UserStats } from '@/features/account/users/services/usersApi';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import { UserRolesModal } from '@/features/account/users/components/UserRolesModal';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { UserPlus, RefreshCw, Filter, Download } from 'lucide-react';

import {
  TeamStatsCards,
  TeamFiltersPanel,
  TeamBulkActionsBar,
  TeamMembersTable,
  CreateTeamMemberModal,
  EditTeamMemberModal,
  DeleteTeamMemberModal,
  StatusFilter,
  SortBy,
  UserFiltersState
} from './users-page';

const UsersPage: React.FC = () => {
  const dispatch = useDispatch<AppDispatch>();
  const { user: currentUser } = useSelector((state: RootState) => state.auth);
  const { showNotification } = useNotifications();
  const { confirm, ConfirmationDialog } = useConfirmation();
  usePageWebSocket({ pageType: 'account' });
  const [users, setUsers] = useState<User[]>([]);
  const [filteredUsers, setFilteredUsers] = useState<User[]>([]);
  const [userStats, setUserStats] = useState<UserStats | null>(null);
  const [loading, setLoading] = useState(true);
  const [selectedUser, setSelectedUser] = useState<User | null>(null);
  const [selectedUsers, setSelectedUsers] = useState<Set<string>>(new Set());
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [showEditModal, setShowEditModal] = useState(false);
  const [showDeleteModal, setShowDeleteModal] = useState(false);
  const [showRolesModal, setShowRolesModal] = useState(false);
  const [selectedUserForRoles, setSelectedUserForRoles] = useState<User | null>(null);
  const [actionLoading, setActionLoading] = useState(false);

  // Filtering and search state
  const [filters, setFilters] = useState<UserFiltersState>({
    searchTerm: '',
    statusFilter: 'all',
    roleFilter: 'all',
    sortBy: 'name',
    sortOrder: 'asc'
  });
  const [showFilters, setShowFilters] = useState(false);

  // Form state
  const [formData, setFormData] = useState<UserFormData>({
    name: '',
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
    } catch {
      showNotification('Failed to load users. Please check your connection and try again.', 'error');
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
    } catch {
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
    if (filters.searchTerm) {
      filtered = filtered.filter(user =>
        user.name.toLowerCase().includes(filters.searchTerm.toLowerCase()) ||
        user.email.toLowerCase().includes(filters.searchTerm.toLowerCase()) ||
        user.phone?.toLowerCase().includes(filters.searchTerm.toLowerCase())
      );
    }

    // Apply status filter
    if (filters.statusFilter !== 'all') {
      filtered = filtered.filter(user => user.status === filters.statusFilter);
    }

    // Apply role filter
    if (filters.roleFilter !== 'all') {
      filtered = filtered.filter(user => user.roles?.includes(filters.roleFilter));
    }

    // Apply sorting
    filtered.sort((a, b) => {
      let aVal: string | Date, bVal: string | Date;

      switch (filters.sortBy) {
        case 'name':
          aVal = a.name.toLowerCase();
          bVal = b.name.toLowerCase();
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

      if (aVal < bVal) return filters.sortOrder === 'asc' ? -1 : 1;
      if (aVal > bVal) return filters.sortOrder === 'asc' ? 1 : -1;
      return 0;
    });

    setFilteredUsers(filtered);
  }, [users, filters]);

  // Handle form changes
  const handleFormChange = (field: keyof UserFormData, value: string | string[]) => {
    setFormData(prev => ({ ...prev, [field]: value }));
    if (formErrors.length > 0) {
      setFormErrors([]);
    }
  };

  // Reset form
  const resetForm = () => {
    setFormData({
      name: '',
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

  // Export users to CSV
  const exportUsers = (usersToExport: User[] = filteredUsers) => {
    const headers = ['Name', 'Email', 'Phone', 'Roles', 'Status', 'Verified', 'Last Login', 'Created Date'];
    const rows = usersToExport.map(user => [
      user.name,
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
          confirm({
            title: 'Delete Team Members',
            message: `Are you sure you want to delete ${selectedUsers.size} team member${selectedUsers.size > 1 ? 's' : ''}? This action cannot be undone.`,
            confirmLabel: 'Delete',
            variant: 'danger',
            onConfirm: async () => {
              await Promise.all(userIds.map(id => usersApi.deleteUser(id)));
              await loadData();
              setSelectedUsers(new Set());
            }
          });
          return;
        case 'export': {
          const selectedUserData = filteredUsers.filter(u => selectedUsers.has(u.id));
          exportUsers(selectedUserData);
          return;
        }
      }

      await loadData();
      setSelectedUsers(new Set());
    } catch {
      showNotification(`Failed to ${action} selected users. Please try again.`, 'error');
    } finally {
      setActionLoading(false);
    }
  };

  // Handle user impersonation
  const handleImpersonateUser = async (user: User) => {
    if (user.id === currentUser?.id) {
      showNotification('Cannot impersonate yourself', 'error');
      return;
    }

    try {
      setActionLoading(true);
      await dispatch(startImpersonation({
        user_id: user.id,
        reason: 'Admin impersonation'
      })).unwrap();

      window.location.href = '/app';
    } catch {
      showNotification('Failed to impersonate user. Please try again.', 'error');
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
    } catch {
      setFormErrors(['Failed to create user. Please try again.']);
    } finally {
      setActionLoading(false);
    }
  };

  // Handle edit user
  const handleEditUser = async () => {
    if (!selectedUser) return;

    const updateData = {
      name: formData.name,
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
    } catch {
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
        showNotification(response.message || 'Failed to delete user', 'error');
      }
    } catch {
      showNotification('Failed to delete user. Please try again.', 'error');
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
        showNotification(response.message || `Failed to ${action} user`, 'error');
      }
    } catch {
      showNotification(`Failed to ${action} user. Please try again.`, 'error');
    } finally {
      setActionLoading(false);
    }
  };

  // Open edit modal
  const openEditModal = (user: User) => {
    setSelectedUser(user);
    setFormData({
      name: user.name || '',
      email: user.email,
      phone: user.phone || '',
      roles: ['account.member'],
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

  // Clear filters helper
  const clearFilters = () => {
    setFilters({
      searchTerm: '',
      statusFilter: 'all',
      roleFilter: 'all',
      sortBy: 'name',
      sortOrder: 'asc'
    });
  };

  const isFiltersDefault = filters.searchTerm === '' &&
    filters.statusFilter === 'all' &&
    filters.roleFilter === 'all' &&
    filters.sortBy === 'name' &&
    filters.sortOrder === 'asc';

  const pageActions: PageAction[] = useMemo(() => [
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
      onClick: clearFilters,
      variant: 'secondary',
      disabled: isFiltersDefault
    },
    {
      id: 'sort-toggle',
      label: filters.sortOrder === 'asc' ? 'Sort Desc' : 'Sort Asc',
      onClick: () => setFilters(prev => ({ ...prev, sortOrder: prev.sortOrder === 'asc' ? 'desc' : 'asc' })),
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
  ], [loading, filteredUsers.length, showFilters, isFiltersDefault, filters.sortOrder, loadData]);

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'Account' },
    { label: 'User Management' }
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
            <TeamFiltersPanel
              filters={filters}
              totalUsers={users.length}
              filteredCount={filteredUsers.length}
              availableRoles={availableRoles}
              rolesLoading={rolesLoading}
              onSearchChange={(value) => setFilters(prev => ({ ...prev, searchTerm: value }))}
              onStatusFilterChange={(value: StatusFilter) => setFilters(prev => ({ ...prev, statusFilter: value }))}
              onRoleFilterChange={(value) => setFilters(prev => ({ ...prev, roleFilter: value }))}
              onSortByChange={(value: SortBy) => setFilters(prev => ({ ...prev, sortBy: value }))}
            />
          )}

          {/* Stats Cards */}
          {userStats && <TeamStatsCards userStats={userStats} />}

          {/* Bulk Operations Bar */}
          {selectedUsers.size > 0 && (
            <TeamBulkActionsBar
              selectedCount={selectedUsers.size}
              onClearSelection={() => setSelectedUsers(new Set())}
              onExport={() => handleBulkAction('export')}
              onActivate={() => handleBulkAction('activate')}
              onSuspend={() => handleBulkAction('suspend')}
              onDelete={() => handleBulkAction('delete')}
              actionLoading={actionLoading}
            />
          )}

          {/* Users Table */}
          <TeamMembersTable
            users={filteredUsers}
            selectedUsers={selectedUsers}
            currentUserId={currentUser?.id}
            actionLoading={actionLoading}
            onToggleSelectAll={toggleSelectAll}
            onToggleUserSelection={toggleUserSelection}
            onEditUser={openEditModal}
            onRolesModal={openRolesModal}
            onImpersonateUser={handleImpersonateUser}
            onUserAction={handleUserAction}
            onDeleteUser={openDeleteModal}
          />

          {/* Create User Modal */}
          <CreateTeamMemberModal
            isOpen={showCreateModal}
            formData={formData}
            formErrors={formErrors}
            actionLoading={actionLoading}
            onClose={() => {
              setShowCreateModal(false);
              resetForm();
            }}
            onFormChange={handleFormChange}
            onSubmit={handleCreateUser}
          />

          {/* Edit User Modal */}
          <EditTeamMemberModal
            isOpen={showEditModal}
            formData={formData}
            formErrors={formErrors}
            actionLoading={actionLoading}
            onClose={() => {
              setShowEditModal(false);
              resetForm();
            }}
            onFormChange={handleFormChange}
            onSubmit={handleEditUser}
          />

          {/* Delete Confirmation Modal */}
          <DeleteTeamMemberModal
            isOpen={showDeleteModal}
            userName={selectedUser?.name}
            actionLoading={actionLoading}
            onClose={() => {
              setShowDeleteModal(false);
              resetForm();
            }}
            onConfirm={handleDeleteUser}
          />

          {/* User Roles Modal */}
          <UserRolesModal
            user={selectedUserForRoles}
            isOpen={showRolesModal}
            onClose={handleRoleModalClose}
            onUserUpdated={handleUserRolesUpdated}
          />
          {ConfirmationDialog}
        </>
      )}
    </PageContainer>
  );
};

export { UsersPage };
