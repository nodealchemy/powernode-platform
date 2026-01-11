import { screen, fireEvent, waitFor } from '@testing-library/react';
import { ForgotPasswordPage } from './ForgotPasswordPage';
import { renderWithProviders, mockUnauthenticatedState } from '@/shared/utils/test-utils';

// Mock React Router hooks
const mockNavigate = jest.fn();

jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useNavigate: () => mockNavigate,
}));

// Mock authApi
const mockForgotPassword = jest.fn();
jest.mock('@/features/account/auth/services/authAPI', () => ({
  authApi: {
    forgotPassword: (...args: unknown[]) => mockForgotPassword(...args),
  },
}));

// No need to mock slices - let actual reducers handle state

describe('ForgotPasswordPage', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockForgotPassword.mockResolvedValue({});
  });

  describe('rendering', () => {
    it('renders the forgot password form', () => {
      renderWithProviders(<ForgotPasswordPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      expect(screen.getByText('Reset your password')).toBeInTheDocument();
      expect(screen.getByLabelText('Email address')).toBeInTheDocument();
      expect(screen.getByRole('button', { name: /send reset email/i })).toBeInTheDocument();
    });

    it('renders logo link', () => {
      renderWithProviders(<ForgotPasswordPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      const logoLink = screen.getByText('P').closest('a');
      expect(logoLink).toHaveAttribute('href', '/welcome');
    });

    it('renders sign in link', () => {
      renderWithProviders(<ForgotPasswordPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      expect(screen.getByText('Remember your password?')).toBeInTheDocument();
      const signInLink = screen.getByText('Sign in');
      expect(signInLink.closest('a')).toHaveAttribute('href', '/login');
    });
  });

  describe('form interactions', () => {
    it('updates email field on change', () => {
      renderWithProviders(<ForgotPasswordPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      const emailInput = screen.getByLabelText('Email address');
      fireEvent.change(emailInput, { target: { value: 'test@example.com' } });
      expect(emailInput).toHaveValue('test@example.com');
    });

    it('has required attribute on email field', () => {
      renderWithProviders(<ForgotPasswordPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      expect(screen.getByLabelText('Email address')).toBeRequired();
    });

    it('has correct autocomplete attribute', () => {
      renderWithProviders(<ForgotPasswordPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      expect(screen.getByLabelText('Email address')).toHaveAttribute('autocomplete', 'email');
    });
  });

  describe('form submission', () => {
    it('calls forgotPassword API on submit', async () => {
      renderWithProviders(<ForgotPasswordPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      const emailInput = screen.getByLabelText('Email address');
      fireEvent.change(emailInput, { target: { value: 'test@example.com' } });

      const submitButton = screen.getByRole('button', { name: /send reset email/i });
      fireEvent.click(submitButton);

      await waitFor(() => {
        expect(mockForgotPassword).toHaveBeenCalledWith('test@example.com');
      });
    });

    it('shows loading state during submission', async () => {
      mockForgotPassword.mockImplementation(() => new Promise(resolve => setTimeout(resolve, 100)));

      renderWithProviders(<ForgotPasswordPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      const emailInput = screen.getByLabelText('Email address');
      fireEvent.change(emailInput, { target: { value: 'test@example.com' } });

      const submitButton = screen.getByRole('button', { name: /send reset email/i });
      fireEvent.click(submitButton);

      await waitFor(() => {
        expect(screen.getByText(/sending email/i)).toBeInTheDocument();
      });
    });

    it('disables button during loading', async () => {
      mockForgotPassword.mockImplementation(() => new Promise(resolve => setTimeout(resolve, 100)));

      renderWithProviders(<ForgotPasswordPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      const emailInput = screen.getByLabelText('Email address');
      fireEvent.change(emailInput, { target: { value: 'test@example.com' } });

      const submitButton = screen.getByRole('button', { name: /send reset email/i });
      fireEvent.click(submitButton);

      await waitFor(() => {
        expect(submitButton).toBeDisabled();
      });
    });
  });

  describe('success state', () => {
    it('shows success message after submission', async () => {
      renderWithProviders(<ForgotPasswordPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      const emailInput = screen.getByLabelText('Email address');
      fireEvent.change(emailInput, { target: { value: 'test@example.com' } });

      const submitButton = screen.getByRole('button', { name: /send reset email/i });
      fireEvent.click(submitButton);

      await waitFor(() => {
        expect(screen.getByText('Email sent!')).toBeInTheDocument();
      });
    });

    it('displays the submitted email in success message', async () => {
      renderWithProviders(<ForgotPasswordPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      const emailInput = screen.getByLabelText('Email address');
      fireEvent.change(emailInput, { target: { value: 'test@example.com' } });

      const submitButton = screen.getByRole('button', { name: /send reset email/i });
      fireEvent.click(submitButton);

      await waitFor(() => {
        expect(screen.getByText('test@example.com')).toBeInTheDocument();
      });
    });

    it('hides the form after successful submission', async () => {
      renderWithProviders(<ForgotPasswordPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      const emailInput = screen.getByLabelText('Email address');
      fireEvent.change(emailInput, { target: { value: 'test@example.com' } });

      const submitButton = screen.getByRole('button', { name: /send reset email/i });
      fireEvent.click(submitButton);

      await waitFor(() => {
        expect(screen.queryByLabelText('Email address')).not.toBeInTheDocument();
        expect(screen.queryByRole('button', { name: /send reset email/i })).not.toBeInTheDocument();
      });
    });
  });

  describe('error handling', () => {
    it('handles API errors gracefully', async () => {
      mockForgotPassword.mockRejectedValue(new Error('Network error'));

      renderWithProviders(<ForgotPasswordPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      const emailInput = screen.getByLabelText('Email address');
      fireEvent.change(emailInput, { target: { value: 'test@example.com' } });

      const submitButton = screen.getByRole('button', { name: /send reset email/i });
      fireEvent.click(submitButton);

      await waitFor(() => {
        // Button should be re-enabled after error
        expect(submitButton).not.toBeDisabled();
      });

      // Form should still be visible after error (not showing success)
      expect(screen.getByLabelText('Email address')).toBeInTheDocument();
    });
  });

  describe('accessibility', () => {
    it('has proper label association', () => {
      renderWithProviders(<ForgotPasswordPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      const emailInput = screen.getByLabelText('Email address');
      expect(emailInput).toHaveAttribute('id', 'email');
    });

    it('has email input type for validation', () => {
      renderWithProviders(<ForgotPasswordPage />, {
        preloadedState: mockUnauthenticatedState,
      });

      const emailInput = screen.getByLabelText('Email address');
      expect(emailInput).toHaveAttribute('type', 'email');
    });
  });
});
