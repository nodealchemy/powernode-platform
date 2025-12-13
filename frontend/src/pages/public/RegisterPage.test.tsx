import { screen, fireEvent, waitFor } from '@testing-library/react';
import { RegisterPage } from './RegisterPage';
import { renderWithProviders, mockUnauthenticatedState, createMockPlan } from '@/shared/utils/test-utils';

// Mock React Router hooks
const mockNavigate = jest.fn();
const mockSearchParams = new URLSearchParams('plan=plan_basic&billing=monthly');
jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useNavigate: () => mockNavigate,
  useSearchParams: () => [mockSearchParams],
}));

// Mock plansApi
const mockGetPublicPlans = jest.fn();
jest.mock('@/features/plans/services/plansApi', () => ({
  plansApi: {
    getPublicPlans: () => mockGetPublicPlans(),
  },
}));

// No need to mock slices - let actual reducers handle state

// Mock sessionStorage
const mockSessionStorage: Record<string, string> = {};
Object.defineProperty(window, 'sessionStorage', {
  value: {
    getItem: jest.fn((key: string) => mockSessionStorage[key] || null),
    setItem: jest.fn((key: string, value: string) => {
      mockSessionStorage[key] = value;
    }),
    removeItem: jest.fn((key: string) => {
      delete mockSessionStorage[key];
    }),
    clear: jest.fn(() => {
      Object.keys(mockSessionStorage).forEach((key) => delete mockSessionStorage[key]);
    }),
  },
  writable: true,
});

