// Types for the UsersTable components (one table, two scopes — see userScopes.ts)
import { User, UserFormData, UserStats } from '@/features/account/users/services/usersApi';
import type { RowGates } from './userScopes';

export type StatusFilter = 'all' | 'active' | 'suspended' | 'inactive';
export type SortBy = 'name' | 'email' | 'created_at' | 'last_login_at';
export type SortOrder = 'asc' | 'desc';

export type UserRowAction = 'suspend' | 'activate' | 'unlock' | 'reset_password' | 'resend_verification' | 'manual_verify';

export interface UserFiltersState {
  searchTerm: string;
  statusFilter: StatusFilter;
  roleFilter: string;
  sortBy: SortBy;
  sortOrder: SortOrder;
}

export interface UserStatsCardsProps {
  userStats: UserStats;
}

export interface UserFiltersPanelProps {
  filters: UserFiltersState;
  totalUsers: number;
  filteredCount: number;
  availableRoles: Array<{ value: string; label: string; description: string }>;
  rolesLoading: boolean;
  onSearchChange: (value: string) => void;
  onStatusFilterChange: (value: StatusFilter) => void;
  onRoleFilterChange: (value: string) => void;
  onSortByChange: (value: SortBy) => void;
}

export interface UserBulkActionsBarProps {
  selectedCount: number;
  showStatusActions: boolean;
  showDelete: boolean;
  onClearSelection: () => void;
  onExport: () => void;
  onActivate: () => void;
  onSuspend: () => void;
  onDelete: () => void;
  actionLoading: boolean;
}

export interface UsersTableRowsProps {
  users: User[];
  selectedUsers: Set<string>;
  actionLoading: boolean;
  showAccountColumn: boolean;
  gatesFor: (user: User) => RowGates;
  onToggleSelectAll: () => void;
  onToggleUserSelection: (userId: string) => void;
  onEditUser: (user: User) => void;
  onRolesModal: (user: User) => void;
  onImpersonateUser: (user: User) => void;
  onUserAction: (user: User, action: UserRowAction) => void;
  onDeleteUser: (user: User) => void;
}

export interface CreateUserModalProps {
  isOpen: boolean;
  formData: UserFormData;
  formErrors: string[];
  actionLoading: boolean;
  onClose: () => void;
  onFormChange: (field: keyof UserFormData, value: string | string[]) => void;
  onSubmit: () => void;
}

export interface EditUserModalProps {
  isOpen: boolean;
  formData: UserFormData;
  formErrors: string[];
  actionLoading: boolean;
  onClose: () => void;
  onFormChange: (field: keyof UserFormData, value: string | string[]) => void;
  onSubmit: () => void;
}

export interface DeleteUserModalProps {
  isOpen: boolean;
  userName: string | undefined;
  actionLoading: boolean;
  onClose: () => void;
  onConfirm: () => void;
}
