import { screen, waitFor } from '@testing-library/react';
import { VerifyEmailPage } from './VerifyEmailPage';
import { renderWithProviders, mockAuthenticatedState } from '@/shared/utils/test-utils';

const mockAddNotification = jest.fn();
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ addNotification: mockAddNotification }),
}));

const mockVerifyEmail = jest.fn();
jest.mock('@/features/account/auth/services/authAPI', () => ({
  authApi: {
    verifyEmail: (...args: unknown[]) => mockVerifyEmail(...args),
  },
}));

// The route requires authentication (App.tsx wraps /verify-email in
// ProtectedRoute) but not verification -- the whole point of this page.
const AUTH_STATE = {
  ...mockAuthenticatedState,
  auth: {
    ...mockAuthenticatedState.auth,
    user: { ...mockAuthenticatedState.auth.user, email_verified: false },
  },
};

describe('VerifyEmailPage', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('a verification token is present in the URL', () => {
    it('calls verifyEmail exactly once with the token', async () => {
      mockVerifyEmail.mockResolvedValue({
        data: { success: true, data: { message: 'Email verified successfully' } },
      });
      renderWithProviders(<VerifyEmailPage />, {
        preloadedState: AUTH_STATE,
        route: '/verify-email?token=abc123',
      });

      await waitFor(() => expect(mockVerifyEmail).toHaveBeenCalledTimes(1));
      expect(mockVerifyEmail).toHaveBeenCalledWith('abc123');
    });

    // Single-use: it must never sit in history or leak through a Referer
    // header on whatever the user navigates to next.
    it('clears the token from the address bar once read', async () => {
      mockVerifyEmail.mockResolvedValue({
        data: { success: true, data: { message: 'Email verified successfully' } },
      });
      renderWithProviders(<VerifyEmailPage />, {
        preloadedState: AUTH_STATE,
        route: '/verify-email?token=abc123',
      });

      await waitFor(() => expect(mockVerifyEmail).toHaveBeenCalledTimes(1));
      expect(window.location.search).not.toContain('token');
      expect(window.location.pathname).toBe('/verify-email');
    });

    it('renders the backend success message', async () => {
      mockVerifyEmail.mockResolvedValue({
        data: { success: true, data: { message: 'Email verified successfully' } },
      });
      renderWithProviders(<VerifyEmailPage />, {
        preloadedState: AUTH_STATE,
        route: '/verify-email?token=abc123',
      });

      await waitFor(() => expect(screen.getByText('Email verified successfully')).toBeInTheDocument());
    });

    it('renders the backend expired message on a 422', async () => {
      mockVerifyEmail.mockRejectedValue({
        response: {
          status: 422,
          data: { success: false, error: 'Verification token has expired. Please request a new one.' },
        },
      });
      renderWithProviders(<VerifyEmailPage />, {
        preloadedState: AUTH_STATE,
        route: '/verify-email?token=stale',
      });

      await waitFor(() =>
        expect(
          screen.getByText('Verification token has expired. Please request a new one.'),
        ).toBeInTheDocument(),
      );
    });

    it('renders the backend invalid-token message on a 404', async () => {
      mockVerifyEmail.mockRejectedValue({
        response: { status: 404, data: { success: false, error: 'Invalid verification token' } },
      });
      renderWithProviders(<VerifyEmailPage />, {
        preloadedState: AUTH_STATE,
        route: '/verify-email?token=bogus',
      });

      await waitFor(() => expect(screen.getByText('Invalid verification token')).toBeInTheDocument());
    });
  });

  describe('no token in the URL', () => {
    it('shows the resend UI and never calls verifyEmail', async () => {
      renderWithProviders(<VerifyEmailPage />, {
        preloadedState: AUTH_STATE,
        route: '/verify-email',
      });

      expect(screen.getByText('Verify your email')).toBeInTheDocument();
      expect(screen.getByRole('button', { name: /resend verification email/i })).toBeInTheDocument();
      // Give any stray effect a tick to fire before asserting the negative.
      await new Promise((r) => setTimeout(r, 10));
      expect(mockVerifyEmail).not.toHaveBeenCalled();
    });
  });
});
