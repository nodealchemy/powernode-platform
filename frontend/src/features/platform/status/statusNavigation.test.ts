import { defaultNavigationConfig } from '@/shared/utils/navigation';
import { hasAccess } from '@/shared/utils/permissionUtils';
import type { User } from '@/shared/services/slices/authSlice';

// The Status page's DOOR, tested where the door actually is.
//
// Two independent gates guard `/app/status`, and this asserts the one that is
// data rather than JSX: the nav entry's `permissions`. The route's gate is the
// `<ProtectedRoute requiredPermissions={['platform.status.read']}>` wrapper in
// DashboardPage.tsx, which shares this exact permission string — a mismatch
// between the two would show a nav item that leads to a refusal, or hide a page
// a member is entitled to reach.
//
// PERMISSIONS, NEVER ROLES. `hasAccess` reads `user.permissions` only; a user
// with every role and no `platform.status.read` must not see this item, and the
// negative arm below is what proves the entry is not simply always-visible.

const userWith = (permissions: string[]): User =>
  ({
    id: 'u-1',
    email: 'operator@example.com',
    permissions,
    roles: ['admin', 'owner'],
  }) as unknown as User;

describe('the Status navigation entry', () => {
  const item = defaultNavigationConfig.items.find((entry) => entry.id === 'platform-status');

  it('exists as a top-level item pointing at /app/status', () => {
    // Top-level rather than inside a section: the status plane spans core AND
    // fleet, so filing it under AI or DevOps would claim it belongs to one.
    expect(item).toBeDefined();
    expect(item?.href).toBe('/app/status');
    expect(item?.name).toBe('Status');
  });

  it('requires platform.status.read and nothing else', () => {
    expect(item?.permissions).toEqual(['platform.status.read']);
  });

  it('is visible to a member holding the permission and hidden without it', () => {
    // Both arms. A design decision rides on the first one: the permission is
    // granted to admin, owner, manager AND member, because a status page only
    // admins can open does not replace five pages a member could reach.
    expect(hasAccess(userWith(['platform.status.read']), item?.permissions)).toBe(true);
    expect(hasAccess(userWith(['ai.agents.read']), item?.permissions)).toBe(false);
  });

  it('is hidden from a user with roles but no permissions', () => {
    // The roles on this fixture are admin and owner. If this ever returns true,
    // something has started reading roles for access control.
    expect(hasAccess(userWith([]), item?.permissions)).toBe(false);
  });
});
