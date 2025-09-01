import React, { ReactElement } from 'react';
import { render, RenderOptions } from '@testing-library/react';
import { BrowserRouter } from 'react-router-dom';
import { Provider } from 'react-redux';
import { configureStore, PreloadedState } from '@reduxjs/toolkit';

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
export const createTestStore = (preloadedState?: PreloadedState<any>) => {
  return configureStore({
    reducer: {
      auth: (state = { user: null, isLoading: false, isAuthenticated: false }, action) => {
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
            return { user: null, isLoading: false, isAuthenticated: false };
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
    },
    preloadedState
  });
};

// Test wrapper component
interface AllTheProvidersProps {
  children: React.ReactNode;
  initialState?: PreloadedState<any>;
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

// Custom render function
interface CustomRenderOptions extends Omit<RenderOptions, 'wrapper'> {
  initialState?: PreloadedState<any>;
}

export const renderWithProviders = (
  ui: ReactElement,
  options?: CustomRenderOptions
) => {
  const { initialState, ...renderOptions } = options || {};
  
  return render(ui, {
    wrapper: (props) => <AllTheProviders {...props} initialState={initialState} />,
    ...renderOptions,
  });
};

// Mock user data for testing
export const mockUsers = {
  regularUser: {
    id: '1',
    email: 'user@example.com',
    first_name: 'John',
    last_name: 'Doe',
    permissions: ['users.read', 'plans.read'],
    account: {
      id: 'acc_1',
      name: 'Test Company'
    }
  },
  adminUser: {
    id: '2',
    email: 'admin@example.com',
    first_name: 'Admin',
    last_name: 'User',
    permissions: ['users.read', 'users.manage', 'admin.access', 'plans.read', 'billing.manage'],
    account: {
      id: 'acc_2',
      name: 'Admin Company'
    }
  },
  billingManager: {
    id: '3',
    email: 'billing@example.com',
    first_name: 'Billing',
    last_name: 'Manager',
    permissions: ['users.read', 'billing.read', 'billing.manage', 'invoices.create'],
    account: {
      id: 'acc_3',
      name: 'Billing Company'
    }
  }
};

// Mock plans data
export const mockPlans = [
  {
    id: 'plan_basic',
    name: 'Basic Plan',
    description: 'Perfect for small teams',
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
    is_popular: false
  },
  {
    id: 'plan_pro',
    name: 'Pro Plan',
    description: 'Perfect for growing businesses',
    price_cents: 2999,
    currency: 'USD',
    billing_cycle: 'monthly',
    trial_days: 14,
    features: [
      'Unlimited users',
      'Priority support',
      '100GB storage',
      'Advanced analytics',
      'Custom integrations'
    ],
    is_popular: true
  },
  {
    id: 'plan_enterprise',
    name: 'Enterprise Plan',
    description: 'For large organizations',
    price_cents: 9999,
    currency: 'USD',
    billing_cycle: 'monthly',
    trial_days: 30,
    features: [
      'Unlimited everything',
      'Dedicated support',
      'Unlimited storage',
      'Custom development',
      'SLA guarantee'
    ],
    is_popular: false
  }
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

export const createMockApiResponse = <T>(data: T, success = true) => ({
  success,
  data,
  ...(success ? {} : { error: 'Mock error' })
});

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