import { fireEvent, screen, waitFor } from '@testing-library/react';
import { Route, Routes } from 'react-router-dom';
import { ProtectedRoute } from '@/shared/components/ui/ProtectedRoute';
import { VerifyEmailPage } from './VerifyEmailPage';
import { renderWithProviders, mockAuthenticatedState } from '@/shared/utils/test-utils';

const mockAddNotification = jest.fn();
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ addNotification: mockAddNotification }),
}));

const mockVerifyEmail = jest.fn();
const mockGetCurrentUser = jest.fn();
jest.mock('@/features/account/auth/services/authAPI', () => ({
  authApi: {
    verifyEmail: (...args: unknown[]) => mockVerifyEmail(...args),
    getCurrentUser: (...args: unknown[]) => mockGetCurrentUser(...args),
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
    // Refreshed user, now verified — matches what /auth/me actually returns
    // right after a successful token verification.
    mockGetCurrentUser.mockResolvedValue({
      data: {
        success: true,
        data: { user: { ...mockAuthenticatedState.auth.user, email_verified: true } },
      },
    });
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

    // review2-resume.md V2: distinct headings for expired vs. invalid, so the
    // wrong bucket can't render silently as the other.
    it('heads a 422 "Link expired" and never "Link invalid"', async () => {
      mockVerifyEmail.mockRejectedValue({
        response: {
          status: 422,
          data: { success: false, error: 'Verification token has expired. Please request a new one.' },
        },
      });
      renderWithProviders(<VerifyEmailPage />, { preloadedState: AUTH_STATE, route: '/verify-email?token=stale' });

      await waitFor(() => expect(screen.getByText('Link expired')).toBeInTheDocument());
      expect(screen.queryByText('Link invalid')).toBeNull();
    });

    it('heads a 404 "Link invalid" and never "Link expired"', async () => {
      mockVerifyEmail.mockRejectedValue({
        response: { status: 404, data: { success: false, error: 'Invalid verification token' } },
      });
      renderWithProviders(<VerifyEmailPage />, { preloadedState: AUTH_STATE, route: '/verify-email?token=used-once' });

      await waitFor(() => expect(screen.getByText('Link invalid')).toBeInTheDocument());
      expect(screen.queryByText('Link expired')).toBeNull();
    });

    // review2-resume.md V2.
    it('never logs the token, on the success path or the error path', async () => {
      const secret = 'secret-tok-XYZ';
      const seen: string[] = [];
      const methods = ['log', 'info', 'warn', 'error', 'debug'] as const;
      const spies = methods.map((m) =>
        jest.spyOn(console, m).mockImplementation((...args: unknown[]) => {
          seen.push(args.map((a) => (typeof a === 'string' ? a : JSON.stringify(a))).join(' '));
        }),
      );
      try {
        mockVerifyEmail.mockResolvedValueOnce({
          data: { success: true, data: { message: 'Email verified successfully' } },
        });
        const first = renderWithProviders(<VerifyEmailPage />, {
          preloadedState: AUTH_STATE,
          route: `/verify-email?token=${secret}`,
        });
        await waitFor(() => expect(screen.getByText('Email verified successfully')).toBeInTheDocument());
        first.unmount();

        mockVerifyEmail.mockRejectedValueOnce({
          response: {
            status: 422,
            data: { success: false, error: 'Verification token has expired. Please request a new one.' },
          },
        });
        renderWithProviders(<VerifyEmailPage />, {
          preloadedState: AUTH_STATE,
          route: `/verify-email?token=${secret}`,
        });
        await waitFor(() => expect(screen.getByText(/has expired/)).toBeInTheDocument());
      } finally {
        spies.forEach((s) => s.mockRestore());
      }
      const leaks = seen.filter((line) => line.includes(secret));
      expect(leaks).toEqual([]);
      expect(JSON.stringify(mockAddNotification.mock.calls)).not.toContain(secret);
    });

    // review2-resume.md V1: /app requires email_verified (App.tsx's ProtectedRoute
    // requireEmailVerification), and the redux user is stale right after verifying
    // until it's refreshed -- exercised through the REAL route guard, not a stub.
    it('after a success, refreshes the user and "Continue to Dashboard" reaches /app', async () => {
      mockVerifyEmail.mockResolvedValue({
        data: { success: true, data: { message: 'Email verified successfully' } },
      });
      renderWithProviders(
        <Routes>
          <Route path="/verify-email" element={<VerifyEmailPage />} />
          <Route
            path="/app"
            element={
              <ProtectedRoute requireEmailVerification>
                <div>DASHBOARD STUB</div>
              </ProtectedRoute>
            }
          />
        </Routes>,
        { preloadedState: AUTH_STATE, route: '/verify-email?token=continue-tok' },
      );

      await waitFor(() => expect(screen.getByText('Email verified successfully')).toBeInTheDocument());
      expect(mockGetCurrentUser).toHaveBeenCalledTimes(1);
      fireEvent.click(screen.getByRole('button', { name: /continue to dashboard/i }));

      await waitFor(() => expect(screen.getByText('DASHBOARD STUB')).toBeInTheDocument());
      expect(screen.queryByText('Verify your email')).toBeNull();
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
