import React, { ReactElement } from 'react';
import { render, RenderOptions } from '@testing-library/react';
import { BrowserRouter } from 'react-router-dom';
import { Provider } from 'react-redux';
import { configureStore } from '@reduxjs/toolkit';
import { RootState } from '@/shared/services';

// Mock theme context for all tests
export const MockThemeProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  return <div data-theme="light">{children}</div>;
};

// Mock notifications for all tests
export const mockNotifications = {
  showNotification: jest.fn(),
  hideNotification: jest.fn()
};

// Basic Redux store for testing
export const createTestStore = (preloadedState?: any) => {
  const rootReducer = (state: any = {
    auth: { user: null, isLoading: false, isAuthenticated: false },
    plans: { plans: [], isLoading: false }
  }, action: any) => {
    return {
      auth: (state.auth && typeof state.auth === 'object') ? 
        (() => {
          switch (action.type) {
            case 'auth/loginStart':
              return { ...state.auth, isLoading: true };
            case 'auth/loginSuccess':
              return { 
                ...state.auth, 
                user: action.payload?.user, 
                isLoading: false, 
                isAuthenticated: true 
              };
            case 'auth/logout':
              return { user: null, isLoading: false, isAuthenticated: false };
            default:
              return state.auth;
          }
        })() : { user: null, isLoading: false, isAuthenticated: false },
      plans: (state.plans && typeof state.plans === 'object') ?
        (() => {
          switch (action.type) {
            case 'plans/fetchStart':
              return { ...state.plans, isLoading: true };
            case 'plans/fetchSuccess':
              return { ...state.plans, plans: action.payload, isLoading: false };
            default:
              return state.plans;
          }
        })() : { plans: [], isLoading: false }
    };
  };

  return configureStore({
    reducer: rootReducer,
    preloadedState
  });
};

// Test wrapper component
interface AllTheProvidersProps {
  children: React.ReactNode;
  initialState?: any;
}

const AllTheProviders: React.FC<AllTheProvidersProps> = ({ children, initialState }) => {
  const store = createTestStore(initialState);
  
  return (
    <Provider store={store}>
      <BrowserRouter>
        <MockThemeProvider>
          {children}
        </MockThemeProvider>
      </BrowserRouter>
    </Provider>
  );
};

// Support both new and legacy interfaces
export interface ExtendedRenderOptions extends Omit<RenderOptions, 'wrapper'> {
  preloadedState?: any;
  initialState?: any; // Legacy support
}

export const renderWithProviders = (
  ui: ReactElement,
  options?: ExtendedRenderOptions
) => {
  const { initialState, preloadedState, ...renderOptions } = options || {};
  const state = preloadedState || initialState;
  
  return render(ui, {
    wrapper: (props) => <AllTheProviders {...props} initialState={state} />,
    ...renderOptions,
  });
};

// Enhanced mock creation functions (moved up for proper hoisting)
export const createMockPlan = (overrides: Partial<EnhancedPlan> = {}): EnhancedPlan => ({
  id: 'plan_basic',
  name: 'Basic Plan',
  description: 'Perfect for small teams',
  price: 9.99,
  price_cents: 999,
  currency: 'USD',
  billing_cycle: 'monthly',
  trial_days: 14,
  features: [
    'Up to 5 users',
    'Basic support',
    '10GB storage',
    'Standard integrations'
  ],
  active: true,
  is_popular: false,
  created_at: new Date().toISOString(),
  updated_at: new Date().toISOString(),
  ...overrides
});

export const createMockUser = (overrides: Partial<EnhancedUser> = {}): EnhancedUser => ({
  id: '1',
  email: 'user@example.com',
  first_name: 'John',
  last_name: 'Doe',
  roles: ['account.member'],
  permissions: ['users.read', 'plans.read'],
  status: 'active',
  email_verified: true,
  last_login_at: new Date().toISOString(),
  created_at: new Date().toISOString(),
  updated_at: new Date().toISOString(),
  account: {
    id: 'acc_1',
    name: 'Test Company',
    status: 'active'
  },
  ...overrides
});

