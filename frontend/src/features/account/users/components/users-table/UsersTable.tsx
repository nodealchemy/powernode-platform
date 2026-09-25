import React, { useState, useEffect, useCallback, useMemo } from 'react';
import { useSelector, useDispatch } from 'react-redux';
import { useSearchParams } from 'react-router-dom';
import { RootState, AppDispatch } from '@/shared/services';
import { startImpersonation } from '@/shared/services/slices/authSlice';
import { featureRegistry } from '@/shared/services/featureRegistry';
import { usersApi, User, UserFormData, UserStats } from '@/features/account/users/services/usersApi';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { PageAction } from '@/shared/components/layout/PageContainer';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import { UserRolesModal } from '@/features/account/users/components/UserRolesModal';
import { InviteTeamMemberModal } from '@/features/account/components/InviteTeamMemberModal';
import { Modal } from '@/shared/components/ui/Modal';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { UserPlus, Mail, RefreshCw, Filter, Download, Copy, Check, KeyRound } from 'lucide-react';
import { UserStatsCards } from './UserStatsCards';
import { UserFiltersPanel } from './UserFiltersPanel';
import { UserBulkActionsBar } from './UserBulkActionsBar';
import { UsersTableRows } from './UsersTableRows';
import { CreateUserModal, EditUserModal, DeleteUserModal } from './UserFormModals';
import { StatusFilter, SortBy, UserFiltersState, UserRowAction } from './types';
import { SCOPE_ENDPOINTS, USER_IMPERSONATION_SLOT, UserScope, pageGates, rowGates } from './userScopes';

const DEFAULT_FILTERS: UserFiltersState = {
  searchTerm: '',
  statusFilter: 'all',
  roleFilter: 'all',
  sortBy: 'name',
  sortOrder: 'asc'
};

const EMPTY_FORM: UserFormData = {
  name: '',
  email: '',
  phone: '',
  roles: ['account.member'],
  password: '',
  password_confirmation: ''
};

export interface UsersTableProps {
  /** 'account': the current account's users; 'all': every account's users. */
  scope: UserScope;
  /** The host page renders these in its header (PageContainer actions). */
  onActionsReady?: (actions: PageAction[]) => void;
}

/**
 * The one user-management table. Both the account Users tab and
 * Administration → All Users render it; `scope` picks the population and the
 * endpoints (userScopes.ts), and every action is gated by permissions only.
 */
