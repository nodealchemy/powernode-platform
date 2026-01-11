// Types for UsersPage components
import { User, UserFormData, UserStats } from '@/features/account/users/services/usersApi';

export type StatusFilter = 'all' | 'active' | 'suspended' | 'inactive';
export type SortBy = 'name' | 'email' | 'created_at' | 'last_login_at';
export type SortOrder = 'asc' | 'desc';

export interface UserFiltersState {
  searchTerm: string;
  statusFilter: StatusFilter;
  roleFilter: string;
  sortBy: SortBy;
  sortOrder: SortOrder;
}

export interface TeamStatsCardsProps {
  userStats: UserStats;
}

export interface TeamFiltersPanelProps {
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

export interface TeamBulkActionsBarProps {
  selectedCount: number;
  onClearSelection: () => void;
  onExport: () => void;
  onActivate: () => void;
  onSuspend: () => void;
  onDelete: () => void;
  actionLoading: boolean;
}

export interface TeamMembersTableProps {
  users: User[];
  selectedUsers: Set<string>;
  currentUserId: string | undefined;
  actionLoading: boolean;
  onToggleSelectAll: () => void;
  onToggleUserSelection: (userId: string) => void;
  onEditUser: (user: User) => void;
  onRolesModal: (user: User) => void;
  onImpersonateUser: (user: User) => void;
  onUserAction: (user: User, action: 'suspend' | 'activate' | 'unlock' | 'reset_password' | 'resend_verification') => void;
  onDeleteUser: (user: User) => void;
}

export interface CreateTeamMemberModalProps {
  isOpen: boolean;
  formData: UserFormData;
  formErrors: string[];
  actionLoading: boolean;
  onClose: () => void;
  onFormChange: (field: keyof UserFormData, value: string | string[]) => void;
  onSubmit: () => void;
}

export interface EditTeamMemberModalProps {
  isOpen: boolean;
  formData: UserFormData;
  formErrors: string[];
  actionLoading: boolean;
  onClose: () => void;
  onFormChange: (field: keyof UserFormData, value: string | string[]) => void;
  onSubmit: () => void;
}

export interface DeleteTeamMemberModalProps {
  isOpen: boolean;
  userName: string | undefined;
  actionLoading: boolean;
  onClose: () => void;
  onConfirm: () => void;
}
