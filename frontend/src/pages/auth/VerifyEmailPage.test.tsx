import React from 'react';
import { render, screen, fireEvent, waitFor, act } from '@testing-library/react';
import { Provider } from 'react-redux';
import { configureStore } from '@reduxjs/toolkit';
import { VerifyEmailPage } from './VerifyEmailPage';
import authReducer from '../../store/slices/authSlice';
import uiReducer from '../../store/slices/uiSlice';
import { authAPI } from '../../services/authAPI';

// Mock the authAPI
jest.mock('../../services/authAPI');
const mockedAuthAPI = authAPI as jest.Mocked<typeof authAPI>;

// Mock timers for testing cooldown
jest.useFakeTimers();

const createMockStore = (initialAuthState = {}) => {
  return configureStore({
    reducer: {
      auth: authReducer,
      ui: uiReducer,
    },
    preloadedState: {
      auth: {
        user: {
          id: '1',
          email: 'test@example.com',
          firstName: 'John',
          lastName: 'Doe',
          roles: ['admin'],
          status: 'active',
          emailVerified: false,
          account: {
            id: '1',
            name: 'Test Company',
            status: 'active',
          },
        },
        accessToken: null,
        refreshToken: null,
        isAuthenticated: false,
        isLoading: false,
        error: null,
        resendingVerification: false,
        resendVerificationSuccess: false,
        resendCooldown: 0,
        ...initialAuthState,
      },
      ui: {
        sidebarOpen: true,
        sidebarCollapsed: false,
        theme: 'light' as const,
        loading: false,
        notifications: [],
      },
    },
  });
};

describe('VerifyEmailPage', () => {
  afterEach(() => {
    jest.clearAllMocks();
    jest.clearAllTimers();
  });

  it('renders verification page with user email', () => {
    const store = createMockStore();
    
    render(
      <Provider store={store}>
        <VerifyEmailPage />
      </Provider>
    );

    expect(screen.getByText('Verify your email')).toBeInTheDocument();
    expect(screen.getByText('test@example.com')).toBeInTheDocument();
    expect(screen.getByText('Resend verification email')).toBeInTheDocument();
  });

  it('handles successful resend verification', async () => {
    const mockResponse = {
      data: { message: 'Verification email sent' },
      status: 200,
      statusText: 'OK',
      headers: {},
      config: {} as any,
    };
    mockedAuthAPI.resendVerification.mockResolvedValueOnce(mockResponse);

    const store = createMockStore();
    
    render(
      <Provider store={store}>
        <VerifyEmailPage />
      </Provider>
    );

    const resendButton = screen.getByText('Resend verification email');
    fireEvent.click(resendButton);

    // Should show loading state
    await waitFor(() => {
      expect(screen.getByText('Sending...')).toBeInTheDocument();
    });

    // Wait for success state
    await waitFor(() => {
      expect(screen.getByText('Verification email sent successfully!')).toBeInTheDocument();
    });

    // Should show cooldown
    await waitFor(() => {
      expect(screen.getByText(/Resend verification email \(60s\)/)).toBeInTheDocument();
    });
  });

  it('handles resend verification error', async () => {
    const mockError = { 
      response: { 
        data: { 
          error: 'Rate limit exceeded. Please try again later.' 
        } 
      } 
    };
    mockedAuthAPI.resendVerification.mockRejectedValueOnce(mockError);

    const store = createMockStore();
    
    render(
      <Provider store={store}>
        <VerifyEmailPage />
      </Provider>
    );

    const resendButton = screen.getByText('Resend verification email');
    fireEvent.click(resendButton);

    await waitFor(() => {
      expect(screen.getByText('Rate limit exceeded. Please try again later.')).toBeInTheDocument();
    });
  });

  it('shows cooldown countdown and prevents clicking during cooldown', async () => {
    const store = createMockStore({
      resendCooldown: 60,
    });
    
    render(
      <Provider store={store}>
        <VerifyEmailPage />
      </Provider>
    );

    const resendButton = screen.getByText(/Resend verification email \(60s\)/);
    expect(resendButton).toBeDisabled();

    // Advance timers to simulate countdown
    act(() => {
      jest.advanceTimersByTime(1000);
    });

    await waitFor(() => {
      expect(screen.getByText(/Resend verification email \(59s\)/)).toBeInTheDocument();
    });
  });

  it('clears success message after 5 seconds', async () => {
    const store = createMockStore({
      resendVerificationSuccess: true,
    });
    
    render(
      <Provider store={store}>
        <VerifyEmailPage />
      </Provider>
    );

    expect(screen.getByText('Verification email sent successfully!')).toBeInTheDocument();

    // Fast forward 5 seconds
    act(() => {
      jest.advanceTimersByTime(5000);
    });

    await waitFor(() => {
      expect(screen.queryByText('Verification email sent successfully!')).not.toBeInTheDocument();
    });
  });

  it('disables button during loading state', async () => {
    const store = createMockStore({
      resendingVerification: true,
    });
    
    render(
      <Provider store={store}>
        <VerifyEmailPage />
      </Provider>
    );

    const resendButton = screen.getByRole('button');
    expect(resendButton).toBeDisabled();
    expect(screen.getByText('Sending...')).toBeInTheDocument();
  });
});