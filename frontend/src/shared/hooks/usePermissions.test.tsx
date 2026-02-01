import React from 'react';
import { render, screen } from '@testing-library/react';
import { renderHook } from '@testing-library/react';
import { Provider } from 'react-redux';
import { configureStore } from '@reduxjs/toolkit';
import { usePermissions } from './usePermissions';

// Mock user data
const createMockUser = (permissions: string[] = [], roles: string[] = []) => ({
  id: 'user-1',
  email: 'test@example.com',
  name: 'Test User',
  permissions,
  roles
});

// Create mock store with different user states
const createMockStore = (user: any = null) => {
  return configureStore({
    reducer: {
      auth: (state = { user }, action) => {
        switch (action.type) {
          case 'SET_USER':
            return { ...state, user: action.payload };
          default:
            return state;
        }
      },
      notifications: (state = { notifications: [] }) => state
    }
  });
};

describe('usePermissions', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('with no user', () => {
    it('returns false for all permission checks when no user', () => {
      const store = createMockStore(null);
      const { result } = renderHook(() => usePermissions(), {
        wrapper: ({ children }) => <Provider store={store}>{children}</Provider>
      });

      expect(result.current.hasPermission('users.read')).toBe(false);
      expect(result.current.hasAnyPermission(['users.read', 'users.write'])).toBe(false);
      expect(result.current.hasAllPermissions(['users.read', 'users.write'])).toBe(false);
      expect(result.current.canAccess('users', 'read')).toBe(false);
      expect(result.current.isSystemAdmin()).toBe(false);
      expect(result.current.isAccountManager()).toBe(false);
      expect(result.current.isAdmin()).toBe(false);
    });

    it('returns empty arrays for permissions and roles when no user', () => {
      const store = createMockStore(null);
      const { result } = renderHook(() => usePermissions(), {
        wrapper: ({ children }) => <Provider store={store}>{children}</Provider>
      });

      expect(result.current.permissions).toEqual([]);
      expect(result.current.getAllPermissions()).toEqual([]);
      expect(result.current.roles).toEqual([]);
      expect(result.current.getAllRoles()).toEqual([]);
    });
  });

  describe('with user but no permissions', () => {
    it('returns false for all permission checks when user has no permissions', () => {
      const user = createMockUser([], ['basic.user']);
      const store = createMockStore(user);
      const { result } = renderHook(() => usePermissions(), {
        wrapper: ({ children }) => <Provider store={store}>{children}</Provider>
      });

      expect(result.current.hasPermission('users.read')).toBe(false);
      expect(result.current.hasAnyPermission(['users.read', 'users.write'])).toBe(false);
      expect(result.current.hasAllPermissions(['users.read'])).toBe(false);
      expect(result.current.canAccess('users', 'read')).toBe(false);
    });
  });

  describe('exact permission matching', () => {
    it('grants access for exact permission matches', () => {
      const permissions = ['users.read', 'users.create', 'billing.read'];
      const user = createMockUser(permissions);
      const store = createMockStore(user);
      const { result } = renderHook(() => usePermissions(), {
        wrapper: ({ children }) => <Provider store={store}>{children}</Provider>
      });

      expect(result.current.hasPermission('users.read')).toBe(true);
      expect(result.current.hasPermission('users.create')).toBe(true);
      expect(result.current.hasPermission('billing.read')).toBe(true);
      expect(result.current.hasPermission('users.delete')).toBe(false);
      expect(result.current.hasPermission('admin.access')).toBe(false);
    });

    it('uses canAccess method correctly', () => {
      const permissions = ['users.read', 'users.create', 'billing.read'];
      const user = createMockUser(permissions);
      const store = createMockStore(user);
      const { result } = renderHook(() => usePermissions(), {
        wrapper: ({ children }) => <Provider store={store}>{children}</Provider>
      });

      expect(result.current.canAccess('users', 'read')).toBe(true);
      expect(result.current.canAccess('users', 'create')).toBe(true);
      expect(result.current.canAccess('billing', 'read')).toBe(true);
      expect(result.current.canAccess('users', 'delete')).toBe(false);
      expect(result.current.canAccess('admin', 'access')).toBe(false);
    });
  });

  describe('wildcard permission matching', () => {
    it('grants access for resource wildcards', () => {
      const permissions = ['users.*', 'billing.read'];
      const user = createMockUser(permissions);
      const store = createMockStore(user);
      const { result } = renderHook(() => usePermissions(), {
        wrapper: ({ children }) => <Provider store={store}>{children}</Provider>
      });

      expect(result.current.hasPermission('users.read')).toBe(true);
      expect(result.current.hasPermission('users.create')).toBe(true);
      expect(result.current.hasPermission('users.update')).toBe(true);
      expect(result.current.hasPermission('users.delete')).toBe(true);
      expect(result.current.hasPermission('users.anything')).toBe(true);
      
      expect(result.current.hasPermission('billing.read')).toBe(true);
      expect(result.current.hasPermission('billing.create')).toBe(false);
      
      expect(result.current.hasPermission('admin.access')).toBe(false);
    });

    it('grants access for system wildcards', () => {
      const permissions = ['*.*'];
      const user = createMockUser(permissions);
      const store = createMockStore(user);
      const { result } = renderHook(() => usePermissions(), {
        wrapper: ({ children }) => <Provider store={store}>{children}</Provider>
      });

      expect(result.current.hasPermission('users.read')).toBe(true);
      expect(result.current.hasPermission('users.create')).toBe(true);
      expect(result.current.hasPermission('billing.read')).toBe(true);
      expect(result.current.hasPermission('admin.access')).toBe(true);
      expect(result.current.hasPermission('anything.anything')).toBe(true);
    });

    it('grants access for system.* wildcard', () => {
      const permissions = ['system.*'];
      const user = createMockUser(permissions);
      const store = createMockStore(user);
      const { result } = renderHook(() => usePermissions(), {
        wrapper: ({ children }) => <Provider store={store}>{children}</Provider>
      });

      expect(result.current.hasPermission('users.read')).toBe(true);
      expect(result.current.hasPermission('billing.create')).toBe(true);
      expect(result.current.hasPermission('admin.access')).toBe(true);
      expect(result.current.hasPermission('anything.anything')).toBe(true);
    });
  });

  describe('multiple permission checks', () => {
    it('checks hasAnyPermission correctly', () => {
      const permissions = ['users.read', 'billing.read'];
      const user = createMockUser(permissions);
      const store = createMockStore(user);
      const { result } = renderHook(() => usePermissions(), {
        wrapper: ({ children }) => <Provider store={store}>{children}</Provider>
      });

      expect(result.current.hasAnyPermission(['users.read', 'users.write'])).toBe(true);
      expect(result.current.hasAnyPermission(['users.write', 'users.delete'])).toBe(false);
      expect(result.current.hasAnyPermission(['users.read', 'billing.read'])).toBe(true);
      expect(result.current.hasAnyPermission(['admin.access', 'system.admin'])).toBe(false);
      expect(result.current.hasAnyPermission([])).toBe(false);
    });

    it('checks hasAllPermissions correctly', () => {
      const permissions = ['users.read', 'users.create', 'billing.read'];
      const user = createMockUser(permissions);
      const store = createMockStore(user);
      const { result } = renderHook(() => usePermissions(), {
        wrapper: ({ children }) => <Provider store={store}>{children}</Provider>
      });

      expect(result.current.hasAllPermissions(['users.read', 'users.create'])).toBe(true);
      expect(result.current.hasAllPermissions(['users.read', 'users.delete'])).toBe(false);
      expect(result.current.hasAllPermissions(['users.read', 'billing.read'])).toBe(true);
      expect(result.current.hasAllPermissions(['users.read', 'users.create', 'billing.read'])).toBe(true);
      expect(result.current.hasAllPermissions(['users.read', 'admin.access'])).toBe(false);
      expect(result.current.hasAllPermissions([])).toBe(true);
    });
  });

  describe('convenience methods', () => {
    it('identifies system admin correctly', () => {
      const systemAdminUser = createMockUser(['system.admin']);
      const regularUser = createMockUser(['users.read']);
      
      let store = createMockStore(systemAdminUser);
      let { result } = renderHook(() => usePermissions(), {
        wrapper: ({ children }) => <Provider store={store}>{children}</Provider>
      });
      expect(result.current.isSystemAdmin()).toBe(true);

      store = createMockStore(regularUser);
      ({ result } = renderHook(() => usePermissions(), {
        wrapper: ({ children }) => <Provider store={store}>{children}</Provider>
      }));
      expect(result.current.isSystemAdmin()).toBe(false);
    });

    it('identifies account manager correctly', () => {
      const accountManagerUser = createMockUser(['team.assign_roles']);
      const partialUser = createMockUser(['admin.user.update']);
      const regularUser = createMockUser(['users.read']);
      
      let store = createMockStore(accountManagerUser);
      let { result } = renderHook(() => usePermissions(), {
        wrapper: ({ children }) => <Provider store={store}>{children}</Provider>
      });
      expect(result.current.isAccountManager()).toBe(true);

      store = createMockStore(partialUser);
      ({ result } = renderHook(() => usePermissions(), {
        wrapper: ({ children }) => <Provider store={store}>{children}</Provider>
      }));
      expect(result.current.isAccountManager()).toBe(true);

      store = createMockStore(regularUser);
      ({ result } = renderHook(() => usePermissions(), {
        wrapper: ({ children }) => <Provider store={store}>{children}</Provider>
      }));
      expect(result.current.isAccountManager()).toBe(false);
    });

    it('identifies admin correctly', () => {
      const adminUser = createMockUser(['admin.access']);
      const regularUser = createMockUser(['users.read']);
      
      let store = createMockStore(adminUser);
      let { result } = renderHook(() => usePermissions(), {
        wrapper: ({ children }) => <Provider store={store}>{children}</Provider>
      });
      expect(result.current.isAdmin()).toBe(true);

      store = createMockStore(regularUser);
      ({ result } = renderHook(() => usePermissions(), {
        wrapper: ({ children }) => <Provider store={store}>{children}</Provider>
      }));
      expect(result.current.isAdmin()).toBe(false);
    });
  });

  describe('data accessors', () => {
    it('returns correct permissions and roles', () => {
      const permissions = ['users.read', 'users.create', 'billing.read'];
      const roles = ['account.manager', 'billing.manager'];
      const user = createMockUser(permissions, roles);
      const store = createMockStore(user);
      const { result } = renderHook(() => usePermissions(), {
        wrapper: ({ children }) => <Provider store={store}>{children}</Provider>
      });

      expect(result.current.permissions).toEqual(permissions);
      expect(result.current.getAllPermissions()).toEqual(permissions);
      expect(result.current.roles).toEqual(roles);
      expect(result.current.getAllRoles()).toEqual(roles);
    });

    it('handles undefined permissions and roles gracefully', () => {
      const user = { ...createMockUser(), permissions: undefined, roles: undefined };
      const store = createMockStore(user);
      const { result } = renderHook(() => usePermissions(), {
        wrapper: ({ children }) => <Provider store={store}>{children}</Provider>
      });

      expect(result.current.permissions).toEqual([]);
      expect(result.current.getAllPermissions()).toEqual([]);
      expect(result.current.roles).toEqual([]);
      expect(result.current.getAllRoles()).toEqual([]);
    });
  });

  describe('edge cases', () => {
    it('handles malformed permission strings gracefully', () => {
      const permissions = ['users.read', 'malformed', 'billing.', '.create', ''];
      const user = createMockUser(permissions);
      const store = createMockStore(user);
      const { result } = renderHook(() => usePermissions(), {
        wrapper: ({ children }) => <Provider store={store}>{children}</Provider>
      });

      expect(result.current.hasPermission('users.read')).toBe(true);
      expect(result.current.hasPermission('malformed')).toBe(true);
      expect(result.current.hasPermission('billing.')).toBe(true);
      expect(result.current.hasPermission('.create')).toBe(true);
      expect(result.current.hasPermission('')).toBe(true);
    });

    it('handles empty permission checks', () => {
      const permissions = ['users.read'];
      const user = createMockUser(permissions);
      const store = createMockStore(user);
      const { result } = renderHook(() => usePermissions(), {
        wrapper: ({ children }) => <Provider store={store}>{children}</Provider>
      });

      expect(result.current.hasPermission('')).toBe(false);
      expect(result.current.canAccess('', '')).toBe(false);
      expect(result.current.canAccess('users', '')).toBe(false);
      expect(result.current.canAccess('', 'read')).toBe(false);
    });

    it('handles case sensitivity correctly', () => {
      const permissions = ['users.read', 'Users.CREATE', 'BILLING.read'];
      const user = createMockUser(permissions);
      const store = createMockStore(user);
      const { result } = renderHook(() => usePermissions(), {
        wrapper: ({ children }) => <Provider store={store}>{children}</Provider>
      });

      expect(result.current.hasPermission('users.read')).toBe(true);
      expect(result.current.hasPermission('Users.read')).toBe(false);
      expect(result.current.hasPermission('Users.CREATE')).toBe(true);
      expect(result.current.hasPermission('users.CREATE')).toBe(false);
      expect(result.current.hasPermission('BILLING.read')).toBe(true);
      expect(result.current.hasPermission('billing.read')).toBe(false);
    });
  });

  describe('complex scenarios', () => {
    it('handles mixed exact and wildcard permissions correctly', () => {
      const permissions = ['users.*', 'billing.read', 'admin.access', 'reports.*'];
      const user = createMockUser(permissions);
      const store = createMockStore(user);
      const { result } = renderHook(() => usePermissions(), {
        wrapper: ({ children }) => <Provider store={store}>{children}</Provider>
      });

      // Wildcard permissions
      expect(result.current.hasPermission('users.read')).toBe(true);
      expect(result.current.hasPermission('users.create')).toBe(true);
      expect(result.current.hasPermission('users.update')).toBe(true);
      expect(result.current.hasPermission('users.delete')).toBe(true);
      expect(result.current.hasPermission('reports.generate')).toBe(true);
      expect(result.current.hasPermission('reports.export')).toBe(true);

      // Exact permissions
      expect(result.current.hasPermission('billing.read')).toBe(true);
      expect(result.current.hasPermission('admin.access')).toBe(true);

      // Not granted permissions
      expect(result.current.hasPermission('billing.create')).toBe(false);
      expect(result.current.hasPermission('billing.update')).toBe(false);
      expect(result.current.hasPermission('system.admin')).toBe(false);
    });

    it('handles system admin with mixed permissions correctly', () => {
      const permissions = ['system.*', 'users.read']; // system.* should override users.read
      const user = createMockUser(permissions);
      const store = createMockStore(user);
      const { result } = renderHook(() => usePermissions(), {
        wrapper: ({ children }) => <Provider store={store}>{children}</Provider>
      });

      expect(result.current.hasPermission('users.read')).toBe(true);
      expect(result.current.hasPermission('users.create')).toBe(true);
      expect(result.current.hasPermission('billing.read')).toBe(true);
      expect(result.current.hasPermission('admin.access')).toBe(true);
      expect(result.current.isSystemAdmin()).toBe(true);
    });
  });

  describe('component integration', () => {
    interface ProtectedComponentProps {
      permissions: string[];
      roles?: string[];
    }

    const ProtectedComponent: React.FC<ProtectedComponentProps> = ({ permissions: _permissions, roles: _roles = [] }) => {
      const {
        hasPermission,
        hasAnyPermission,
        hasAllPermissions,
        isSystemAdmin,
        isAccountManager,
        isAdmin
      } = usePermissions();

      return (
        <div>
          <div data-testid="user-read">
            {hasPermission('users.read') ? 'Can read users' : 'Cannot read users'}
          </div>
          <div data-testid="user-create">
            {hasPermission('users.create') ? 'Can create users' : 'Cannot create users'}
          </div>
          <div data-testid="any-user-permission">
            {hasAnyPermission(['users.read', 'users.create']) ? 'Has user permissions' : 'No user permissions'}
          </div>
          <div data-testid="all-admin-permissions">
            {hasAllPermissions(['admin.access', 'system.admin']) ? 'Full admin' : 'Not full admin'}
          </div>
          <div data-testid="is-system-admin">
            {isSystemAdmin() ? 'System Admin' : 'Not System Admin'}
          </div>
          <div data-testid="is-account-manager">
            {isAccountManager() ? 'Account Manager' : 'Not Account Manager'}
          </div>
          <div data-testid="is-admin">
            {isAdmin() ? 'Admin' : 'Not Admin'}
          </div>
        </div>
      );
    };

    it('integrates correctly with components for regular user', () => {
      const user = createMockUser(['users.read', 'billing.read'], ['basic.user']);
      const store = createMockStore(user);
      
      render(
        <Provider store={store}>
          <ProtectedComponent permissions={user.permissions} roles={user.roles} />
        </Provider>
      );

      expect(screen.getByTestId('user-read')).toHaveTextContent('Can read users');
      expect(screen.getByTestId('user-create')).toHaveTextContent('Cannot create users');
      expect(screen.getByTestId('any-user-permission')).toHaveTextContent('Has user permissions');
      expect(screen.getByTestId('all-admin-permissions')).toHaveTextContent('Not full admin');
      expect(screen.getByTestId('is-system-admin')).toHaveTextContent('Not System Admin');
      expect(screen.getByTestId('is-account-manager')).toHaveTextContent('Not Account Manager');
      expect(screen.getByTestId('is-admin')).toHaveTextContent('Not Admin');
    });

    it('integrates correctly with components for admin user', () => {
      const user = createMockUser(['admin.access', 'system.admin', 'users.*'], ['system.admin']);
      const store = createMockStore(user);
      
      render(
        <Provider store={store}>
          <ProtectedComponent permissions={user.permissions} roles={user.roles} />
        </Provider>
      );

      expect(screen.getByTestId('user-read')).toHaveTextContent('Can read users');
      expect(screen.getByTestId('user-create')).toHaveTextContent('Can create users');
      expect(screen.getByTestId('any-user-permission')).toHaveTextContent('Has user permissions');
      expect(screen.getByTestId('all-admin-permissions')).toHaveTextContent('Full admin');
      expect(screen.getByTestId('is-system-admin')).toHaveTextContent('System Admin');
      expect(screen.getByTestId('is-account-manager')).toHaveTextContent('Not Account Manager');
      expect(screen.getByTestId('is-admin')).toHaveTextContent('Admin');
    });

    it('integrates correctly with components for account manager', () => {
      const user = createMockUser(['users.manage', 'team.manage', 'billing.read'], ['account.manager']);
      const store = createMockStore(user);
      
      render(
        <Provider store={store}>
          <ProtectedComponent permissions={user.permissions} roles={user.roles} />
        </Provider>
      );

      expect(screen.getByTestId('user-read')).toHaveTextContent('Cannot read users');
      expect(screen.getByTestId('user-create')).toHaveTextContent('Cannot create users');
      expect(screen.getByTestId('any-user-permission')).toHaveTextContent('No user permissions');
      expect(screen.getByTestId('all-admin-permissions')).toHaveTextContent('Not full admin');
      expect(screen.getByTestId('is-system-admin')).toHaveTextContent('Not System Admin');
      expect(screen.getByTestId('is-account-manager')).toHaveTextContent('Account Manager');
      expect(screen.getByTestId('is-admin')).toHaveTextContent('Not Admin');
    });
  });
});