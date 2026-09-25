import { render, screen, fireEvent, waitFor, within } from '@testing-library/react';
import { Provider } from 'react-redux';
import { configureStore } from '@reduxjs/toolkit';
import { MemoryRouter } from 'react-router-dom';
import { featureRegistry } from '@/shared/services/featureRegistry';
import { UsersTable } from './UsersTable';
import { USER_IMPERSONATION_SLOT, UserScope } from './userScopes';

const mockGetUsers = jest.fn();
const mockGetAllUsers = jest.fn();
const mockDeleteUser = jest.fn();
const mockDeleteAdminUser = jest.fn();
jest.mock('@/features/account/users/services/usersApi', () => ({
  usersApi: {
    getUsers: (...args: unknown[]) => mockGetUsers(...args),
    getAllUsers: (...args: unknown[]) => mockGetAllUsers(...args),
    deleteUser: (...args: unknown[]) => mockDeleteUser(...args),
    deleteAdminUser: (...args: unknown[]) => mockDeleteAdminUser(...args),
    updateUser: jest.fn(),
    updateAdminUser: jest.fn(),
    getUserStats: () => Promise.resolve({ success: false }),
    getAvailableRoles: () => Promise.resolve([]),
    getRoleColor: () => '',
    getStatusColor: () => '',
    formatRoles: (roles: string[]) => roles.join(', '),
  }
}));

jest.mock('@/shared/hooks/usePageWebSocket', () => ({ usePageWebSocket: () => {} }));
jest.mock('@/shared/hooks/useNotifications', () => ({ useNotifications: () => ({ showNotification: jest.fn() }) }));
jest.mock('@/features/account/users/components/UserRolesModal', () => ({ UserRolesModal: () => null }));
jest.mock('@/features/account/components/InviteTeamMemberModal', () => ({ InviteTeamMemberModal: () => null }));
jest.mock('@/shared/components/entity', () => ({ EntityLink: ({ label }: { label: string }) => <span>{label}</span> }));

const other = {
  id: 'u2', name: 'Other User', email: 'o@example.com', roles: ['account.member'], permissions: [],
  status: 'active', email_verified: true, locked: false, failed_login_attempts: 0, last_login_at: null,
  created_at: '2026-01-01T00:00:00Z', updated_at: '2026-01-01T00:00:00Z', preferences: {},
  account: { id: 'acct-1', name: 'Mine', status: 'active' },
};

// Roles that would grant everything if consulted; the gates must ignore them.
const renderTable = (scope: UserScope, permissions: string[]) => {
  const store = configureStore({
    reducer: {
      auth: (state = {
        user: { id: 'me', name: 'Me', email: 'me@example.com', roles: ['owner', 'system.admin'], permissions,
          account: { id: 'acct-1', name: 'Mine', status: 'active' } },
        isAuthenticated: true,
      }) => state,
    },
  });
  return render(
    <Provider store={store}>
      <MemoryRouter>
        <UsersTable scope={scope} />
      </MemoryRouter>
    </Provider>
  );
};

const row = async () => within(await screen.findByTestId('user-row-u2'));

beforeEach(() => {
  jest.clearAllMocks();
  featureRegistry.clear();
  mockGetUsers.mockResolvedValue({ success: true, data: [other] });
  mockGetAllUsers.mockResolvedValue({ success: true, data: [other] });
  mockDeleteUser.mockResolvedValue({ success: true });
  mockDeleteAdminUser.mockResolvedValue({ success: true });
});

