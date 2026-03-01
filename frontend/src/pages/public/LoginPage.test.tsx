import { screen, fireEvent, waitFor } from '@testing-library/react';
import { LoginPage } from './LoginPage';
import { renderWithProviders, mockUnauthenticatedState } from '@/shared/utils/test-utils';

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

// No need to mock slices - let actual reducers handle state

describe('LoginPage', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

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

      renderWithProviders(<LoginPage />, {
        preloadedState: stateWithRegistration,
      });

      expect(screen.getByText('Create your account')).toBeInTheDocument();
      expect(screen.getByText('Create your account').closest('a')).toHaveAttribute('href', '/plans');
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

    it('links to plans page from create account', () => {
      const stateWithRegistration = {
        ...mockUnauthenticatedState,
        config: {
          ...mockUnauthenticatedState.config,
          registrationEnabled: true,
        },
      };

      renderWithProviders(<LoginPage />, {
        preloadedState: stateWithRegistration,
      });

      const createAccountLink = screen.getByText('Create your account').closest('a');
      expect(createAccountLink).toHaveAttribute('href', '/plans');
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
});
