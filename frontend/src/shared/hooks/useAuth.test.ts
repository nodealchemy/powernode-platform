import { renderHook } from '@testing-library/react';
import { Provider } from 'react-redux';
import { configureStore, combineReducers } from '@reduxjs/toolkit';
import type { ReactNode } from 'react';
import { createElement } from 'react';
import { useAuth } from './useAuth';
import authReducer from '../services/slices/authSlice';
import uiReducer from '../services/slices/uiSlice';

const rootReducer = combineReducers({
  auth: authReducer,
  ui: uiReducer,
});

// Helper to create a test store with specific state
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const createTestStore = (preloadedState?: any) => {
  return configureStore({
    reducer: rootReducer,
    preloadedState,
  });
};

// Wrapper component for renderHook
const createWrapper = (store: ReturnType<typeof createTestStore>) => {
  return function Wrapper({ children }: { children: ReactNode }) {
    return createElement(Provider, { store, children });
  };
};

describe('useAuth', () => {
  describe('when user is not authenticated', () => {
    it('returns null for currentUser', () => {
      const store = createTestStore({
        auth: {
          user: null,
          isLoading: false,
          isAuthenticated: false,
          error: null,
        },
      });

      const { result } = renderHook(() => useAuth(), {
        wrapper: createWrapper(store),
      });

      expect(result.current.currentUser).toBeNull();
    });

    it('returns false for isAuthenticated', () => {
      const store = createTestStore({
        auth: {
          user: null,
          isLoading: false,
          isAuthenticated: false,
          error: null,
        },
      });

      const { result } = renderHook(() => useAuth(), {
        wrapper: createWrapper(store),
      });

      expect(result.current.isAuthenticated).toBe(false);
    });

    it('returns empty array for permissions', () => {
      const store = createTestStore({
        auth: {
          user: null,
          isLoading: false,
          isAuthenticated: false,
          error: null,
        },
      });

      const { result } = renderHook(() => useAuth(), {
        wrapper: createWrapper(store),
      });

      expect(result.current.permissions).toEqual([]);
    });
  });

  describe('when user is authenticated', () => {
    const mockUser = {
      id: '123',
      email: 'test@example.com',
      name: 'Test User',
      permissions: ['users.read', 'users.create', 'billing.read'],
      roles: ['account.member'],
      status: 'active',
      email_verified: true,
      account: {
        id: '456',
        name: 'Test Company',
        status: 'active',
      },
    };

    it('returns the current user', () => {
      const store = createTestStore({
        auth: {
          user: mockUser,
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      const { result } = renderHook(() => useAuth(), {
        wrapper: createWrapper(store),
      });

      expect(result.current.currentUser).toEqual(mockUser);
    });

    it('returns true for isAuthenticated', () => {
      const store = createTestStore({
        auth: {
          user: mockUser,
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      const { result } = renderHook(() => useAuth(), {
        wrapper: createWrapper(store),
      });

      expect(result.current.isAuthenticated).toBe(true);
    });

    it('returns user permissions', () => {
      const store = createTestStore({
        auth: {
          user: mockUser,
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      const { result } = renderHook(() => useAuth(), {
        wrapper: createWrapper(store),
      });

      expect(result.current.permissions).toEqual(['users.read', 'users.create', 'billing.read']);
    });

    it('returns empty array when user has no permissions', () => {
      const userWithoutPermissions = {
        ...mockUser,
        permissions: undefined,
      };

      const store = createTestStore({
        auth: {
          user: userWithoutPermissions,
          isLoading: false,
          isAuthenticated: true,
          error: null,
        },
      });

      const { result } = renderHook(() => useAuth(), {
        wrapper: createWrapper(store),
      });

      expect(result.current.permissions).toEqual([]);
    });
  });

  describe('loading state', () => {
    it('returns true for isLoading when auth is loading', () => {
      const store = createTestStore({
        auth: {
          user: null,
          isLoading: true,
          isAuthenticated: false,
          error: null,
        },
      });

      const { result } = renderHook(() => useAuth(), {
        wrapper: createWrapper(store),
      });

      expect(result.current.isLoading).toBe(true);
    });

    it('returns false for isLoading when auth is not loading', () => {
      const store = createTestStore({
        auth: {
          user: null,
          isLoading: false,
          isAuthenticated: false,
          error: null,
        },
      });

      const { result } = renderHook(() => useAuth(), {
        wrapper: createWrapper(store),
      });

      expect(result.current.isLoading).toBe(false);
    });
  });

  describe('return type', () => {
    it('returns all expected properties', () => {
      const store = createTestStore({
        auth: {
          user: null,
          isLoading: false,
          isAuthenticated: false,
          error: null,
        },
      });

      const { result } = renderHook(() => useAuth(), {
        wrapper: createWrapper(store),
      });

      expect(result.current).toHaveProperty('currentUser');
      expect(result.current).toHaveProperty('isAuthenticated');
      expect(result.current).toHaveProperty('isLoading');
      expect(result.current).toHaveProperty('permissions');
    });
  });
});
