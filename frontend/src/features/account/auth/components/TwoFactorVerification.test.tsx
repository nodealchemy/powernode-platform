
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { TwoFactorVerification } from './TwoFactorVerification';

// Mock the twoFactorApi
jest.mock('@/shared/services/account/twoFactorApi', () => ({
  twoFactorApi: {
    verifyLogin: jest.fn()
  }
}));

import { twoFactorApi } from '@/shared/services/account/twoFactorApi';

describe('TwoFactorVerification', () => {
  const defaultProps = {
    verificationToken: 'test-token',
    onSuccess: jest.fn(),
    onError: jest.fn()
  };

  beforeEach(() => {
    jest.clearAllMocks();
    (twoFactorApi.verifyLogin as jest.Mock).mockResolvedValue({ success: true });
  });

  describe('rendering', () => {
    it('renders verification header', () => {
      render(<TwoFactorVerification {...defaultProps} />);

      expect(screen.getByText('Two-Factor Authentication Required')).toBeInTheDocument();
    });

    it('renders verification code input', () => {
      render(<TwoFactorVerification {...defaultProps} />);

      expect(screen.getByPlaceholderText(/Enter 6-digit code/i)).toBeInTheDocument();
    });

    it('renders verify button', () => {
      render(<TwoFactorVerification {...defaultProps} />);

      expect(screen.getByRole('button', { name: /Verify/i })).toBeInTheDocument();
    });

    it('renders help text', () => {
      render(<TwoFactorVerification {...defaultProps} />);

      expect(screen.getByText(/Enter the 6-digit code/i)).toBeInTheDocument();
    });

    it('renders cancel button when onCancel provided', () => {
      render(<TwoFactorVerification {...defaultProps} onCancel={jest.fn()} />);

      expect(screen.getByText('Cancel')).toBeInTheDocument();
    });

    it('does not render cancel button when onCancel not provided', () => {
      render(<TwoFactorVerification {...defaultProps} />);

      expect(screen.queryByText('Cancel')).not.toBeInTheDocument();
    });
  });

  describe('code input', () => {
    it('accepts only digits', () => {
      render(<TwoFactorVerification {...defaultProps} />);

      const input = screen.getByPlaceholderText(/Enter 6-digit code/i);
      fireEvent.change(input, { target: { value: 'abc123def' } });

      expect(input).toHaveValue('123');
    });

    it('limits input to 8 characters', () => {
      render(<TwoFactorVerification {...defaultProps} />);

      const input = screen.getByPlaceholderText(/Enter 6-digit code/i);
      // First set a valid 8 character value
      fireEvent.change(input, { target: { value: '12345678' } });
      expect(input).toHaveValue('12345678');

      // Then try to add more - should reject and keep previous value
      fireEvent.change(input, { target: { value: '123456789' } });
      expect(input).toHaveValue('12345678');
    });

    it('clears error when code changes', async () => {
      render(<TwoFactorVerification {...defaultProps} />);

      // Enter invalid code length first
      const input = screen.getByPlaceholderText(/Enter 6-digit code/i);
      fireEvent.change(input, { target: { value: '12345' } });

      // Submit form to trigger error
      const form = input.closest('form');
      fireEvent.submit(form!);

      await waitFor(() => {
        expect(screen.getByText(/valid 6-digit code/i)).toBeInTheDocument();
      });

      // Type more to clear error
      fireEvent.change(input, { target: { value: '1' } });

      expect(screen.queryByText(/valid 6-digit code/i)).not.toBeInTheDocument();
    });
  });

  describe('validation', () => {
    it('verify button is disabled when code is empty', () => {
      render(<TwoFactorVerification {...defaultProps} />);

      expect(screen.getByRole('button', { name: /Verify/i })).toBeDisabled();
    });

    it('shows error for invalid code length', async () => {
      render(<TwoFactorVerification {...defaultProps} />);

      const input = screen.getByPlaceholderText(/Enter 6-digit code/i);
      fireEvent.change(input, { target: { value: '12345' } }); // 5 digits

      // Submit form directly (button is enabled with any non-empty value)
      const form = input.closest('form');
      fireEvent.submit(form!);

      await waitFor(() => {
        expect(screen.getByText(/valid 6-digit code or 8-digit backup code/i)).toBeInTheDocument();
      });
    });

    it('accepts 6-digit code', async () => {
      render(<TwoFactorVerification {...defaultProps} />);

      const input = screen.getByPlaceholderText(/Enter 6-digit code/i);
      fireEvent.change(input, { target: { value: '123456' } });

      fireEvent.click(screen.getByRole('button', { name: /Verify/i }));

      await waitFor(() => {
        expect(screen.queryByText(/valid 6-digit code/i)).not.toBeInTheDocument();
      });
    });

    it('accepts 8-digit backup code', async () => {
      render(<TwoFactorVerification {...defaultProps} />);

      const input = screen.getByPlaceholderText(/Enter 6-digit code/i);
      fireEvent.change(input, { target: { value: '12345678' } });

      fireEvent.click(screen.getByRole('button', { name: /Verify/i }));

      await waitFor(() => {
        expect(screen.queryByText(/valid 6-digit code/i)).not.toBeInTheDocument();
      });
    });
  });

  describe('verification', () => {
    it('calls API with token and code', async () => {
      render(<TwoFactorVerification {...defaultProps} />);

      const input = screen.getByPlaceholderText(/Enter 6-digit code/i);
      fireEvent.change(input, { target: { value: '123456' } });

      fireEvent.click(screen.getByRole('button', { name: /Verify/i }));

      await waitFor(() => {
        expect(twoFactorApi.verifyLogin).toHaveBeenCalledWith('test-token', '123456');
      });
    });

    it('calls onSuccess on successful verification', async () => {
      const mockResponse = { success: true, access_token: 'token' };
      (twoFactorApi.verifyLogin as jest.Mock).mockResolvedValue(mockResponse);

      render(<TwoFactorVerification {...defaultProps} />);

      const input = screen.getByPlaceholderText(/Enter 6-digit code/i);
      fireEvent.change(input, { target: { value: '123456' } });

      fireEvent.click(screen.getByRole('button', { name: /Verify/i }));

      await waitFor(() => {
        expect(defaultProps.onSuccess).toHaveBeenCalledWith(mockResponse);
      });
    });

    it('shows error on verification failure', async () => {
      (twoFactorApi.verifyLogin as jest.Mock).mockResolvedValue({
        success: false,
        error: 'Invalid verification code'
      });

      render(<TwoFactorVerification {...defaultProps} />);

      const input = screen.getByPlaceholderText(/Enter 6-digit code/i);
      fireEvent.change(input, { target: { value: '123456' } });

      fireEvent.click(screen.getByRole('button', { name: /Verify/i }));

      await waitFor(() => {
        expect(screen.getByText('Invalid verification code')).toBeInTheDocument();
      });
    });

    it('shows loading state during verification', async () => {
      (twoFactorApi.verifyLogin as jest.Mock).mockImplementation(() =>
        new Promise(resolve => setTimeout(() => resolve({ success: true }), 100))
      );

      render(<TwoFactorVerification {...defaultProps} />);

      const input = screen.getByPlaceholderText(/Enter 6-digit code/i);
      fireEvent.change(input, { target: { value: '123456' } });

      fireEvent.click(screen.getByRole('button', { name: /Verify/i }));

      expect(screen.getByText('Verifying...')).toBeInTheDocument();
    });

    it('disables form during verification', async () => {
      (twoFactorApi.verifyLogin as jest.Mock).mockImplementation(() =>
        new Promise(resolve => setTimeout(() => resolve({ success: true }), 100))
      );

      render(<TwoFactorVerification {...defaultProps} />);

      const input = screen.getByPlaceholderText(/Enter 6-digit code/i);
      fireEvent.change(input, { target: { value: '123456' } });

      fireEvent.click(screen.getByRole('button', { name: /Verify/i }));

      expect(input).toBeDisabled();
    });
  });

  describe('error handling', () => {
    it('handles network error', async () => {
      (twoFactorApi.verifyLogin as jest.Mock).mockRejectedValue(new Error('Network error'));

      render(<TwoFactorVerification {...defaultProps} />);

      const input = screen.getByPlaceholderText(/Enter 6-digit code/i);
      fireEvent.change(input, { target: { value: '123456' } });

      fireEvent.click(screen.getByRole('button', { name: /Verify/i }));

      await waitFor(() => {
        expect(screen.getByText('Failed to verify code. Please try again.')).toBeInTheDocument();
      });
    });

    it('calls onError on network failure', async () => {
      (twoFactorApi.verifyLogin as jest.Mock).mockRejectedValue(new Error('Network error'));

      render(<TwoFactorVerification {...defaultProps} />);

      const input = screen.getByPlaceholderText(/Enter 6-digit code/i);
      fireEvent.change(input, { target: { value: '123456' } });

      fireEvent.click(screen.getByRole('button', { name: /Verify/i }));

      await waitFor(() => {
        expect(defaultProps.onError).toHaveBeenCalledWith('Failed to verify code. Please try again.');
      });
    });
  });

  describe('cancel button', () => {
    it('calls onCancel when clicked', () => {
      const onCancel = jest.fn();
      render(<TwoFactorVerification {...defaultProps} onCancel={onCancel} />);

      fireEvent.click(screen.getByText('Cancel'));

      expect(onCancel).toHaveBeenCalled();
    });
  });
});
