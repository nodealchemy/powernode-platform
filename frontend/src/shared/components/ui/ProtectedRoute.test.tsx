import React from 'react';
import { render, screen } from '@testing-library/react';
import { Provider } from 'react-redux';
import { MemoryRouter } from 'react-router-dom';
import { configureStore } from '@reduxjs/toolkit';
import { ProtectedRoute } from './ProtectedRoute';

// Mock LoadingSpinner
jest.mock('./LoadingSpinner', () => ({
  LoadingSpinner: ({ size }: { size: string }) => (
    <div data-testid="loading-spinner" data-size={size}>Loading...</div>
  )
}));

describe('ProtectedRoute', () => {
  const createStore = (authState: {
    isAuthenticated?: boolean;
    isLoading?: boolean;
    user?: {
      id?: string;
      email?: string;
      email_verified?: boolean;
      permissions?: string[];
    } | null;
  }) => configureStore({
    reducer: {
      auth: () => ({
        isAuthenticated: authState.isAuthenticated ?? false,
        isLoading: authState.isLoading ?? false,
        user: authState.user ?? null
      })
    }
  });

  const renderWithProviders = (
    ui: React.ReactElement,
    authState: Parameters<typeof createStore>[0],
    initialRoute = '/dashboard'
  ) => {
    return render(
      <Provider store={createStore(authState)}>
        <MemoryRouter initialEntries={[initialRoute]} future={{ v7_startTransition: true, v7_relativeSplatPath: true }}>
          {ui}
        </MemoryRouter>
      </Provider>
    );
  };

  describe('loading state', () => {
    it('shows loading spinner while auth is loading', () => {
      renderWithProviders(
        <ProtectedRoute><div>Protected Content</div></ProtectedRoute>,
        { isLoading: true }
      );

      expect(screen.getByTestId('loading-spinner')).toBeInTheDocument();
      expect(screen.queryByText('Protected Content')).not.toBeInTheDocument();
    });

    it('shows loading spinner when authenticated but user not loaded', () => {
      renderWithProviders(
        <ProtectedRoute><div>Protected Content</div></ProtectedRoute>,
        { isAuthenticated: true, user: null }
      );

      expect(screen.getByTestId('loading-spinner')).toBeInTheDocument();
    });

    it('uses large spinner size', () => {
      renderWithProviders(
        <ProtectedRoute><div>Protected Content</div></ProtectedRoute>,
        { isLoading: true }
      );

      expect(screen.getByTestId('loading-spinner')).toHaveAttribute('data-size', 'lg');
    });
  });

  describe('authentication', () => {
    it('renders children when authenticated', () => {
      renderWithProviders(
        <ProtectedRoute><div>Protected Content</div></ProtectedRoute>,
        {
          isAuthenticated: true,
          user: { id: '1', email: 'test@test.com', email_verified: true, permissions: [] }
        }
      );

      expect(screen.getByText('Protected Content')).toBeInTheDocument();
    });

    it('redirects to login when not authenticated', () => {
      renderWithProviders(
        <ProtectedRoute><div>Protected Content</div></ProtectedRoute>,
        { isAuthenticated: false, user: null }
      );

      // Component renders Navigate, which changes the route
      expect(screen.queryByText('Protected Content')).not.toBeInTheDocument();
    });
  });

  describe('email verification', () => {
    it('allows access when email is verified', () => {
      renderWithProviders(
        <ProtectedRoute requireEmailVerification>
          <div>Verified Content</div>
        </ProtectedRoute>,
        {
          isAuthenticated: true,
          user: { id: '1', email_verified: true, permissions: [] }
        }
      );

      expect(screen.getByText('Verified Content')).toBeInTheDocument();
    });

    it('redirects when email verification required but not verified', () => {
      renderWithProviders(
        <ProtectedRoute requireEmailVerification>
          <div>Verified Content</div>
        </ProtectedRoute>,
        {
          isAuthenticated: true,
          user: { id: '1', email_verified: false, permissions: [] }
        }
      );

      expect(screen.queryByText('Verified Content')).not.toBeInTheDocument();
    });

    it('does not require email verification by default', () => {
      renderWithProviders(
        <ProtectedRoute>
          <div>Content</div>
        </ProtectedRoute>,
        {
          isAuthenticated: true,
          user: { id: '1', email_verified: false, permissions: [] }
        }
      );

      expect(screen.getByText('Content')).toBeInTheDocument();
    });
  });

  describe('permission-based access', () => {
    it('allows access when user has required permission', () => {
      renderWithProviders(
        <ProtectedRoute requiredPermissions={['users.read']}>
          <div>Admin Content</div>
        </ProtectedRoute>,
        {
          isAuthenticated: true,
          user: { id: '1', email_verified: true, permissions: ['users.read', 'billing.read'] }
        }
      );

      expect(screen.getByText('Admin Content')).toBeInTheDocument();
    });

    it('allows access when user has one of multiple required permissions', () => {
      renderWithProviders(
        <ProtectedRoute requiredPermissions={['admin.access', 'users.manage']}>
          <div>Admin Content</div>
        </ProtectedRoute>,
        {
          isAuthenticated: true,
          user: { id: '1', email_verified: true, permissions: ['users.manage'] }
        }
      );

      expect(screen.getByText('Admin Content')).toBeInTheDocument();
    });

    it('redirects when user lacks required permissions', () => {
      renderWithProviders(
        <ProtectedRoute requiredPermissions={['admin.access']}>
          <div>Admin Content</div>
        </ProtectedRoute>,
        {
          isAuthenticated: true,
          user: { id: '1', email_verified: true, permissions: ['users.read'] }
        }
      );

      expect(screen.queryByText('Admin Content')).not.toBeInTheDocument();
    });

    it('redirects when user has no permissions', () => {
      renderWithProviders(
        <ProtectedRoute requiredPermissions={['admin.access']}>
          <div>Admin Content</div>
        </ProtectedRoute>,
        {
          isAuthenticated: true,
          user: { id: '1', email_verified: true, permissions: [] }
        }
      );

      expect(screen.queryByText('Admin Content')).not.toBeInTheDocument();
    });
  });

  describe('admin access', () => {
    it('allows access with admin.access permission', () => {
      renderWithProviders(
        <ProtectedRoute requireAdminAccess>
          <div>Admin Panel</div>
        </ProtectedRoute>,
        {
          isAuthenticated: true,
          user: { id: '1', email_verified: true, permissions: ['admin.access'] }
        }
      );

      expect(screen.getByText('Admin Panel')).toBeInTheDocument();
    });

    it('allows access with system.admin permission', () => {
      renderWithProviders(
        <ProtectedRoute requireAdminAccess>
          <div>Admin Panel</div>
        </ProtectedRoute>,
        {
          isAuthenticated: true,
          user: { id: '1', email_verified: true, permissions: ['system.admin'] }
        }
      );

      expect(screen.getByText('Admin Panel')).toBeInTheDocument();
    });

    it('redirects when lacking admin permissions', () => {
      renderWithProviders(
        <ProtectedRoute requireAdminAccess>
          <div>Admin Panel</div>
        </ProtectedRoute>,
        {
          isAuthenticated: true,
          user: { id: '1', email_verified: true, permissions: ['users.read'] }
        }
      );

      expect(screen.queryByText('Admin Panel')).not.toBeInTheDocument();
    });
  });

  describe('combined requirements', () => {
    it('allows access when all requirements met', () => {
      renderWithProviders(
        <ProtectedRoute
          requireEmailVerification
          requiredPermissions={['billing.read']}
        >
          <div>Full Access Content</div>
        </ProtectedRoute>,
        {
          isAuthenticated: true,
          user: {
            id: '1',
            email_verified: true,
            permissions: ['billing.read', 'users.read']
          }
        }
      );

      expect(screen.getByText('Full Access Content')).toBeInTheDocument();
    });

    it('redirects when email not verified even with permissions', () => {
      renderWithProviders(
        <ProtectedRoute
          requireEmailVerification
          requiredPermissions={['billing.read']}
        >
          <div>Full Access Content</div>
        </ProtectedRoute>,
        {
          isAuthenticated: true,
          user: {
            id: '1',
            email_verified: false,
            permissions: ['billing.read']
          }
        }
      );

      expect(screen.queryByText('Full Access Content')).not.toBeInTheDocument();
    });
  });

  describe('default behavior', () => {
    it('renders children with no extra requirements', () => {
      renderWithProviders(
        <ProtectedRoute>
          <div>Basic Protected</div>
        </ProtectedRoute>,
        {
          isAuthenticated: true,
          user: { id: '1', permissions: [] }
        }
      );

      expect(screen.getByText('Basic Protected')).toBeInTheDocument();
    });
  });
});
