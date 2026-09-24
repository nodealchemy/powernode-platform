import { screen, fireEvent, waitFor } from '@testing-library/react';
import { LoginPage } from './LoginPage';
import { renderWithProviders, mockUnauthenticatedState } from '@/shared/utils/test-utils';
import { featureRegistry } from '@/shared/services/featureRegistry';

// Core names no pricing route: an extension registers the public route that
// fills the 'pricing' role, and the sign-up link follows it.
const PricingPage = () => null;
const registerPricing = () =>
  featureRegistry.registerPublicRoutes('test-ext', [
    { path: '/ext-pricing', component: PricingPage, role: 'pricing' },
  ]);

// Mock React Router hooks
const mockNavigate = jest.fn();
const mockLocation = { state: null, pathname: '/login' };

jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useNavigate: () => mockNavigate,
  useLocation: () => mockLocation,
}));

// Mock settingsApi
jest.mock('@/shared/services/settings/settingsApi', () => ({
  settingsApi: {
    getCopyright: jest.fn().mockResolvedValue('Test Copyright'),
    formatCopyright: jest.fn().mockReturnValue('© 2025 Test Company'),
  },
}));

// Mock the raw api client (not authAPI/twoFactorApi) so the real login ->
// 2FA -> getCurrentUser thunk chain runs against the real server envelope
// { success, data: {...}, message? } — see the 'two-factor authentication
// flow' describe block below.
const mockApiGet = jest.fn();
const mockApiPost = jest.fn();

jest.mock('@/shared/services/api', () => ({
  api: {
    get: (...args: unknown[]) => mockApiGet(...args),
    post: (...args: unknown[]) => mockApiPost(...args),
    put: jest.fn(),
    patch: jest.fn(),
    delete: jest.fn(),
  },
}));

// No need to mock slices - let actual reducers handle state