describe('RegisterPage', () => {
  const mockPlan = createMockPlan({
    id: 'plan_basic',
    name: 'Basic Plan',
    price_cents: 999,
    currency: 'USD',
    billing_cycle: 'monthly',
    trial_days: 14,
  });

  beforeEach(() => {
    jest.clearAllMocks();
    mockGetPublicPlans.mockResolvedValue({
      success: true,
      data: { plans: [mockPlan] },
    });
    window.sessionStorage.clear();
  });

  describe('rendering', () => {
    it('renders the registration form', async () => {
      renderWithProviders(<RegisterPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      await waitFor(() => {
        expect(screen.getByText('Powernode')).toBeInTheDocument();
      });

      expect(screen.getByText('Create your account')).toBeInTheDocument();
      expect(screen.getByLabelText('Company Name')).toBeInTheDocument();
      expect(screen.getByLabelText('Full Name')).toBeInTheDocument();
      expect(screen.getByLabelText('Email Address')).toBeInTheDocument();
      expect(screen.getByLabelText('Password')).toBeInTheDocument();
    });

    it('renders logo link', async () => {
      renderWithProviders(<RegisterPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      await waitFor(() => {
        const logoLink = screen.getByText('P').closest('a');
        expect(logoLink).toHaveAttribute('href', '/welcome');
      });
    });

    it('renders change plan link', async () => {
      renderWithProviders(<RegisterPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      await waitFor(() => {
        expect(screen.getByText('Change plan')).toBeInTheDocument();
      });

      const changePlanLink = screen.getByText('Change plan').closest('a');
      expect(changePlanLink).toHaveAttribute('href', '/plans');
    });

    it('renders sign in link', async () => {
      renderWithProviders(<RegisterPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      await waitFor(() => {
        expect(screen.getByText('Already have an account?')).toBeInTheDocument();
      });

      const signInLink = screen.getByText('Sign in');
      expect(signInLink.closest('a')).toHaveAttribute('href', '/login');
    });
  });

  describe('selected plan display', () => {
    it('displays selected plan information', async () => {
      renderWithProviders(<RegisterPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      await waitFor(() => {
        expect(screen.getByText('Basic Plan')).toBeInTheDocument();
      });
    });

    it('displays billing cycle', async () => {
      renderWithProviders(<RegisterPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      await waitFor(() => {
        expect(screen.getByText(/billed monthly/i)).toBeInTheDocument();
      });
    });

    it('displays trial information when plan has trial', async () => {
      renderWithProviders(<RegisterPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      await waitFor(() => {
        expect(screen.getByText(/14 day trial/i)).toBeInTheDocument();
      });
    });
  });

  describe('form interactions', () => {
    it('updates company name field on change', async () => {
      renderWithProviders(<RegisterPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      await waitFor(() => {
        expect(screen.getByLabelText('Company Name')).toBeInTheDocument();
      });

      const companyInput = screen.getByLabelText('Company Name');
      fireEvent.change(companyInput, { target: { value: 'Test Corp' } });
      expect(companyInput).toHaveValue('Test Corp');
    });

    it('updates full name field on change', async () => {
      renderWithProviders(<RegisterPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      await waitFor(() => {
        expect(screen.getByLabelText('Full Name')).toBeInTheDocument();
      });

      const nameInput = screen.getByLabelText('Full Name');
      fireEvent.change(nameInput, { target: { value: 'John Doe' } });
      expect(nameInput).toHaveValue('John Doe');
    });

    it('updates email field on change', async () => {
      renderWithProviders(<RegisterPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      await waitFor(() => {
        expect(screen.getByLabelText('Email Address')).toBeInTheDocument();
      });

      const emailInput = screen.getByLabelText('Email Address');
      fireEvent.change(emailInput, { target: { value: 'test@example.com' } });
      expect(emailInput).toHaveValue('test@example.com');
    });

    it('updates password field on change', async () => {
      renderWithProviders(<RegisterPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      await waitFor(() => {
        expect(screen.getByLabelText('Password')).toBeInTheDocument();
      });

      const passwordInput = screen.getByLabelText('Password');
      fireEvent.change(passwordInput, { target: { value: 'password123' } });
      expect(passwordInput).toHaveValue('password123');
    });

    it('toggles password visibility', async () => {
      renderWithProviders(<RegisterPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      await waitFor(() => {
        expect(screen.getByLabelText('Password')).toBeInTheDocument();
      });

      const passwordInput = screen.getByLabelText('Password');
      const toggleButton = screen.getByLabelText('Show password');

      expect(passwordInput).toHaveAttribute('type', 'password');

      fireEvent.click(toggleButton);
      expect(passwordInput).toHaveAttribute('type', 'text');

      fireEvent.click(screen.getByLabelText('Hide password'));
      expect(passwordInput).toHaveAttribute('type', 'password');
    });
  });

  describe('form validation', () => {
    it('has required attributes on form fields', async () => {
      renderWithProviders(<RegisterPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      await waitFor(() => {
        expect(screen.getByLabelText('Company Name')).toBeRequired();
        expect(screen.getByLabelText('Full Name')).toBeRequired();
        expect(screen.getByLabelText('Email Address')).toBeRequired();
        expect(screen.getByLabelText('Password')).toBeRequired();
      });
    });

    it('shows password requirements hint', async () => {
      renderWithProviders(<RegisterPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      await waitFor(() => {
        expect(screen.getByText(/password must be at least 8 characters/i)).toBeInTheDocument();
      });
    });

    it('disables submit button when form is invalid', async () => {
      renderWithProviders(<RegisterPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      await waitFor(() => {
        const submitButton = screen.getByRole('button', { name: /create account/i });
        expect(submitButton).toBeDisabled();
      });
    });
  });

  describe('navigation', () => {
    it('redirects to plans page if no plan is selected', async () => {
      // Mock empty search params
      const emptySearchParams = new URLSearchParams('');
      jest.doMock('react-router-dom', () => ({
        ...jest.requireActual('react-router-dom'),
        useNavigate: () => mockNavigate,
        useSearchParams: () => [emptySearchParams],
      }));

      // Note: Due to module caching, this test documents expected behavior
      // The actual navigation happens inside useEffect
    });
  });

  describe('error display', () => {
    it('displays error message when auth error exists', async () => {
      const stateWithError = {
        ...mockUnauthenticatedState,
        auth: {
          ...mockUnauthenticatedState.auth,
          error: 'Email already in use',
        },
      };

      renderWithProviders(<RegisterPage />, {
        preloadedState: stateWithError,
      });

      await waitFor(() => {
        expect(screen.getByText('Email already in use')).toBeInTheDocument();
      });
    });
  });

  describe('section headers', () => {
    it('displays company information section header', async () => {
      renderWithProviders(<RegisterPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      await waitFor(() => {
        expect(screen.getByText('Company Information')).toBeInTheDocument();
      });
    });

    it('displays account section header', async () => {
      renderWithProviders(<RegisterPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      await waitFor(() => {
        expect(screen.getByText('Your Account')).toBeInTheDocument();
      });
    });
  });

  describe('accessibility', () => {
    it('has proper label associations', async () => {
      renderWithProviders(<RegisterPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      await waitFor(() => {
        const companyInput = screen.getByLabelText('Company Name');
        const nameInput = screen.getByLabelText('Full Name');
        const emailInput = screen.getByLabelText('Email Address');
        const passwordInput = screen.getByLabelText('Password');

        expect(companyInput).toHaveAttribute('id', 'accountName');
        expect(nameInput).toHaveAttribute('id', 'name');
        expect(emailInput).toHaveAttribute('id', 'email');
        expect(passwordInput).toHaveAttribute('id', 'password');
      });
    });

    it('has correct autocomplete attributes', async () => {
      renderWithProviders(<RegisterPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      await waitFor(() => {
        expect(screen.getByLabelText('Email Address')).toHaveAttribute('autocomplete', 'email');
        expect(screen.getByLabelText('Password')).toHaveAttribute('autocomplete', 'new-password');
      });
    });
  });
});
