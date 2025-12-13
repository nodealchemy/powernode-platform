// Types for AdminUsersPage components
import { User, UserFormData, UserStats } from '@/features/users/services/usersApi';

export type StatusFilter = 'all' | 'active' | 'suspended' | 'inactive';
export type SortBy = 'name' | 'email' | 'created_at' | 'last_login_at';
export type SortOrder = 'asc' | 'desc';

export interface UserFiltersState {
  searchTerm: string;
  statusFilter: StatusFilter;
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
  onSearchChange: (value: string) => void;
  onStatusFilterChange: (value: StatusFilter) => void;
  onSortByChange: (value: SortBy) => void;
}

export interface BulkActionsBarProps {
  selectedCount: number;
  onClearSelection: () => void;
  onExport: () => void;
  onActivate: () => void;
  onSuspend: () => void;
  onDelete: () => void;
  actionLoading: boolean;
}

export interface UsersTableProps {
  users: User[];
  selectedUsers: Set<string>;
  currentUserId: string | undefined;
  openDropdownUserId: string | null;
  actionLoading: boolean;
  onToggleSelectAll: () => void;
  onToggleUserSelection: (userId: string) => void;
  onEditUser: (user: User) => void;
  onRolesModal: (user: User) => void;
  onImpersonateUser: (user: User) => void;
  onUserAction: (user: User, action: 'suspend' | 'activate' | 'unlock' | 'reset_password' | 'resend_verification') => void;
  onDeleteUser: (user: User) => void;
  onToggleDropdown: (userId: string) => void;
}

export interface CreateUserModalProps {
  isOpen: boolean;
  formData: UserFormData;
  formErrors: string[];
  actionLoading: boolean;
  availableRoles: Array<{ value: string; label: string; description: string }>;
  rolesLoading: boolean;
  onClose: () => void;
  onFormChange: (field: keyof UserFormData, value: string | string[]) => void;
  onRolesChange: (roles: string[]) => void;
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
