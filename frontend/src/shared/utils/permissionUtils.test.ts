import {
  hasPermissions,
  hasAccess,
  hasAdminAccess,
  isAccountManager,
} from './permissionUtils';
import type { User } from '@/shared/services/slices/authSlice';

const userWith = (permissions: string[]): User => ({ permissions } as unknown as User);

describe('hasPermissions', () => {
  it('denies a null user', () => {
    expect(hasPermissions(null, ['users.read'])).toBe(false);
  });

  it('allows when no permissions are required', () => {
    expect(hasPermissions(userWith([]), undefined)).toBe(true);
    expect(hasPermissions(userWith([]), [])).toBe(true);
  });

  it('grants everything to system.admin', () => {
    expect(hasPermissions(userWith(['system.admin']), ['anything.at_all'])).toBe(true);
    expect(hasPermissions(userWith(['system.admin']), ['a.b.c'])).toBe(true);
  });

  it('matches a direct permission', () => {
    expect(hasPermissions(userWith(['users.read']), ['users.read'])).toBe(true);
    expect(hasPermissions(userWith(['users.read']), ['users.create'])).toBe(false);
  });

  it('matches a resource wildcard (resource.* satisfies resource.action)', () => {
    expect(hasPermissions(userWith(['users.*']), ['users.create'])).toBe(true);
    // Wildcard only applies to 2-part permissions
    expect(hasPermissions(userWith(['users.*']), ['users.read.extra'])).toBe(false);
  });

  it("applies the global '*' only to 2-part permissions", () => {
    expect(hasPermissions(userWith(['*']), ['users.create'])).toBe(true);
    expect(hasPermissions(userWith(['*']), ['system.settings.write'])).toBe(false);
  });

  it('uses OR semantics across required permissions', () => {
    expect(hasPermissions(userWith(['users.read']), ['users.create', 'users.read'])).toBe(true);
    expect(hasPermissions(userWith(['users.read']), ['users.create', 'users.delete'])).toBe(false);
  });
});

describe('hasAccess', () => {
  it('denies a null user', () => {
    expect(hasAccess(null, ['users.read'])).toBe(false);
    expect(hasAccess(null)).toBe(false);
  });

  it('allows a present user when no requirements are given', () => {
    expect(hasAccess(userWith([]))).toBe(true);
    expect(hasAccess(userWith([]), [])).toBe(true);
  });

  it('delegates to hasPermissions when requirements are given', () => {
    expect(hasAccess(userWith(['users.read']), ['users.read'])).toBe(true);
    expect(hasAccess(userWith(['users.read']), ['users.delete'])).toBe(false);
  });
});

describe('hasAdminAccess', () => {
  it('requires admin.access (directly, via wildcard, or via system.admin)', () => {
    expect(hasAdminAccess(userWith(['admin.access']))).toBe(true);
    expect(hasAdminAccess(userWith(['admin.*']))).toBe(true);
    expect(hasAdminAccess(userWith(['system.admin']))).toBe(true);
    expect(hasAdminAccess(userWith(['users.read']))).toBe(false);
    expect(hasAdminAccess(null)).toBe(false);
  });
});

describe('isAccountManager', () => {
  it('is true with team.assign_roles or admin.user.update', () => {
    expect(isAccountManager(userWith(['team.assign_roles']))).toBe(true);
    expect(isAccountManager(userWith(['admin.user.update']))).toBe(true);
  });

  it('is true for system.admin and false otherwise / for null', () => {
    expect(isAccountManager(userWith(['system.admin']))).toBe(true);
    expect(isAccountManager(userWith(['users.read']))).toBe(false);
    expect(isAccountManager(null)).toBe(false);
  });
});