describe('LoginPage', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    featureRegistry.clear();
  });

  afterAll(() => featureRegistry.clear());

  describe('rendering', () => {
    it('renders the login form', () => {
      renderWithProviders(<LoginPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      expect(screen.getByText('Powernode')).toBeInTheDocument();
      expect(screen.getByText('Welcome back to your dashboard')).toBeInTheDocument();
      expect(screen.getByLabelText('Email address')).toBeInTheDocument();
      expect(screen.getByLabelText('Password')).toBeInTheDocument();
      expect(screen.getByRole('button', { name: /sign in/i })).toBeInTheDocument();
    });

    it('renders forgot password link', () => {
      renderWithProviders(<LoginPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      expect(screen.getByText('Forgot password?')).toBeInTheDocument();
      expect(screen.getByText('Forgot password?').closest('a')).toHaveAttribute('href', '/forgot-password');
    });

    it('renders create account link when registration enabled', () => {
      const stateWithRegistration = {
        ...mockUnauthenticatedState,
        config: {
          ...mockUnauthenticatedState.config,
          registrationEnabled: true,
        },
      };

      registerPricing();
      renderWithProviders(<LoginPage />, {
        preloadedState: stateWithRegistration,
      });

      expect(screen.getByText('Create your account')).toBeInTheDocument();
      expect(screen.getByText('Create your account').closest('a')).toHaveAttribute('href', '/ext-pricing');
    });

    it('shows no create account link when no extension registers a pricing route', () => {
      renderWithProviders(<LoginPage />, {
        preloadedState: {
          ...mockUnauthenticatedState,
          config: { ...mockUnauthenticatedState.config, registrationEnabled: true },
        },
      });

      expect(screen.queryByText('Create your account')).not.toBeInTheDocument();
      expect(screen.queryByText('New to Powernode?')).not.toBeInTheDocument();
    });

    it('hides create account link when registration disabled', () => {
      renderWithProviders(<LoginPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      expect(screen.queryByText('Create your account')).not.toBeInTheDocument();
    });

    it('renders remember me checkbox', () => {
      renderWithProviders(<LoginPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      expect(screen.getByLabelText(/remember me/i)).toBeInTheDocument();
      expect(screen.getByLabelText(/remember me/i)).not.toBeChecked();
    });

    it('renders trust indicators', () => {
      renderWithProviders(<LoginPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      expect(screen.getByText('Secure Login')).toBeInTheDocument();
      expect(screen.getByText('256-bit SSL')).toBeInTheDocument();
      expect(screen.getByText('Two-Factor Auth')).toBeInTheDocument();
    });

    it('renders footer links', () => {
      renderWithProviders(<LoginPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      expect(screen.getByText('Privacy Policy')).toBeInTheDocument();
      expect(screen.getByText('Terms of Service')).toBeInTheDocument();
      expect(screen.getByText('Support')).toBeInTheDocument();
    });
  });

  describe('form interactions', () => {
    it('updates email field on change', () => {
      renderWithProviders(<LoginPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      const emailInput = screen.getByLabelText('Email address');
      fireEvent.change(emailInput, { target: { value: 'test@example.com' } });
      expect(emailInput).toHaveValue('test@example.com');
    });

    it('updates password field on change', () => {
      renderWithProviders(<LoginPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      const passwordInput = screen.getByLabelText('Password');
      fireEvent.change(passwordInput, { target: { value: 'password123' } });
      expect(passwordInput).toHaveValue('password123');
    });

    it('toggles password visibility', () => {
      renderWithProviders(<LoginPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      const passwordInput = screen.getByLabelText('Password');
      const toggleButton = screen.getByLabelText('Show password');

      expect(passwordInput).toHaveAttribute('type', 'password');

      fireEvent.click(toggleButton);
      expect(passwordInput).toHaveAttribute('type', 'text');

      fireEvent.click(screen.getByLabelText('Hide password'));
      expect(passwordInput).toHaveAttribute('type', 'password');
    });

    it('toggles remember me checkbox', () => {
      renderWithProviders(<LoginPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      const checkbox = screen.getByLabelText(/remember me/i);
      expect(checkbox).not.toBeChecked();

      fireEvent.click(checkbox);
      expect(checkbox).toBeChecked();
    });
  });

  describe('error display', () => {
    it('displays error message when auth error exists', () => {
      const stateWithError = {
        ...mockUnauthenticatedState,
        auth: {
          ...mockUnauthenticatedState.auth,
          error: 'Invalid email or password',
        },
      };

      renderWithProviders(<LoginPage />, {
        preloadedState: stateWithError,
      });

      expect(screen.getByText('Invalid email or password')).toBeInTheDocument();
    });

    it('does not display error when no error exists', () => {
      renderWithProviders(<LoginPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      expect(screen.queryByRole('alert')).not.toBeInTheDocument();
    });
  });

  describe('form submission', () => {
    it('has required attributes on form fields', () => {
      renderWithProviders(<LoginPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      expect(screen.getByLabelText('Email address')).toBeRequired();
      expect(screen.getByLabelText('Password')).toBeRequired();
    });

    it('has correct autocomplete attributes', () => {
      renderWithProviders(<LoginPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      expect(screen.getByLabelText('Email address')).toHaveAttribute('autocomplete', 'username');
      expect(screen.getByLabelText('Password')).toHaveAttribute('autocomplete', 'current-password');
    });
  });

  describe('navigation', () => {
    it('links to welcome page from logo', () => {
      renderWithProviders(<LoginPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      const logoLink = screen.getByText('P').closest('a');
      expect(logoLink).toHaveAttribute('href', '/welcome');
    });

    it('links create account to the registered pricing route', () => {
      const stateWithRegistration = {
        ...mockUnauthenticatedState,
        config: {
          ...mockUnauthenticatedState.config,
          registrationEnabled: true,
        },
      };

      registerPricing();
      renderWithProviders(<LoginPage />, {
        preloadedState: stateWithRegistration,
      });

      const createAccountLink = screen.getByText('Create your account').closest('a');
      expect(createAccountLink).toHaveAttribute('href', '/ext-pricing');
    });
  });

  describe('accessibility', () => {
    it('has proper label associations', () => {
      renderWithProviders(<LoginPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      const emailInput = screen.getByLabelText('Email address');
      const passwordInput = screen.getByLabelText('Password');
      const rememberMe = screen.getByLabelText(/remember me/i);

      expect(emailInput).toHaveAttribute('id', 'email');
      expect(passwordInput).toHaveAttribute('id', 'password');
      expect(rememberMe).toHaveAttribute('id', 'remember-me');
    });

    it('has descriptive button for password visibility toggle', () => {
      renderWithProviders(<LoginPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      expect(screen.getByLabelText('Show password')).toBeInTheDocument();
    });
  });

  describe('copyright text', () => {
    it('displays copyright text', async () => {
      renderWithProviders(<LoginPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      // Copyright text should be present (either from mock or fallback)
      await waitFor(() => {
        // Check for any copyright text containing the year
        const copyrightElement = screen.getByText(/© \d{4}/);
        expect(copyrightElement).toBeInTheDocument();
      });
    });
  });

  // Traces the real login -> 2FA -> getCurrentUser consumer chain against
  // the actual server envelope, to answer: does twoFactorApi's un-unwrapped
  // /auth/verify-2fa reply (the same shape bug fixed for /two_factor in
  // twoFactorApi.ts) actually block a 2FA user from finishing sign-in?
  //
  // It does not. TwoFactorVerification only reads the envelope's top-level
  // `success`/`error` (unaffected by the nesting bug, since render_success
  // /render_error put those at the top level) and forwards the raw response
  // to onSuccess. LoginPage.handle2FASuccess ignores that payload entirely
  // and re-fetches the user via getCurrentUser() instead — so the nested
  // user/account/access_token fields twoFactorApi.verifyLogin never unwraps
  // are simply never read by the code that runs today.
  describe('two-factor authentication flow', () => {
    beforeEach(() => {
      mockApiPost.mockImplementation((url: string) => {
        if (url === '/auth/login') {
          return Promise.resolve({
            data: {
              success: true,
              data: { requires_2fa: true, verification_token: 'verify-token-abc' },
              message: 'Two-factor authentication required. Please provide your verification code.'
            }
          });
        }
        if (url === '/auth/verify-2fa') {
          // The real, un-unwrapped envelope: user/account/access_token/expires_at
          // sit under `data`, exactly as sessions_controller.rb's verify_2fa
          // action (~line 256) renders them.
          return Promise.resolve({
            data: {
              success: true,
              data: {
                user: { id: 'u1', email: 'test@example.com', name: 'Test User', permissions: [] },
                account: { id: 'a1', name: 'Acme' },
                access_token: 'fresh-access-token',
                expires_at: '2026-01-01T00:00:00Z'
              }
            }
          });
        }
        return Promise.reject(new Error(`unexpected POST ${url}`));
      });

      mockApiGet.mockImplementation((url: string) => {
        if (url === '/auth/me') {
          return Promise.resolve({
            data: {
              success: true,
              data: { user: { id: 'u1', email: 'test@example.com', name: 'Test User', permissions: [] } }
            }
          });
        }
        return Promise.reject(new Error(`unexpected GET ${url}`));
      });
    });

    it('finishes signing the user in after 2FA even though verifyLogin never unwraps its envelope', async () => {
      const { store } = renderWithProviders(<LoginPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      fireEvent.change(screen.getByLabelText('Email address'), { target: { value: 'test@example.com' } });
      fireEvent.change(screen.getByLabelText('Password'), { target: { value: 'correct-password' } });
      fireEvent.click(screen.getByRole('button', { name: /sign in/i }));

      await waitFor(() => {
        expect(screen.getByText('Two-Factor Authentication Required')).toBeInTheDocument();
      });
      // Confirms the requires_2fa/verification_token unwrap in authSlice's
      // `login` thunk (response.data.data) is what got us here.
      expect(mockApiPost).toHaveBeenCalledWith('/auth/login', expect.objectContaining({ email: 'test@example.com' }));

      fireEvent.change(screen.getByPlaceholderText(/Enter 6-digit code/i), { target: { value: '123456' } });
      fireEvent.click(screen.getByRole('button', { name: /Verify/i }));

      await waitFor(() => {
        expect(mockNavigate).toHaveBeenCalledWith('/app', { replace: true });
      });

      // The user in Redux state came from getCurrentUser's /auth/me response,
      // not from verifyLogin's (unread) nested payload — proving the login
      // flow completes correctly regardless of the /auth/verify-2fa unwrap gap.
      expect(store.getState().auth.user).toEqual(
        expect.objectContaining({ id: 'u1', email: 'test@example.com' })
      );
    });

    it('surfaces the server error message when 2FA verification fails', async () => {
      mockApiPost.mockImplementation((url: string) => {
        if (url === '/auth/login') {
          return Promise.resolve({
            data: {
              success: true,
              data: { requires_2fa: true, verification_token: 'verify-token-abc' }
            }
          });
        }
        if (url === '/auth/verify-2fa') {
          // render_error responds with a non-2xx status (sessions_controller.rb's
          // verify_2fa rescues StandardError with :unauthorized), so axios REJECTS
          // — it never resolves with {success:false}. Mirror that.
          return Promise.reject({
            response: { status: 401, data: { success: false, error: 'Authentication verification failed' } }
          });
        }
        return Promise.reject(new Error(`unexpected POST ${url}`));
      });

      renderWithProviders(<LoginPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      fireEvent.change(screen.getByLabelText('Email address'), { target: { value: 'test@example.com' } });
      fireEvent.change(screen.getByLabelText('Password'), { target: { value: 'correct-password' } });
      fireEvent.click(screen.getByRole('button', { name: /sign in/i }));

      await waitFor(() => {
        expect(screen.getByText('Two-Factor Authentication Required')).toBeInTheDocument();
      });

      fireEvent.change(screen.getByPlaceholderText(/Enter 6-digit code/i), { target: { value: '000000' } });
      fireEvent.click(screen.getByRole('button', { name: /Verify/i }));

      await waitFor(() => {
        expect(screen.getByText('Authentication verification failed')).toBeInTheDocument();
      });
      expect(mockNavigate).not.toHaveBeenCalled();
    });
  });
});
