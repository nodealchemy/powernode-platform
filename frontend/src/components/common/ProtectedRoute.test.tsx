import React from 'react';
import { screen } from '@testing-library/react';
import { renderWithProviders, mockAuthenticatedState, mockUnauthenticatedState } from '../../utils/test-utils';
import { ProtectedRoute } from './ProtectedRoute';

// Mock react-router-dom Navigate component to prevent infinite loops
const mockNavigate = jest.fn();
jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  Navigate: ({ to }: { to: string }) => {
    mockNavigate(to);
    return <div data-testid="navigate" data-to={to}>Redirecting to {to}</div>;
  },
  useLocation: () => ({ pathname: '/dashboard', state: null }),
}));

const TestComponent = () => <div>Protected Content</div>;

describe('ProtectedRoute', () => {
  beforeEach(() => {
    mockNavigate.mockClear();
  });

  it('renders children when user is authenticated', () => {
    renderWithProviders(
      <ProtectedRoute>
        <TestComponent />
      </ProtectedRoute>,
      {
        preloadedState: mockAuthenticatedState,
      }
    );

    expect(screen.getByText('Protected Content')).toBeInTheDocument();
    expect(mockNavigate).not.toHaveBeenCalled();
  });

  it('redirects to login when user is not authenticated', () => {
    renderWithProviders(
      <ProtectedRoute>
        <TestComponent />
      </ProtectedRoute>,
      {
        preloadedState: mockUnauthenticatedState,
      }
    );

    // Should redirect, so protected content should not be visible
    expect(screen.queryByText('Protected Content')).not.toBeInTheDocument();
    
    // Check if Navigate was called with the correct path
    expect(screen.getByTestId('navigate')).toBeInTheDocument();
    expect(screen.getByTestId('navigate')).toHaveAttribute('data-to', '/login');
    expect(mockNavigate).toHaveBeenCalledWith('/login');
  });

  it('redirects to email verification when user is unverified and email verification is required', () => {
    const unverifiedUserState = {
      ...mockAuthenticatedState,
      auth: {
        ...mockAuthenticatedState.auth,
        user: {
          ...mockAuthenticatedState.auth.user!,
          emailVerified: false,
        },
      },
    };

    renderWithProviders(
      <ProtectedRoute requireEmailVerification>
        <TestComponent />
      </ProtectedRoute>,
      {
        preloadedState: unverifiedUserState,
      }
    );

    expect(screen.queryByText('Protected Content')).not.toBeInTheDocument();
    expect(screen.getByTestId('navigate')).toHaveAttribute('data-to', '/verify-email');
    expect(mockNavigate).toHaveBeenCalledWith('/verify-email');
  });

  it('allows access when user has required role', () => {
    renderWithProviders(
      <ProtectedRoute requiredRoles={['admin']}>
        <TestComponent />
      </ProtectedRoute>,
      {
        preloadedState: mockAuthenticatedState, // User is admin
      }
    );

    expect(screen.getByText('Protected Content')).toBeInTheDocument();
    expect(mockNavigate).not.toHaveBeenCalled();
  });

  it('redirects to unauthorized when user lacks required role', () => {
    const memberUserState = {
      ...mockAuthenticatedState,
      auth: {
        ...mockAuthenticatedState.auth,
        user: {
          ...mockAuthenticatedState.auth.user!,
          roles: ['member'],
        },
      },
    };

    renderWithProviders(
      <ProtectedRoute requiredRoles={['admin', 'owner']}>
        <TestComponent />
      </ProtectedRoute>,
      {
        preloadedState: memberUserState,
      }
    );

    expect(screen.queryByText('Protected Content')).not.toBeInTheDocument();
    expect(screen.getByTestId('navigate')).toHaveAttribute('data-to', '/unauthorized');
    expect(mockNavigate).toHaveBeenCalledWith('/unauthorized');
  });

  it('allows access for multiple required roles', () => {
    const ownerUserState = {
      ...mockAuthenticatedState,
      auth: {
        ...mockAuthenticatedState.auth,
        user: {
          ...mockAuthenticatedState.auth.user!,
          roles: ['owner'],
        },
      },
    };

    renderWithProviders(
      <ProtectedRoute requiredRoles={['admin', 'owner']}>
        <TestComponent />
      </ProtectedRoute>,
      {
        preloadedState: ownerUserState,
      }
    );

    expect(screen.getByText('Protected Content')).toBeInTheDocument();
    expect(mockNavigate).not.toHaveBeenCalled();
  });
});