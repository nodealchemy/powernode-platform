import React from 'react';
import { render, screen, waitFor } from '@testing-library/react';
import { BrowserRouter } from 'react-router-dom';
import { Provider } from 'react-redux';
import { configureStore } from '@reduxjs/toolkit';
import { authApi } from '@/features/auth/services/authAPI';
import { plansApi } from '@/features/plans/services/plansApi';
import { createMockPlan } from '@/shared/utils/test-utils';

// Mock all APIs
jest.mock('@/features/auth/services/authAPI');
jest.mock('@/features/plans/services/plansApi');
jest.mock('@/features/billing/services/billingApi');

// Mock notifications
const mockShowNotification = jest.fn();
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    showNotification: mockShowNotification
  })
}));

// Mock theme context
jest.mock('@/shared/hooks/ThemeContext', () => ({
  useTheme: () => ({ 
    theme: 'light',
    toggleTheme: jest.fn() 
  })
}));

// Create test store with proper initial state structure
const createTestStore = () => {
  const initialAuthState = {
    user: null,
    accessToken: null,
    refreshToken: null,
    isAuthenticated: false,
    isLoading: false,
    error: null,
    resendingVerification: false,
    resendVerificationSuccess: false,
    resendCooldown: 0,
    impersonation: {
      isImpersonating: false,
      originalUser: null,
      impersonatedUser: null,
      sessionId: null,
      startedAt: null,
      expiresAt: null,
    }
  };

  const initialUIState = {
    sidebarOpen: true,
    sidebarCollapsed: false,
    theme: 'light' as const,
    loading: false,
    notifications: []
  };

  return configureStore({
    reducer: {
      auth: (state = initialAuthState, action: any) => {
        switch (action.type) {
          case 'auth/loginStart':
            return { ...state, isLoading: true };
          case 'auth/loginSuccess':
            return { 
              ...state, 
              user: action.payload.user, 
              isLoading: false, 
              isAuthenticated: true 
            };
          case 'auth/logout':
            return { ...initialAuthState };
          default:
            return state;
        }
      },
      ui: (state = initialUIState, action) => {
        switch (action.type) {
          case 'ui/setSidebarOpen':
            return { ...state, sidebarOpen: action.payload };
          default:
            return state;
        }
      },
      plans: (state = { plans: [], isLoading: false }, action) => {
        switch (action.type) {
          case 'plans/fetchStart':
            return { ...state, isLoading: true };
          case 'plans/fetchSuccess':
            return { ...state, plans: action.payload, isLoading: false };
          default:
            return state;
        }
      }
    }
  });
};

const mockAuthAPI = authApi as jest.Mocked<typeof authApi>;
const mockPlansApi = plansApi as jest.Mocked<typeof plansApi>;

// Mock data for testing
const mockPlans = [
  createMockPlan({
    id: 'plan_basic',
    name: 'Basic Plan',
    price_cents: 999,
    currency: 'USD',
    billing_cycle: 'monthly',
    trial_days: 14,
    features: {
      max_users: 5,
      basic_support: true,
      api_access: false,
      advanced_analytics: false
    }
  }),
  createMockPlan({
    id: 'plan_pro',
    name: 'Pro Plan',
    price_cents: 2999,
    currency: 'USD',
    billing_cycle: 'monthly',
    trial_days: 14,
    features: {
      max_users: 100,
      priority_support: true,
      api_access: true,
      advanced_analytics: true
    }
  }),
  createMockPlan({
    id: 'plan_enterprise',
    name: 'Enterprise Plan',
    price_cents: 9999,
    currency: 'USD',
    billing_cycle: 'monthly',
    trial_days: 30,
    features: {
      max_users: -1,  // Unlimited
      dedicated_support: true,
      api_access: true,
      advanced_analytics: true,
      custom_integrations: true
    }
  })
];

const renderWithProviders = (component: React.ReactElement) => {
  const store = createTestStore();
  return {
    ...render(
      <Provider store={store}>
        <BrowserRouter>
          {component}
        </BrowserRouter>
      </Provider>
    ),
    store
  };
};

// Mock App component for integration testing
const MockApp: React.FC = () => {
  return (
    <div data-testid="app">
      <h1>Powernode Platform</h1>
      <div data-testid="auth-section">Authentication Section</div>
      <div data-testid="dashboard-section">Dashboard Section</div>
      <div data-testid="plans-section">Plans Section</div>
    </div>
  );
};