// Mock user data for testing using enhanced types
export const mockUsers = {
  regularUser: createMockUser({
    id: '1',
    email: 'user@example.com',
    first_name: 'John',
    last_name: 'Doe',
    roles: ['account.member'],
    permissions: ['users.read', 'plans.read'],
    account: {
      id: 'acc_1',
      name: 'Test Company'
    }
  }),
  adminUser: createMockUser({
    id: '2',
    email: 'admin@example.com',
    first_name: 'Admin',
    last_name: 'User',
    roles: ['system.admin'],
    permissions: ['users.read', 'users.manage', 'admin.access', 'plans.read', 'billing.manage'],
    account: {
      id: 'acc_2',
      name: 'Admin Company'
    }
  }),
  billingManager: createMockUser({
    id: '3',
    email: 'billing@example.com',
    first_name: 'Billing',
    last_name: 'Manager',
    roles: ['billing.manager'],
    permissions: ['users.read', 'billing.read', 'billing.manage', 'invoices.create'],
    account: {
      id: 'acc_3',
      name: 'Billing Company'
    }
  })
};

// Enhanced type interfaces for testing
export interface EnhancedPlan {
  id: string;
  name: string;
  description?: string;
  price?: number;
  price_cents?: number;
  currency?: string;
  billing_cycle: string;
  trial_days?: number;
  features?: string[] | Record<string, unknown>;
  active?: boolean;
  is_popular?: boolean;
  created_at?: string;
  updated_at?: string;
}

export interface EnhancedUser {
  id: string;
  email: string;
  first_name: string;
  last_name: string;
  roles?: string[];
  permissions?: string[];
  status?: string;
  email_verified?: boolean;
  last_login_at?: string;
  created_at?: string;
  updated_at?: string;
  invitation_sent_at?: string;
  account?: {
    id: string;
    name: string;
    status?: string;
  };
}


// Mock plans data using enhanced types
export const mockPlans: EnhancedPlan[] = [
  createMockPlan({
    id: 'plan_basic',
    name: 'Basic Plan',
    description: 'Perfect for small teams',
    price_cents: 999,
    is_popular: false
  }),
  createMockPlan({
    id: 'plan_pro',
    name: 'Pro Plan',
    description: 'Perfect for growing businesses',
    price_cents: 2999,
    features: [
      'Unlimited users',
      'Priority support',
      '100GB storage',
      'Advanced analytics',
      'Custom integrations'
    ],
    is_popular: true
  }),
  createMockPlan({
    id: 'plan_enterprise',
    name: 'Enterprise Plan',
    description: 'For large organizations',
    price_cents: 9999,
    trial_days: 30,
    features: [
      'Unlimited everything',
      'Dedicated support',
      'Unlimited storage',
      'Custom development',
      'SLA guarantee'
    ],
    is_popular: false
  })
];

// Mock payment gateways data
export const mockPaymentGateways = {
  stripe: {
    provider: 'stripe',
    name: 'Stripe',
    enabled: true,
    test_mode: false,
    supported_methods: ['card', 'bank'],
    publishable_key_present: true,
    secret_key_present: true,
    endpoint_secret_present: true,
    webhook_tolerance: 300,
    api_version: '2023-10-16'
  },
  paypal: {
    provider: 'paypal',
    name: 'PayPal',
    enabled: false,
    test_mode: true,
    supported_methods: ['paypal'],
    client_id_present: false,
    client_secret_present: false,
    webhook_id_present: false,
    mode: 'sandbox'
  }
};

// Helper functions for tests
export const waitForLoadingToFinish = () => {
  return new Promise(resolve => setTimeout(resolve, 0));
};

export const createMockApiResponse = <T,>(data: T, success = true) => ({
  success,
  data,
  ...(success ? {} : { error: 'Mock error' })
});

// Mock authenticated state for proper testing
export const mockAuthenticatedState = {
  auth: {
    user: mockUsers.adminUser,
    accessToken: 'mock-access-token',
    refreshToken: 'mock-refresh-token',
    isAuthenticated: true,
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
    },
  },
  ui: {
    sidebarOpen: true,
    sidebarCollapsed: false,
    theme: 'light' as const,
    loading: false,
    notifications: [],
  },
  subscription: {
    currentSubscription: null,
    availablePlans: [],
    isLoading: false,
    error: null,
  },
};

// Re-export mock utilities
export { createMockAxiosResponse } from './test-utils/mockAxios';

export const mockLocalStorage = {
  getItem: jest.fn(),
  setItem: jest.fn(),
  removeItem: jest.fn(),
  clear: jest.fn(),
};

// Global test setup
beforeEach(() => {
  jest.clearAllMocks();
  
  // Reset localStorage mock
  Object.defineProperty(window, 'localStorage', {
    value: mockLocalStorage,
    writable: true
  });
  
  // Reset console error mock
  jest.spyOn(console, 'error').mockImplementation(() => {});
});

afterEach(() => {
  jest.restoreAllMocks();
});

// Re-export everything from React Testing Library
export * from '@testing-library/react';
export { renderWithProviders as render };