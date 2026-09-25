import { hasPermissions } from '@/shared/utils/permissionUtils';
import type { User as AuthUser } from '@/shared/services/slices/authSlice';
import {
  usersApi,
  User,
  UserResponse,
  UsersListResponse,
  UserUpdateData,
} from '@/features/account/users/services/usersApi';

/**
 * The two populations one UsersTable can manage:
 * - 'account': the current account's users (Api::V1::UsersController, /users/*)
 * - 'all': every account's users (Api::V1::Admin::UsersController, /admin/users/*)
 */
export type UserScope = 'account' | 'all';

/**
 * Host-owned capability id for impersonation. /impersonations is served by an
 * extension, not core, so the row action exists only when an extension
 * registers metadata for this id (featureRegistry.registerSlotMeta) naming the
 * permissions that open it. Core never names the extension.
 */
export const USER_IMPERSONATION_SLOT = 'account.users.impersonate';

interface ScopeEndpoints {
  list: () => Promise<UsersListResponse>;
  update: (userId: string, data: UserUpdateData) => Promise<UserResponse>;
  remove: (userId: string) => Promise<{ success: boolean; message?: string }>;
}

/** Which endpoint each scope reads and writes. Create and the member actions
 *  (suspend/activate/unlock/reset/resend/verify) exist only on /users/*, which
 *  resolves users in the current account; rowGates keeps those actions to
 *  such rows. */
export const SCOPE_ENDPOINTS: Record<UserScope, ScopeEndpoints> = {
  account: {
    list: () => usersApi.getUsers(),
    update: (userId, data) => usersApi.updateUser(userId, data),
    remove: (userId) => usersApi.deleteUser(userId),
  },
  all: {
    list: () => usersApi.getAllUsers(),
    update: (userId, data) => usersApi.updateAdminUser(userId, data),
    remove: (userId) => usersApi.deleteAdminUser(userId),
  },
};

// The permission each gate needs, mirroring the server's own checks:
// users_controller.rb (set_user / user_update_params / before_actions) for
// 'account', admin/users_controller.rb for 'all'. Roles are edited through
// /admin/users/:id (UserRolesModal) in both scopes.
const ROW_PERMISSIONS: Record<UserScope, { edit: string[]; roles: string[]; manage: string[]; delete: string[] }> = {
  account: {
    edit: ['users.update'],
    roles: ['admin.user.update'],
    manage: ['admin.user.manage'],
    delete: ['admin.user.delete'],
  },
  all: {
    edit: ['admin.user.update'],
    roles: ['admin.user.update'],
    manage: ['admin.user.manage'],
    delete: ['admin.user.delete'],
  },
};

export interface RowGates {
  edit: boolean;
  roles: boolean;
  manage: boolean;
  delete: boolean;
  impersonate: boolean;
}

/**
 * What the current user may do to one row, from permissions only.
 * `impersonationPermissions` is the registered capability's permission list,
 * or null when no extension registered it.
 */
export const rowGates = (
  scope: UserScope,
  currentUser: AuthUser | null,
  row: User,
  impersonationPermissions: string[] | null
): RowGates => {
  const perms = ROW_PERMISSIONS[scope];
  const isSelf = row.id === currentUser?.id;
  const inOwnAccount = scope === 'account' || (!!row.account?.id && row.account.id === currentUser?.account?.id);

  return {
    edit: hasPermissions(currentUser, perms.edit),
    roles: hasPermissions(currentUser, perms.roles),
    manage: !isSelf && inOwnAccount && hasPermissions(currentUser, perms.manage),
    delete: !isSelf && hasPermissions(currentUser, perms.delete),
    // Auth::ImpersonationService refuses an inactive target, and a target in
    // another account unless the actor holds system.admin.
    impersonate: !isSelf &&
      row.status === 'active' &&
      (inOwnAccount || hasPermissions(currentUser, ['system.admin'])) &&
      !!impersonationPermissions?.length &&
      hasPermissions(currentUser, impersonationPermissions),
  };
};

export interface PageGates {
  create: boolean;
  invite: boolean;
  bulkStatus: boolean;
  bulkDelete: boolean;
}

/** Page-level actions, from permissions only. */
export const pageGates = (scope: UserScope, currentUser: AuthUser | null): PageGates => ({
  // users#create builds in the current account, so the all-accounts list does
  // not offer it: creating there would imply a cross-account create.
  create: scope === 'account' && hasPermissions(currentUser, ['admin.user.create']),
  // Mirrors Api::V1::InvitationsController#authorize_invitations_access!.
  invite: scope === 'account' && hasPermissions(currentUser, ['team.invite', 'users.create']),
  // Bulk suspend/activate call the account-scoped /users/:id endpoints.
  bulkStatus: scope === 'account' && hasPermissions(currentUser, ROW_PERMISSIONS.account.manage),
  bulkDelete: hasPermissions(currentUser, ROW_PERMISSIONS[scope].delete),
});