describe('UsersTable — row actions per scope, permissions only', () => {
  const matrix: Record<UserScope, Array<[string, string]>> = {
    account: [
      ['Edit User', 'users.update'],
      ['Manage Roles', 'admin.user.update'],
      ['Suspend User', 'admin.user.manage'],
      ['Reset Password', 'admin.user.manage'],
      ['Delete User', 'admin.user.delete'],
    ],
    all: [
      ['Edit User', 'admin.user.update'],
      ['Manage Roles', 'admin.user.update'],
      ['Suspend User', 'admin.user.manage'],
      ['Reset Password', 'admin.user.manage'],
      ['Delete User', 'admin.user.delete'],
    ],
  };

  (Object.keys(matrix) as UserScope[]).forEach((scope) => {
    describe(`scope "${scope}"`, () => {
      it.each(matrix[scope])('shows "%s" to a holder of %s', async (title, permission) => {
        renderTable(scope, [permission]);
        expect((await row()).getByTitle(title)).toBeInTheDocument();
      });

      it.each(matrix[scope])('hides "%s" without its permission', async (title) => {
        renderTable(scope, ['team.read']);
        expect((await row()).queryByTitle(title)).not.toBeInTheDocument();
      });
    });
  });

  it('reads the account scope from /users and the all scope from /admin/users', async () => {
    renderTable('account', ['team.read']);
    await row();
    expect(mockGetUsers).toHaveBeenCalled();
    expect(mockGetAllUsers).not.toHaveBeenCalled();
  });

  it('shows an Account column only in the all scope', async () => {
    const { unmount } = renderTable('all', ['team.read']);
    await row();
    expect(screen.getByRole('columnheader', { name: 'Account' })).toBeInTheDocument();
    unmount();

    renderTable('account', ['team.read']);
    await row();
    expect(screen.queryByRole('columnheader', { name: 'Account' })).not.toBeInTheDocument();
  });

  it('all scope deletes through /admin/users, which reaches a user in any account', async () => {
    renderTable('all', ['admin.user.delete']);
    fireEvent.click((await row()).getByTitle('Delete User'));
    fireEvent.click(await screen.findByRole('button', { name: 'Delete User' }));
    await waitFor(() => expect(mockDeleteAdminUser).toHaveBeenCalledWith('u2'));
    expect(mockDeleteUser).not.toHaveBeenCalled();
  });
});

describe('UsersTable — impersonation is an extension capability', () => {
  it.each<UserScope>(['account', 'all'])('%s: no Impersonate action when nothing registered the capability', async (scope) => {
    renderTable(scope, ['system.admin']);
    expect((await row()).queryByTitle('Impersonate User')).not.toBeInTheDocument();
  });

  it.each<UserScope>(['account', 'all'])('%s: Impersonate appears once registered, for a holder of a registered permission', async (scope) => {
    featureRegistry.registerSlotMeta({ [USER_IMPERSONATION_SLOT]: { permissions: ['admin.user.impersonate'] } });
    renderTable(scope, ['admin.user.impersonate']);
    expect((await row()).getByTitle('Impersonate User')).toBeInTheDocument();
  });

  it('stays hidden for a user without a registered permission', async () => {
    featureRegistry.registerSlotMeta({ [USER_IMPERSONATION_SLOT]: { permissions: ['admin.user.impersonate'] } });
    renderTable('all', ['admin.user.update']);
    expect((await row()).queryByTitle('Impersonate User')).not.toBeInTheDocument();
  });
});

describe('UsersTable — page actions', () => {
  const actionsFor = async (scope: UserScope, permissions: string[]) => {
    const onActionsReady = jest.fn();
    const store = configureStore({
      reducer: { auth: (state = { user: { id: 'me', roles: ['owner'], permissions, account: { id: 'acct-1' } }, isAuthenticated: true }) => state },
    });
    render(
      <Provider store={store}>
        <MemoryRouter><UsersTable scope={scope} onActionsReady={onActionsReady} /></MemoryRouter>
      </Provider>
    );
    await screen.findByTestId('user-row-u2');
    const last = onActionsReady.mock.calls[onActionsReady.mock.calls.length - 1][0] as Array<{ id: string }>;
    return last.map((a) => a.id);
  };

  it.each<UserScope>(['account', 'all'])('%s: Add New User needs admin.user.create', async (scope) => {
    expect(await actionsFor(scope, ['admin.user.create'])).toContain('add-user');
  });

  it.each<UserScope>(['account', 'all'])('%s: no Add New User without it', async (scope) => {
    expect(await actionsFor(scope, ['team.read'])).not.toContain('add-user');
  });
});