export const UsersTable: React.FC<UsersTableProps> = ({ scope, onActionsReady }) => {
  const dispatch = useDispatch<AppDispatch>();
  const { user: currentUser } = useSelector((state: RootState) => state.auth);
  const { showNotification } = useNotifications();
  const { confirm, ConfirmationDialog } = useConfirmation();
  const [searchParams, setSearchParams] = useSearchParams();
  usePageWebSocket({ pageType: 'account' });
  const endpoints = SCOPE_ENDPOINTS[scope];

  const [users, setUsers] = useState<User[]>([]);
  const [userStats, setUserStats] = useState<UserStats | null>(null);
  const [loading, setLoading] = useState(true);
  const [selectedUser, setSelectedUser] = useState<User | null>(null);
  const [selectedUsers, setSelectedUsers] = useState<Set<string>>(new Set());
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [showEditModal, setShowEditModal] = useState(false);
  const [showDeleteModal, setShowDeleteModal] = useState(false);
  const [showInviteModal, setShowInviteModal] = useState(false);
  const [selectedUserForRoles, setSelectedUserForRoles] = useState<User | null>(null);
  const [actionLoading, setActionLoading] = useState(false);
  const [tempPassword, setTempPassword] = useState<{ password: string; userName: string } | null>(null);
  const [copied, setCopied] = useState(false);
  const [filters, setFilters] = useState<UserFiltersState>(DEFAULT_FILTERS);
  const [showFilters, setShowFilters] = useState(false);
  const [formData, setFormData] = useState<UserFormData>(EMPTY_FORM);
  const [formErrors, setFormErrors] = useState<string[]>([]);
  const [availableRoles, setAvailableRoles] = useState<Array<{ value: string; label: string; description: string }>>([]);
  const [rolesLoading, setRolesLoading] = useState(true);

  const gates = pageGates(scope, currentUser ?? null);
  // Registered by whichever extension serves /impersonations; absent in core mode.
  const impersonationPermissions = featureRegistry.getSlotMeta(USER_IMPERSONATION_SLOT)?.permissions ?? null;
  const gatesFor = useCallback(
    (row: User) => rowGates(scope, currentUser ?? null, row, impersonationPermissions),
    [scope, currentUser, impersonationPermissions]
  );

  const loadData = useCallback(async () => {
    try {
      setLoading(true);

      // /users/stats counts the current account only, so the all-accounts
      // scope has no stats to show.
      const [usersResponse, statsResponse] = await Promise.all([
        endpoints.list(),
        scope === 'account' ? usersApi.getUserStats() : Promise.resolve(null)
      ]);

      if (usersResponse.success) {
        setUsers(usersResponse.data);
      } else {
        throw new Error(usersResponse.message || 'Failed to load users');
      }

      setUserStats(statsResponse?.success ? statsResponse.data : null);
    } catch (_error) {
      showNotification('Failed to load users. Please check your connection and try again.', 'error');
    } finally {
      setLoading(false);
    }
  }, [endpoints, scope]);

  const loadAvailableRoles = useCallback(async () => {
    try {
      setRolesLoading(true);
      setAvailableRoles(await usersApi.getAvailableRoles());
    } catch (_error) {
      setAvailableRoles([]);
    } finally {
      setRolesLoading(false);
    }
  }, []);

  useEffect(() => {
    loadData();
    loadAvailableRoles();
  }, [loadData, loadAvailableRoles]);

  const filteredUsers = useMemo(() => {
    const term = filters.searchTerm.toLowerCase();
    const filtered = users.filter(user =>
      (!term ||
        user.name.toLowerCase().includes(term) ||
        user.email.toLowerCase().includes(term) ||
        user.phone?.toLowerCase().includes(term)) &&
      (filters.statusFilter === 'all' || user.status === filters.statusFilter) &&
      (filters.roleFilter === 'all' || user.roles?.includes(filters.roleFilter))
    );

    const sortKey = (user: User): string | number => {
      switch (filters.sortBy) {
        case 'email': return user.email.toLowerCase();
        case 'created_at': return new Date(user.created_at).getTime();
        case 'last_login_at': return user.last_login_at ? new Date(user.last_login_at).getTime() : 0;
        default: return user.name.toLowerCase();
      }
    };

    return filtered.sort((a, b) => {
      const aVal = sortKey(a);
      const bVal = sortKey(b);
      if (aVal < bVal) return filters.sortOrder === 'asc' ? -1 : 1;
      if (aVal > bVal) return filters.sortOrder === 'asc' ? 1 : -1;
      return 0;
    });
  }, [users, filters]);

  const handleFormChange = (field: keyof UserFormData, value: string | string[]) => {
    setFormData(prev => ({ ...prev, [field]: value }));
    if (formErrors.length > 0) {
      setFormErrors([]);
    }
  };

  const resetForm = () => {
    setFormData(EMPTY_FORM);
    setFormErrors([]);
    setSelectedUser(null);
  };

  const toggleUserSelection = (userId: string) => {
    const next = new Set(selectedUsers);
    if (next.has(userId)) {
      next.delete(userId);
    } else {
      next.add(userId);
    }
    setSelectedUsers(next);
  };

  const toggleSelectAll = () => {
    setSelectedUsers(selectedUsers.size === filteredUsers.length ? new Set() : new Set(filteredUsers.map(u => u.id)));
  };

  const exportUsers = (usersToExport: User[] = filteredUsers) => {
    const headers = ['Name', 'Email', 'Phone', 'Account', 'Roles', 'Status', 'Verified', 'Last Login', 'Created Date'];
    const rows = usersToExport.map(user => [
      user.name,
      user.email,
      user.phone || '',
      user.account?.name || '',
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

  const handleBulkAction = async (action: 'suspend' | 'activate' | 'delete' | 'export') => {
    if (selectedUsers.size === 0) return;
    const userIds = Array.from(selectedUsers);

    if (action === 'export') {
      exportUsers(filteredUsers.filter(u => selectedUsers.has(u.id)));
      return;
    }

    if (action === 'delete') {
      confirm({
        title: 'Delete Users',
        message: `Are you sure you want to delete ${userIds.length} user${userIds.length > 1 ? 's' : ''}? This action cannot be undone.`,
        confirmLabel: 'Delete',
        variant: 'danger',
        onConfirm: async () => {
          const results = await Promise.allSettled(userIds.map(id => endpoints.remove(id)));
          const failed = results.filter(r => r.status === 'rejected' || !r.value.success).length;
          if (failed > 0) {
            showNotification(`Failed to delete ${failed} of ${userIds.length} selected user${userIds.length > 1 ? 's' : ''}.`, 'error');
          }
          await loadData();
          setSelectedUsers(new Set());
        }
      });
      return;
    }

    try {
      setActionLoading(true);
      await Promise.all(userIds.map(id =>
        action === 'suspend'
          ? usersApi.suspendUser(id, 'Bulk suspended by administrator')
          : usersApi.activateUser(id)
      ));
      await loadData();
      setSelectedUsers(new Set());
    } catch (_error) {
      showNotification(`Failed to ${action} selected users. Please try again.`, 'error');
    } finally {
      setActionLoading(false);
    }
  };

  const handleImpersonateUser = async (user: User) => {
    try {
      setActionLoading(true);
      await dispatch(startImpersonation({
        user_id: user.id,
        reason: 'Admin impersonation'
      })).unwrap();

      window.location.href = '/app';
    } catch (error) {
      showNotification(typeof error === 'string' ? error : 'Failed to impersonate user. Please try again.', 'error');
    } finally {
      setActionLoading(false);
    }
  };

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
    } catch (error: unknown) {
      const axiosErr = error as { response?: { data?: { details?: { errors?: string[] }; error?: string } } };
      const serverErrors = axiosErr.response?.data?.details?.errors;
      setFormErrors(serverErrors?.length ? serverErrors : [axiosErr.response?.data?.error || 'Failed to create user. Please try again.']);
    } finally {
      setActionLoading(false);
    }
  };

  const handleEditUser = async () => {
    if (!selectedUser) return;

    try {
      setActionLoading(true);
      const response = await endpoints.update(selectedUser.id, {
        name: formData.name,
        email: formData.email,
        phone: formData.phone
      });

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

  const handleDeleteUser = async () => {
    if (!selectedUser) return;

    try {
      setActionLoading(true);
      const response = await endpoints.remove(selectedUser.id);

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

  const runUserAction = async (user: User, action: UserRowAction) => {
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
          if (response.success && response.data?.temporary_password) {
            setTempPassword({ password: response.data.temporary_password, userName: user.name });
            setCopied(false);
            await loadData();
            return;
          }
          break;
        case 'resend_verification':
          response = await usersApi.resendVerification(user.id);
          break;
        case 'manual_verify':
          response = await usersApi.manualVerify(user.id);
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

  // Suspend and activate change who can sign in, so they ask first.
  const handleUserAction = (user: User, action: UserRowAction) => {
    if (action === 'suspend' || action === 'activate') {
      const suspending = action === 'suspend';
      confirm({
        title: suspending ? 'Suspend User' : 'Activate User',
        message: suspending
          ? `Are you sure you want to suspend ${user.name}? They will lose access to the platform until reactivated.`
          : `Are you sure you want to activate ${user.name}? They will regain access to the platform.`,
        confirmLabel: suspending ? 'Suspend' : 'Activate',
        variant: suspending ? 'warning' : 'info',
        onConfirm: () => runUserAction(user, action)
      });
      return;
    }
    runUserAction(user, action);
  };

  const handleCopyPassword = async () => {
    if (!tempPassword) return;
    await navigator.clipboard.writeText(tempPassword.password);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const openEditModal = (user: User) => {
    setSelectedUser(user);
    setFormData({ ...EMPTY_FORM, name: user.name || '', email: user.email, phone: user.phone || '' });
    setShowEditModal(true);
  };

  const openDeleteModal = (user: User) => {
    setSelectedUser(user);
    setShowDeleteModal(true);
  };

  // URL-addressable: the "Invite Team Member" quick action (navigation.tsx)
  // links straight to /app/profile/users?invite=1 so the invite flow opens
  // without a second click, and the state survives a page reload/bookmark.
  useEffect(() => {
    if (gates.invite && searchParams.get('invite') === '1') {
      setShowInviteModal(true);
    }
  }, [searchParams, gates.invite]);

  const closeInviteModal = () => {
    setShowInviteModal(false);
    if (searchParams.has('invite')) {
      const next = new URLSearchParams(searchParams);
      next.delete('invite');
      setSearchParams(next, { replace: true });
    }
  };

  const isFiltersDefault = filters.searchTerm === '' &&
    filters.statusFilter === 'all' &&
    filters.roleFilter === 'all' &&
    filters.sortBy === 'name' &&
    filters.sortOrder === 'asc';

  const pageActions: PageAction[] = useMemo(() => [
    { id: 'refresh', label: 'Refresh', onClick: loadData, variant: 'secondary', icon: RefreshCw, disabled: loading },
    { id: 'export', label: 'Export All', onClick: () => exportUsers(), variant: 'secondary', icon: Download, disabled: loading || filteredUsers.length === 0 },
    { id: 'filters', label: showFilters ? 'Hide Filters' : 'Show Filters', onClick: () => setShowFilters(!showFilters), variant: 'secondary', icon: Filter },
    { id: 'clear-filters', label: 'Clear Filters', onClick: () => setFilters(DEFAULT_FILTERS), variant: 'secondary', disabled: isFiltersDefault },
    {
      id: 'sort-toggle',
      label: filters.sortOrder === 'asc' ? 'Sort Desc' : 'Sort Asc',
      onClick: () => setFilters(prev => ({ ...prev, sortOrder: prev.sortOrder === 'asc' ? 'desc' : 'asc' })),
      variant: 'secondary',
      disabled: loading
    },
    ...(gates.invite ? [ {
      id: 'invite-team-member',
      label: 'Invite Team Member',
      onClick: () => setShowInviteModal(true),
      variant: 'secondary' as const,
      icon: Mail
    } ] : []),
    ...(gates.create ? [ {
      id: 'add-user',
      label: 'Add New User',
      onClick: () => setShowCreateModal(true),
      variant: 'primary' as const,
      icon: UserPlus
    } ] : [])
  ], [loading, filteredUsers, showFilters, isFiltersDefault, filters.sortOrder, loadData, gates.invite, gates.create]);

  useEffect(() => {
    onActionsReady?.(loading ? [] : pageActions);
  }, [onActionsReady, pageActions, loading]);

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-64">
        <LoadingSpinner size="lg" />
      </div>
    );
  }

  return (
    <>
      {showFilters && (
        <UserFiltersPanel
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

      {userStats && <UserStatsCards userStats={userStats} />}

      {selectedUsers.size > 0 && (
        <UserBulkActionsBar
          selectedCount={selectedUsers.size}
          showStatusActions={gates.bulkStatus}
          showDelete={gates.bulkDelete}
          onClearSelection={() => setSelectedUsers(new Set())}
          onExport={() => handleBulkAction('export')}
          onActivate={() => handleBulkAction('activate')}
          onSuspend={() => handleBulkAction('suspend')}
          onDelete={() => handleBulkAction('delete')}
          actionLoading={actionLoading}
        />
      )}

      <UsersTableRows
        users={filteredUsers}
        selectedUsers={selectedUsers}
        actionLoading={actionLoading}
        showAccountColumn={scope === 'all'}
        gatesFor={gatesFor}
        onToggleSelectAll={toggleSelectAll}
        onToggleUserSelection={toggleUserSelection}
        onEditUser={openEditModal}
        onRolesModal={setSelectedUserForRoles}
        onImpersonateUser={handleImpersonateUser}
        onUserAction={handleUserAction}
        onDeleteUser={openDeleteModal}
      />

      {/* An EMAIL invitation (invitationsApi), distinct from "Add New User",
          which creates the user directly with a password. */}
      {gates.invite && (
        <InviteTeamMemberModal
          isOpen={showInviteModal}
          onClose={closeInviteModal}
          onInviteSent={() => showNotification('Invitation sent successfully', 'success')}
        />
      )}

      <CreateUserModal
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

      <EditUserModal
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

      <DeleteUserModal
        isOpen={showDeleteModal}
        userName={selectedUser?.name}
        actionLoading={actionLoading}
        onClose={() => {
          setShowDeleteModal(false);
          resetForm();
        }}
        onConfirm={handleDeleteUser}
      />

      <UserRolesModal
        user={selectedUserForRoles}
        isOpen={!!selectedUserForRoles}
        onClose={() => setSelectedUserForRoles(null)}
        onUserUpdated={loadData}
      />
      {ConfirmationDialog}

      <Modal
        isOpen={!!tempPassword}
        onClose={() => setTempPassword(null)}
        title="Password Reset Successful"
        icon={<KeyRound className="w-6 h-6" />}
        maxWidth="sm"
      >
        <div className="space-y-4">
          <p className="text-sm text-theme-secondary">
            A temporary password has been generated for <strong className="text-theme-primary">{tempPassword?.userName}</strong>.
            Please share this password securely — it cannot be retrieved again.
          </p>
          <div className="flex items-center gap-2 p-3 bg-theme-background rounded-lg border border-theme font-mono text-sm">
            <span className="flex-1 select-all text-theme-primary">{tempPassword?.password}</span>
            <button
              onClick={handleCopyPassword}
              className="p-1.5 rounded hover:bg-theme-surface-hover text-theme-secondary"
              title="Copy to clipboard"
            >
              {copied ? <Check className="h-4 w-4 text-theme-success-fg" /> : <Copy className="h-4 w-4" />}
            </button>
          </div>
          <div className="flex justify-end">
            <button
              onClick={() => setTempPassword(null)}
              className="px-4 py-2 text-sm font-medium rounded-lg bg-theme-interactive-primary text-theme-on-primary hover:bg-theme-interactive-primary-hover"
            >
              Done
            </button>
          </div>
        </div>
      </Modal>
    </>
  );
};