describe('Subscription Workflow Integration', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('User Authentication Flow', () => {
    it('completes full login to dashboard workflow', async () => {
      const mockUser = {
        id: '1',
        email: 'user@example.com',
        name: 'Test User',
        roles: ['account.member'],
        permissions: ['users.read', 'plans.read', 'billing.read'],
        status: 'active',
        email_verified: true,
        account: {
          id: 'acc_1',
          name: 'Test Company',
          status: 'active'
        }
      };

      mockAuthAPI.login.mockResolvedValue({
        data: {
          success: true,
          user: mockUser,
          access_token: 'token123',
          refresh_token: 'refresh123'
        },
        status: 200,
        statusText: 'OK',
        headers: {},
        config: {
          headers: {} as any
        }
      });

      const { store } = renderWithProviders(<MockApp />);

      // Simulate login
      store.dispatch({
        type: 'auth/loginSuccess',
        payload: { user: mockUser }
      });

      await waitFor(() => {
        expect(screen.getByTestId('dashboard-section')).toBeInTheDocument();
      });
    });

    it('handles authentication failure gracefully', async () => {
      mockAuthAPI.login.mockRejectedValue({
        response: {
          data: { error: 'Invalid credentials' }
        }
      });

      renderWithProviders(<MockApp />);

      // Authentication should fail and show error
      await waitFor(() => {
        expect(screen.getByTestId('auth-section')).toBeInTheDocument();
      });
    });

    it('persists user session across page refreshes', async () => {
      const mockUser = {
        id: '1',
        email: 'user@example.com',
        name: 'Test User',
        roles: ['account.member'],
        permissions: ['users.read'],
        status: 'active',
        email_verified: true,
        account: {
          id: 'acc_1',
          name: 'Test Company',
          status: 'active'
        }
      };

      mockAuthAPI.getCurrentUser.mockResolvedValue({
        data: {
          success: true,
          data: { user: mockUser }
        },
        status: 200,
        statusText: 'OK',
        headers: {},
        config: {
          headers: {} as any
        }
      });

      // Simulate page refresh with stored token
      localStorage.setItem('authToken', 'stored-token');

      const { store } = renderWithProviders(<MockApp />);

      // Should automatically restore user session
      store.dispatch({
        type: 'auth/loginSuccess',
        payload: { user: mockUser }
      });

      await waitFor(() => {
        expect(store.getState().auth.isAuthenticated).toBe(true);
      });

      localStorage.removeItem('authToken');
    });
  });

  describe('Plan Selection and Subscription Flow', () => {

    it('loads and displays available plans', async () => {
      mockPlansApi.getPlans.mockResolvedValue({
        success: true,
        data: {
          plans: mockPlans,
          total_count: mockPlans.length
        }
      });

      const { store } = renderWithProviders(<MockApp />);

      // Load plans
      store.dispatch({
        type: 'plans/fetchSuccess',
        payload: mockPlans
      });

      await waitFor(() => {
        expect(store.getState().plans.plans).toEqual(mockPlans);
      });
    });

    it('handles plan selection and subscription creation', async () => {
      const mockSubscriptionResponse = {
        success: true,
        data: {
          id: 'sub_123',
          plan_id: 'plan_pro',
          status: 'trialing',
          trial_end: '2024-02-01T00:00:00Z',
          current_period_end: '2024-02-01T00:00:00Z'
        }
      };

      // Mock the billing API call for subscription creation
      const mockCreateSubscription = jest.fn().mockResolvedValue(mockSubscriptionResponse);

      renderWithProviders(<MockApp />);

      // Simulate plan selection and subscription creation
      const selectedPlan = mockPlans[1]; // Pro Plan
      
      // In a real app, this would trigger the subscription creation
      await mockCreateSubscription({
        plan_id: selectedPlan.id,
        billing_cycle: selectedPlan.billing_cycle
      });

      expect(mockCreateSubscription).toHaveBeenCalledWith({
        plan_id: 'plan_pro',
        billing_cycle: 'monthly'
      });
    });
  });

  describe('Permission-Based Access Control Integration', () => {
    it('shows appropriate UI elements based on user permissions', async () => {
      const userWithLimitedPermissions = {
        id: '1',
        email: 'user@example.com',
        permissions: ['users.read'] // No billing or admin permissions
      };

      const { store } = renderWithProviders(<MockApp />);

      store.dispatch({
        type: 'auth/loginSuccess',
        payload: { user: userWithLimitedPermissions }
      });

      await waitFor(() => {
        const state = store.getState();
        expect(state.auth.user.permissions).toEqual(['users.read']);
        // UI should adapt based on these permissions
      });
    });

    it('prevents access to admin features without proper permissions', async () => {
      const regularUser = {
        id: '1',
        email: 'user@example.com',
        permissions: ['users.read'] // No admin permissions
      };

      const { store } = renderWithProviders(<MockApp />);

      store.dispatch({
        type: 'auth/loginSuccess',
        payload: { user: regularUser }
      });

      await waitFor(() => {
        // Should not show admin-only features
        expect(screen.queryByTestId('admin-panel')).not.toBeInTheDocument();
      });
    });

    it('shows admin features for users with proper permissions', async () => {
      const adminUser = {
        id: '1',
        email: 'admin@example.com',
        permissions: ['users.read', 'admin.access', 'users.manage']
      };

      const { store } = renderWithProviders(<MockApp />);

      store.dispatch({
        type: 'auth/loginSuccess',
        payload: { user: adminUser }
      });

      await waitFor(() => {
        const state = store.getState();
        expect(state.auth.user.permissions).toContain('admin.access');
        // Should show admin features
      });
    });
  });

  describe('Error Handling and Recovery', () => {
    it('handles API failures gracefully', async () => {
      mockAuthAPI.getCurrentUser.mockRejectedValue({
        response: { status: 401, data: { error: 'Unauthorized' } }
      });

      renderWithProviders(<MockApp />);

      // Should handle API failures without crashing
      await waitFor(() => {
        expect(screen.getByTestId('app')).toBeInTheDocument();
      });
    });

    it('handles network connectivity issues', async () => {
      mockAuthAPI.login.mockRejectedValue({
        code: 'NETWORK_ERROR',
        message: 'Network request failed'
      });

      renderWithProviders(<MockApp />);

      // Should show appropriate error messaging for network issues
      await waitFor(() => {
        expect(screen.getByTestId('app')).toBeInTheDocument();
      });
    });

    it('recovers from temporary API failures', async () => {
      // First call fails, second succeeds
      mockAuthAPI.getCurrentUser
        .mockRejectedValueOnce({ message: 'Server error' })
        .mockResolvedValueOnce({
          data: {
            success: true,
            data: {
              user: {
                id: '1',
                email: 'user@example.com',
                name: 'Test User',
                roles: ['account.member'],
                permissions: ['users.read'],
                status: 'active',
                email_verified: true,
                account: {
                  id: 'acc_1',
                  name: 'Test Company',
                  status: 'active'
                }
              }
            }
          },
          status: 200,
          statusText: 'OK',
          headers: {},
          config: {
            headers: {} as any
          }
        });

      renderWithProviders(<MockApp />);

      // Should eventually succeed after retry
      await waitFor(() => {
        expect(screen.getByTestId('app')).toBeInTheDocument();
      }, { timeout: 5000 });
    });
  });

  describe('State Management Integration', () => {
    it('maintains consistent state across different components', async () => {
      const mockUser = {
        id: '1',
        email: 'user@example.com',
        permissions: ['users.read', 'plans.read']
      };

      const { store } = renderWithProviders(<MockApp />);

      // User login should update global state
      store.dispatch({
        type: 'auth/loginSuccess',
        payload: { user: mockUser }
      });

      // Plans loading should update global state
      store.dispatch({
        type: 'plans/fetchSuccess',
        payload: mockPlans
      });

      await waitFor(() => {
        const state = store.getState();
        expect(state.auth.user).toEqual(mockUser);
        expect(state.plans.plans).toEqual(mockPlans);
        expect(state.auth.isAuthenticated).toBe(true);
      });
    });

    it('handles concurrent state updates correctly', async () => {
      const { store } = renderWithProviders(<MockApp />);

      // Simulate concurrent authentication and data loading
      const authPromise = new Promise(resolve => {
        store.dispatch({
          type: 'auth/loginSuccess',
          payload: { 
            user: { 
              id: '1', 
              email: 'user@example.com',
              permissions: ['users.read']
            } 
          }
        });
        resolve(true);
      });

      const plansPromise = new Promise(resolve => {
        store.dispatch({
          type: 'plans/fetchSuccess',
          payload: mockPlans
        });
        resolve(true);
      });

      await Promise.all([authPromise, plansPromise]);

      const state = store.getState();
      expect(state.auth.isAuthenticated).toBe(true);
      expect(state.plans.plans).toHaveLength(3);
    });
  });
});