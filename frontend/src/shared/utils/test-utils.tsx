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

// Re-export everything from testing-library
export * from '@testing-library/react';