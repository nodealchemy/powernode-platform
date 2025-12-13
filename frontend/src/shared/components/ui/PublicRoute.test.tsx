import React from 'react';
import { render, screen } from '@testing-library/react';
import { Provider } from 'react-redux';
import { MemoryRouter } from 'react-router-dom';
import { configureStore } from '@reduxjs/toolkit';
import { PublicRoute } from './PublicRoute';

describe('PublicRoute', () => {
  const createStore = (isAuthenticated: boolean) => configureStore({
    reducer: {
      auth: () => ({ isAuthenticated })
    }
  });

  const renderWithProviders = (
    ui: React.ReactElement,
    isAuthenticated: boolean
  ) => {
    return render(
      <Provider store={createStore(isAuthenticated)}>
        <MemoryRouter>
          {ui}
        </MemoryRouter>
      </Provider>
    );
  };

  describe('unauthenticated users', () => {
    it('renders children when not authenticated', () => {
      renderWithProviders(
        <PublicRoute><div>Login Form</div></PublicRoute>,
        false
      );

      expect(screen.getByText('Login Form')).toBeInTheDocument();
    });

    it('renders multiple children', () => {
      renderWithProviders(
        <PublicRoute>
          <div>Header</div>
          <div>Content</div>
        </PublicRoute>,
        false
      );

      expect(screen.getByText('Header')).toBeInTheDocument();
      expect(screen.getByText('Content')).toBeInTheDocument();
    });
  });

  describe('authenticated users', () => {
    it('does not render children when authenticated', () => {
      renderWithProviders(
        <PublicRoute><div>Login Form</div></PublicRoute>,
        true
      );

      expect(screen.queryByText('Login Form')).not.toBeInTheDocument();
    });
  });

  describe('redirect behavior', () => {
    it('uses default redirect path /app', () => {
      // Default redirectTo is /app
      renderWithProviders(
        <PublicRoute><div>Content</div></PublicRoute>,
        true
      );

      // Content should not be rendered (redirected)
      expect(screen.queryByText('Content')).not.toBeInTheDocument();
    });

    it('accepts custom redirectTo path', () => {
      renderWithProviders(
        <PublicRoute redirectTo="/dashboard"><div>Content</div></PublicRoute>,
        true
      );

      // Content should not be rendered (redirected)
      expect(screen.queryByText('Content')).not.toBeInTheDocument();
    });
  });
});
