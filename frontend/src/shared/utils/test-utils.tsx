import React, { ReactElement } from 'react';
import { render, RenderOptions } from '@testing-library/react';
import { Provider } from 'react-redux';
import { BrowserRouter } from 'react-router-dom';
import { configureStore } from '@reduxjs/toolkit';
import authReducer from '../services/slices/authSlice';
import uiReducer from '../services/slices/uiSlice';

// This type interface extends the default options for render from RTL, as well
// as allows the user to specify other things such as initialState, store.
interface ExtendedRenderOptions extends Omit<RenderOptions, 'wrapper'> {
  preloadedState?: any;
  store?: any;
  route?: string;
}

export function renderWithProviders(
  ui: ReactElement,
  {
    preloadedState = {},
    // Automatically create a store instance if no store was passed in
    store = configureStore({
      reducer: {
        auth: authReducer,
        ui: uiReducer,
      },
      ...(preloadedState && { preloadedState }),
    }),
    route = '/',
    ...renderOptions
  }: ExtendedRenderOptions = {}
) {
  // Set the initial route
  window.history.pushState({}, 'Test page', route);

  function Wrapper({ children }: { children?: React.ReactNode }): React.ReactElement {
    return (
      <Provider store={store}>
        <BrowserRouter 
          future={{
            v7_startTransition: true,
            v7_relativeSplatPath: true,
          }}
        >
          {children}
        </BrowserRouter>
      </Provider>
    );
  }

  return { store, ...render(ui, { wrapper: Wrapper, ...renderOptions }) };
}

// Mock user data
export const mockUser = {
  id: '123',
  email: 'test@example.com',
  first_name: 'John',
  last_name: 'Doe',
  roles: ['system.admin'],
  permissions: ['users.create', 'users.read', 'users.update', 'users.delete', 'billing.read', 'billing.update'],
  status: 'active',
  email_verified: true,
  account: {
    id: '456',
    name: 'Test Company',
    status: 'active',
  },
};

// Multiple mock users for different test scenarios
export const mockUsers = {
  adminUser: {
    id: '123',
    email: 'admin@example.com',
    first_name: 'Admin',
    last_name: 'User',
    roles: ['system.admin'],
    permissions: ['users.create', 'users.read', 'users.update', 'users.delete', 'users.manage', 'team.manage', 'billing.read', 'billing.update', 'admin.access', 'settings.update'],
    status: 'active',
    email_verified: true,
    account: {
      id: '456',
      name: 'Test Company',
      status: 'active',
    },
  },
  regularUser: {
    id: '124',
    email: 'user@example.com',
    first_name: 'Regular',
    last_name: 'User',
    roles: ['account.member'],
    permissions: ['users.read'],
    status: 'active',
    email_verified: true,
    account: {
      id: '456',
      name: 'Test Company',
      status: 'active',
    },
  },
  billingManager: {
    id: '125',
    email: 'billing@example.com',
    first_name: 'Billing',
    last_name: 'Manager',
    roles: ['billing.manager'],
    permissions: ['billing.read', 'billing.update', 'billing.manage'],
    status: 'active',
    email_verified: true,
    account: {
      id: '456',
      name: 'Test Company',
      status: 'active',
    },
  },
};

// Mock authenticated state
export const mockAuthenticatedState = {
  auth: {
    user: mockUser,
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
};

// Mock unauthenticated state
export const mockUnauthenticatedState = {
  auth: {
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
    },
  },
  ui: {
    sidebarOpen: true,
    sidebarCollapsed: false,
    theme: 'light' as const,
    loading: false,
    notifications: [],
  },
};

// Enhanced type interfaces for testing (with all required properties)
export interface EnhancedPlan {
  id: string;
  name: string;
  description: string;
  price_cents: number;
  currency: string;
  billing_cycle: 'monthly' | 'yearly' | 'quarterly';
  status: 'active' | 'inactive' | 'archived';
  trial_days: number;
  is_public: boolean;
  formatted_price: string;
  monthly_price: string;
  created_at: string;
  updated_at: string;
  // Optional properties
  price?: number;
  features?: string[] | Record<string, unknown>;
  active?: boolean;
  is_popular?: boolean;
  subscription_count?: number;
  active_subscription_count?: number;
  can_be_deleted?: boolean;
  has_annual_discount?: boolean;
  annual_discount_percent?: number;
  has_promotional_discount?: boolean;
  promotional_discount_percent?: number;
  promotional_discount_start?: string | null;
  promotional_discount_end?: string | null;
  promotional_discount_code?: string | null;
  has_volume_discount?: boolean;
  annual_savings_amount?: string;
  annual_savings_percentage?: number;
  limits?: Record<string, any>;
}

export interface EnhancedUser {
  id: string;
  first_name: string | null;
  last_name: string | null;
  full_name: string;
  email: string;
  email_verified: boolean;
  roles: string[];
  permissions: string[];
  status: 'active' | 'suspended' | 'inactive';
  locked: boolean;
  failed_login_attempts: number;
  preferences: Record<string, any>;
  account: {
    id: string;
    name: string;
    status: string;
  };
  // Optional properties
  phone?: string;
  last_login_at: string | null;
  created_at: string;
  updated_at: string;
  invitation_sent_at?: string;
}

// Enhanced mock creation functions
export const createMockPlan = (overrides: Partial<EnhancedPlan> = {}): EnhancedPlan => ({
  id: 'plan_basic',
  name: 'Basic Plan',
  description: 'Perfect for small teams',
  price_cents: 999,
  currency: 'USD',
  billing_cycle: 'monthly',
  status: 'active',
  trial_days: 14,
  is_public: true,
  formatted_price: '$9.99',
  monthly_price: '$9.99/month',
  created_at: new Date().toISOString(),
  updated_at: new Date().toISOString(),
  // Optional/additional properties
  price: 9.99,
  features: [
    'Up to 5 users',
    'Basic support',
    '10GB storage',
    'Standard integrations'
  ],
  active: true,
  is_popular: false,
  ...overrides
});

export const createMockUser = (overrides: Partial<EnhancedUser> = {}): EnhancedUser => ({
  id: '1',
  first_name: 'John',
  last_name: 'Doe',
  full_name: 'John Doe',
  email: 'user@example.com',
  email_verified: true,
  roles: ['account.member'],
  permissions: ['users.read', 'plans.read'],
  status: 'active',
  locked: false,
  failed_login_attempts: 0,
  preferences: {},
  account: {
    id: 'acc_1',
    name: 'Test Company',
    status: 'active'
  },
  // Required properties
  last_login_at: new Date().toISOString(),
  created_at: new Date().toISOString(),
  updated_at: new Date().toISOString(),
  ...overrides
});

// Mock Axios response helper for tests
export const createMockAxiosResponse = <T,>(data: T) => ({
  data,
  status: 200,
  statusText: 'OK',
  headers: {},
  config: {
    headers: {} as any
  }
});

// Re-export everything from testing-library
export * from '@testing-library/react';