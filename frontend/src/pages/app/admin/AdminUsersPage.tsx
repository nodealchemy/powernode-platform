import React, { useState, useEffect, useCallback } from 'react';
import { useSelector, useDispatch } from 'react-redux';
import { RootState, AppDispatch } from '@/shared/services';
import { startImpersonation } from '@/shared/services/slices/authSlice';
import { usersApi, User, UserFormData, UserStats } from '@/features/account/users/services/usersApi';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import { UserPlus, RefreshCw, Filter, Download } from 'lucide-react';
import { UserRolesModal } from '@/features/account/users/components/UserRolesModal';
import {
  UserStatsCards,
  UserFiltersPanel,
  BulkActionsBar,
  UsersTable,
  CreateUserModal,
  EditUserModal,
  DeleteUserModal,
  StatusFilter,
  SortBy,
  SortOrder
} from './admin-users';

const AdminUsersPage: React.FC = () => {
  const dispatch = useDispatch<AppDispatch>();
  const { user: currentUser } = useSelector((state: RootState) => state.auth);
  const { showNotification } = useNotifications();
  const { confirm, ConfirmationDialog } = useConfirmation();

  // WebSocket for real-time updates
  usePageWebSocket({
    pageType: 'admin',
    onDataUpdate: () => {
      // Trigger data refresh if needed
    }
  });

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
  const [actionLoading, setActionLoading] = useState(false);
  const [availableRoles, setAvailableRoles] = useState<Array<{ value: string; label: string; description: string }>>([]);
  const [rolesLoading, setRolesLoading] = useState(true);

  // Filtering and search state
  const [searchTerm, setSearchTerm] = useState('');
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('all');
  const [sortBy, setSortBy] = useState<SortBy>('name');
  const [sortOrder, setSortOrder] = useState<SortOrder>('asc');
  const [showFilters, setShowFilters] = useState(false);
  const [openDropdownUserId, setOpenDropdownUserId] = useState<string | null>(null);

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

  // Load available roles
  const loadAvailableRoles = useCallback(async () => {
    try {
      setRolesLoading(true);
      const roles = await usersApi.getAvailableRoles();
      setAvailableRoles(roles);
    } catch (_error) {
      setAvailableRoles([]);
    } finally {
      setRolesLoading(false);
    }
  }, []);

  // Load users and stats
  const loadData = useCallback(async () => {
    try {
      setLoading(true);

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
    } catch (_error) {
      showNotification('Failed to load users. Please check your connection and try again.', 'error');
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

    if (searchTerm) {
      filtered = filtered.filter(user =>
        user.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
        user.email.toLowerCase().includes(searchTerm.toLowerCase()) ||
        user.phone?.toLowerCase().includes(searchTerm.toLowerCase())
      );
    }

    if (statusFilter !== 'all') {
      filtered = filtered.filter(user => user.status === statusFilter);
    }

    filtered.sort((a, b) => {
      let aVal: string | Date;
      let bVal: string | Date;

      switch (sortBy) {
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

      if (aVal < bVal) return sortOrder === 'asc' ? -1 : 1;
      if (aVal > bVal) return sortOrder === 'asc' ? 1 : -1;
      return 0;
    });

    setFilteredUsers(filtered);
  }, [users, searchTerm, statusFilter, sortBy, sortOrder]);

  // Form handlers
  const handleFormChange = (field: keyof UserFormData, value: string | string[]) => {
    setFormData(prev => ({ ...prev, [field]: value }));
    if (formErrors.length > 0) setFormErrors([]);
  };

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

  // Selection handlers
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
    const headers = ['Name', 'Email', 'Phone', 'Role', 'Status', 'Verified', 'Last Login', 'Created Date'];
    const rows = usersToExport.map(user => [
      user.name,
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

  // Bulk actions
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
            title: 'Delete Users',
            message: `Are you sure you want to delete ${selectedUsers.size} user${selectedUsers.size > 1 ? 's' : ''}? This action cannot be undone.`,
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
    } catch (_error) {
      showNotification(`Failed to ${action} selected users. Please try again.`, 'error');
    } finally {
      setActionLoading(false);
    }
  };

  // Impersonation
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
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to impersonate user. Please try again.';
      showNotification(errorMessage, 'error');
    } finally {
      setActionLoading(false);
    }
  };

  // Create user
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
    } catch (error) {
      const axiosError = error as { code?: string; response?: { status?: number; data?: { errors?: unknown; message?: string } }; message?: string };

      if (axiosError.code === 'ERR_NETWORK' || axiosError.code === 'ERR_FAILED') {
        setFormErrors(['Network error: Unable to connect to the server. Please check your connection.']);
      } else if (axiosError.response?.status === 401) {
        setFormErrors(['Authentication error: Your session may have expired. Please refresh the page.']);
      } else if (axiosError.response?.status === 403) {
        setFormErrors(['Permission denied: You do not have permission to create users.']);
      } else if (axiosError.response?.status === 422) {
        const validationErrors = axiosError.response?.data?.errors || axiosError.response?.data?.message;
        if (typeof validationErrors === 'object' && validationErrors !== null) {
          setFormErrors(Object.values(validationErrors as Record<string, string[]>).flat());
        } else if (validationErrors) {
          setFormErrors([String(validationErrors)]);
        } else {
          setFormErrors(['Validation error: Please check your input.']);
        }
      } else if (axiosError.response?.data?.message) {
        setFormErrors([axiosError.response.data.message]);
      } else if (axiosError.message) {
        setFormErrors([`Error: ${axiosError.message}`]);
      } else {
        setFormErrors(['An unexpected error occurred while creating the user.']);
      }
    } finally {
      setActionLoading(false);
    }
  };

  // Edit user
  const handleEditUser = async () => {
    if (!selectedUser) return;

    const updateData = {
      name: formData.name,
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
    } catch (_error) {
      setFormErrors(['Failed to update user. Please try again.']);
    } finally {
      setActionLoading(false);
    }
  };

  // Delete user
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
    } catch (_error) {
      showNotification('Failed to delete user. Please try again.', 'error');
    } finally {
      setActionLoading(false);
    }
  };

  // User actions
  const handleUserAction = async (user: User, action: 'suspend' | 'activate' | 'unlock' | 'reset_password' | 'resend_verification') => {
    // Confirmation for sensitive actions
    if (action === 'suspend') {
      confirm({
        title: 'Suspend User',
        message: `Are you sure you want to suspend ${user.name}? They will lose access to the platform until reactivated.`,
        confirmLabel: 'Suspend',
        variant: 'warning',
        onConfirm: async () => {
          setActionLoading(true);
          setOpenDropdownUserId(null);
          try {
            const response = await usersApi.suspendUser(user.id, 'Suspended by administrator');
            if (response.success) {
              await loadData();
            } else {
              showNotification(response.message || 'Failed to suspend user', 'error');
            }
          } catch (_error) {
            showNotification('Failed to suspend user. Please try again.', 'error');
          } finally {
            setActionLoading(false);
          }
        }
      });
      return;
    }
    if (action === 'activate') {
      confirm({
        title: 'Activate User',
        message: `Are you sure you want to activate ${user.name}? They will regain access to the platform.`,
        confirmLabel: 'Activate',
        variant: 'info',
        onConfirm: async () => {
          setActionLoading(true);
          setOpenDropdownUserId(null);
          try {
            const response = await usersApi.activateUser(user.id);
            if (response.success) {
              await loadData();
            } else {
              showNotification(response.message || 'Failed to activate user', 'error');
            }
          } catch (_error) {
            showNotification('Failed to activate user. Please try again.', 'error');
          } finally {
            setActionLoading(false);
          }
        }
      });
      return;
    }

    try {
      setActionLoading(true);
      setOpenDropdownUserId(null);
      let response;

      switch (action) {
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
    } catch (_error) {
      showNotification(`Failed to ${action} user. Please try again.`, 'error');
    } finally {
      setActionLoading(false);
    }
  };

  // Modal openers
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

  const openDeleteModal = (user: User) => {
    setSelectedUser(user);
    setShowDeleteModal(true);
  };

  const openRolesModal = (user: User) => {
    setSelectedUser(user);
    setShowRolesModal(true);
  };

  // Dropdown click outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (openDropdownUserId && !(event.target as Element).closest('.user-dropdown')) {
        setOpenDropdownUserId(null);
      }
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, [openDropdownUserId]);

  const pageActions: PageAction[] = [
    { id: 'refresh', label: 'Refresh', onClick: loadData, variant: 'secondary', icon: RefreshCw, disabled: loading },
    { id: 'export', label: 'Export All', onClick: () => exportUsers(), variant: 'secondary', icon: Download, disabled: loading || filteredUsers.length === 0 },
    { id: 'filters', label: showFilters ? 'Hide Filters' : 'Show Filters', onClick: () => setShowFilters(!showFilters), variant: 'secondary', icon: Filter },
    { id: 'clear-filters', label: 'Clear Filters', onClick: () => { setSearchTerm(''); setStatusFilter('all'); setSortBy('name'); setSortOrder('asc'); }, variant: 'secondary', disabled: searchTerm === '' && statusFilter === 'all' && sortBy === 'name' && sortOrder === 'asc' },
    { id: 'sort-toggle', label: sortOrder === 'asc' ? 'Sort Desc' : 'Sort Asc', onClick: () => setSortOrder(sortOrder === 'asc' ? 'desc' : 'asc'), variant: 'secondary', disabled: loading },
    { id: 'add-user', label: 'Add New User', onClick: () => setShowCreateModal(true), variant: 'primary', icon: UserPlus }
  ];

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'Admin', href: '/app/admin' },
    { label: 'Users' }
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
          {/* Filters */}
          {showFilters && (
            <UserFiltersPanel
              filters={{ searchTerm, statusFilter, sortBy, sortOrder }}
              totalUsers={users.length}
              filteredCount={filteredUsers.length}
              onSearchChange={setSearchTerm}
              onStatusFilterChange={setStatusFilter}
              onSortByChange={setSortBy}
            />
          )}

          {/* Stats */}
          {userStats && <UserStatsCards userStats={userStats} />}

          {/* Bulk Actions */}
          {selectedUsers.size > 0 && (
            <BulkActionsBar
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
          <UsersTable
            users={filteredUsers}
            selectedUsers={selectedUsers}
            currentUserId={currentUser?.id}
            openDropdownUserId={openDropdownUserId}
            actionLoading={actionLoading}
            onToggleSelectAll={toggleSelectAll}
            onToggleUserSelection={toggleUserSelection}
            onEditUser={openEditModal}
            onRolesModal={openRolesModal}
            onImpersonateUser={handleImpersonateUser}
            onUserAction={handleUserAction}
            onDeleteUser={openDeleteModal}
            onToggleDropdown={(userId) => setOpenDropdownUserId(openDropdownUserId === userId ? null : userId)}
          />

          {/* Modals */}
          <CreateUserModal
            isOpen={showCreateModal}
            formData={formData}
            formErrors={formErrors}
            actionLoading={actionLoading}
            availableRoles={availableRoles}
            rolesLoading={rolesLoading}
            onClose={() => { setShowCreateModal(false); resetForm(); }}
            onFormChange={handleFormChange}
            onRolesChange={(roles) => setFormData(prev => ({ ...prev, roles }))}
            onSubmit={handleCreateUser}
          />

          <EditUserModal
            isOpen={showEditModal}
            formData={formData}
            formErrors={formErrors}
            actionLoading={actionLoading}
            onClose={() => { setShowEditModal(false); resetForm(); }}
            onFormChange={handleFormChange}
            onSubmit={handleEditUser}
          />

          <DeleteUserModal
            isOpen={showDeleteModal}
            userName={selectedUser?.name}
            actionLoading={actionLoading}
            onClose={() => { setShowDeleteModal(false); resetForm(); }}
            onConfirm={handleDeleteUser}
          />

          <UserRolesModal
            user={selectedUser}
            isOpen={showRolesModal}
            onClose={() => { setShowRolesModal(false); setSelectedUser(null); }}
            onUserUpdated={() => { loadData(); }}
          />
          {ConfirmationDialog}
        </>
      )}
    </PageContainer>
  );
};

export { AdminUsersPage };
