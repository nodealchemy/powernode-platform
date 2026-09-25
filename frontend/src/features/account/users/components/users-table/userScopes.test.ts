import { pageGates, rowGates, SCOPE_ENDPOINTS, UserScope } from './userScopes';
import type { User as AuthUser } from '@/shared/services/slices/authSlice';
import type { User } from '@/features/account/users/services/usersApi';

const mockGet = jest.fn();
const mockPut = jest.fn();
const mockDelete = jest.fn();
jest.mock('@/shared/services/api', () => ({
  __esModule: true,
  api: {
    get: (...args: unknown[]) => mockGet(...args),
    put: (...args: unknown[]) => mockPut(...args),
    delete: (...args: unknown[]) => mockDelete(...args),
  },
}));

// Every gate is a function of PERMISSIONS only. The fixtures give each actor a
// role name that would grant everything if roles were consulted ('owner' /
// 'system.admin'), so a gate that read roles instead of permissions fails here.
const actor = (permissions: string[]): AuthUser => ({
  id: 'me', email: 'me@example.com', name: 'Me', roles: ['owner', 'system.admin'], permissions,
  status: 'active', email_verified: true, account: { id: 'acct-1', name: 'Mine', status: 'active' },
} as unknown as AuthUser);

const row = (overrides: Partial<User> = {}): User => ({
  id: 'other', email: 'o@example.com', name: 'Other', roles: [], status: 'active', email_verified: true,
  locked: false, failed_login_attempts: 0, created_at: '2026-01-01T00:00:00Z', updated_at: '2026-01-01T00:00:00Z',
  account: { id: 'acct-1', name: 'Mine', status: 'active' },
  ...overrides,
} as unknown as User);

const IMPERSONATION = ['admin.user.impersonate', 'accounts.manage', 'admin.access'];

describe('rowGates — per scope, permissions only', () => {
  // [gate, permission that opens it] for each scope, mirroring the server's
  // before_actions: users#* (account scope) and admin/users#* (all scope).
  const matrix: Record<UserScope, Array<[keyof ReturnType<typeof rowGates>, string]>> = {
    account: [
      ['edit', 'users.update'],
      ['roles', 'admin.user.update'],
      ['manage', 'admin.user.manage'],
      ['delete', 'admin.user.delete'],
    ],
    all: [
      ['edit', 'admin.user.update'],
      ['roles', 'admin.user.update'],
      ['manage', 'admin.user.manage'],
      ['delete', 'admin.user.delete'],
    ],
  };

  (Object.keys(matrix) as UserScope[]).forEach((scope) => {
    describe(`scope "${scope}"`, () => {
      it.each(matrix[scope])('%s opens with %s', (gate, permission) => {
        expect(rowGates(scope, actor([permission]), row(), null)[gate]).toBe(true);
      });

      it.each(matrix[scope])('%s stays closed without its permission, whatever the roles say', (gate) => {
        expect(rowGates(scope, actor(['team.read']), row(), null)[gate]).toBe(false);
      });

      it('system.admin opens every gate', () => {
        const gates = rowGates(scope, actor(['system.admin']), row(), IMPERSONATION);
        expect(gates).toEqual({ edit: true, roles: true, manage: true, delete: true, impersonate: true });
      });

      it('never offers delete, manage or impersonate on your own row', () => {
        const gates = rowGates(scope, actor(['system.admin']), row({ id: 'me' }), IMPERSONATION);
        expect(gates.delete).toBe(false);
        expect(gates.manage).toBe(false);
        expect(gates.impersonate).toBe(false);
      });
    });
  });

  it('all scope: suspend/activate/unlock/reset only reach users in your own account (those endpoints are account-scoped)', () => {
    const elsewhere = row({ account: { id: 'acct-2', name: 'Theirs', status: 'active' } } as Partial<User>);
    expect(rowGates('all', actor(['admin.user.manage']), elsewhere, null).manage).toBe(false);
    expect(rowGates('all', actor(['admin.user.manage']), row(), null).manage).toBe(true);
  });

  describe('impersonate', () => {
    it('is closed when no extension registered the capability, even for system.admin', () => {
      expect(rowGates('account', actor(['system.admin']), row(), null).impersonate).toBe(false);
      expect(rowGates('all', actor(['system.admin']), row(), null).impersonate).toBe(false);
    });

    it.each(IMPERSONATION)('opens with %s when the capability is registered', (permission) => {
      expect(rowGates('all', actor([permission]), row(), IMPERSONATION).impersonate).toBe(true);
    });

    it('stays closed without one of the registered permissions', () => {
      expect(rowGates('all', actor(['admin.user.update']), row(), IMPERSONATION).impersonate).toBe(false);
    });
  });
});

describe('pageGates — per scope, permissions only', () => {
  it.each<UserScope>(['account', 'all'])('%s: Add user needs admin.user.create', (scope) => {
    expect(pageGates(scope, actor(['admin.user.create'])).create).toBe(true);
    expect(pageGates(scope, actor(['team.read'])).create).toBe(false);
  });

  it('account: Invite needs team.invite or users.create (Api::V1::InvitationsController)', () => {
    expect(pageGates('account', actor(['team.invite'])).invite).toBe(true);
    expect(pageGates('account', actor(['users.create'])).invite).toBe(true);
    expect(pageGates('account', actor(['team.read'])).invite).toBe(false);
  });

  it('all: no Invite (an invitation joins the inviter\'s account, which is the account scope\'s job)', () => {
    expect(pageGates('all', actor(['system.admin'])).invite).toBe(false);
  });

  it.each<UserScope>(['account', 'all'])('%s: bulk delete needs admin.user.delete', (scope) => {
    expect(pageGates(scope, actor(['admin.user.delete'])).bulkDelete).toBe(true);
    expect(pageGates(scope, actor(['admin.user.manage'])).bulkDelete).toBe(false);
  });

  it('bulk suspend/activate: account scope with admin.user.manage; never across accounts', () => {
    expect(pageGates('account', actor(['admin.user.manage'])).bulkStatus).toBe(true);
    expect(pageGates('account', actor(['admin.user.delete'])).bulkStatus).toBe(false);
    expect(pageGates('all', actor(['system.admin'])).bulkStatus).toBe(false);
  });
});

describe('SCOPE_ENDPOINTS — each scope reads and writes its own controller', () => {
  beforeEach(() => {
    mockGet.mockReset().mockResolvedValue({ data: { success: true, data: [] } });
    mockPut.mockReset().mockResolvedValue({ data: { success: true, data: {} } });
    mockDelete.mockReset().mockResolvedValue({ data: { success: true } });
  });

  it('account scope uses /users (current account only)', async () => {
    await SCOPE_ENDPOINTS.account.list();
    await SCOPE_ENDPOINTS.account.update('u2', { name: 'N' });
    await SCOPE_ENDPOINTS.account.remove('u2');
    expect(mockGet).toHaveBeenCalledWith('/users');
    expect(mockPut).toHaveBeenCalledWith('/users/u2', { user: { name: 'N' } });
    expect(mockDelete).toHaveBeenCalledWith('/users/u2');
  });

  it('all scope uses /admin/users, which resolves a user in any account', async () => {
    await SCOPE_ENDPOINTS.all.list();
    await SCOPE_ENDPOINTS.all.update('u2', { name: 'N' });
    await SCOPE_ENDPOINTS.all.remove('u2');
    expect(mockGet).toHaveBeenCalledWith('/admin/users');
    expect(mockPut).toHaveBeenCalledWith('/admin/users/u2', { user: { name: 'N' } });
    expect(mockDelete).toHaveBeenCalledWith('/admin/users/u2');
  });
});
