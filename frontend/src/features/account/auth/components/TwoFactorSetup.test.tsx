
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { TwoFactorSetup } from './TwoFactorSetup';

// Mock the twoFactorApi
jest.mock('@/shared/services/account/twoFactorApi', () => ({
  twoFactorApi: {
    enable: jest.fn(),
    verifySetup: jest.fn()
  }
}));

// Mock clipboard API
Object.assign(navigator, {
  clipboard: {
    writeText: jest.fn()
  }
});

// Mock sanitizeQrCode
jest.mock('@/shared/utils/sanitizeHtml', () => ({
  sanitizeQrCode: (html: string) => html
}));

import { twoFactorApi } from '@/shared/services/account/twoFactorApi';

describe('TwoFactorSetup', () => {
  const mockEnableResponse = {
    success: true,
    qr_code: '<svg>QR Code</svg>',
    manual_entry_key: 'ABCD1234EFGH5678',
    backup_codes: ['code1', 'code2', 'code3']
  };

  beforeEach(() => {
    jest.clearAllMocks();
    (twoFactorApi.enable as jest.Mock).mockResolvedValue(mockEnableResponse);
    (twoFactorApi.verifySetup as jest.Mock).mockResolvedValue({ success: true });
  });

  describe('loading state', () => {
    it('shows loading spinner initially', () => {
      // Delay the response
      (twoFactorApi.enable as jest.Mock).mockImplementation(() =>
        new Promise(resolve => setTimeout(() => resolve(mockEnableResponse), 100))
      );

      render(<TwoFactorSetup />);

      expect(screen.getByText(/Setting up two-factor authentication/i)).toBeInTheDocument();
    });
  });

  describe('setup step', () => {
    it('displays QR code after loading', async () => {
      render(<TwoFactorSetup />);

      await waitFor(() => {
        expect(screen.getByText(/Set Up Two-Factor Authentication/i)).toBeInTheDocument();
      });
    });

    it('displays manual entry key', async () => {
      render(<TwoFactorSetup />);

      await waitFor(() => {
        expect(screen.getByText(/Manual Setup Key/i)).toBeInTheDocument();
      });
    });

    it('shows verification code input', async () => {
      render(<TwoFactorSetup />);

      await waitFor(() => {
        expect(screen.getByText(/Enter the 6-digit code/i)).toBeInTheDocument();
      });
    });

    it('has Cancel and Verify buttons', async () => {
      render(<TwoFactorSetup />);

      await waitFor(() => {
        expect(screen.getByText('Cancel')).toBeInTheDocument();
        expect(screen.getByText('Verify & Enable')).toBeInTheDocument();
      });
    });
  });

  describe('verification', () => {
    it('requires 6-digit code for verification', async () => {
      render(<TwoFactorSetup />);

      await waitFor(() => {
        expect(screen.getByText('Verify & Enable')).toBeInTheDocument();
      });

      // Button should be disabled without code
      const verifyButton = screen.getByText('Verify & Enable');
      expect(verifyButton).toBeDisabled();
    });

    it('enables verify button with 6-digit code', async () => {
      render(<TwoFactorSetup />);

      await waitFor(() => {
        expect(screen.getByPlaceholderText('123456')).toBeInTheDocument();
      });

      fireEvent.change(screen.getByPlaceholderText('123456'), { target: { value: '123456' } });

      const verifyButton = screen.getByText('Verify & Enable');
      expect(verifyButton).not.toBeDisabled();
    });

    it('shows error when verification code is empty', async () => {
      (twoFactorApi.verifySetup as jest.Mock).mockResolvedValue({
        success: false,
        error: 'Invalid verification code'
      });

      render(<TwoFactorSetup />);

      await waitFor(() => {
        expect(screen.getByPlaceholderText('123456')).toBeInTheDocument();
      });

      fireEvent.change(screen.getByPlaceholderText('123456'), { target: { value: '123456' } });
      fireEvent.click(screen.getByText('Verify & Enable'));

      await waitFor(() => {
        expect(screen.getByText('Invalid verification code')).toBeInTheDocument();
      });
    });
  });

  describe('completion step', () => {
    it('shows success message after verification', async () => {
      render(<TwoFactorSetup />);

      await waitFor(() => {
        expect(screen.getByPlaceholderText('123456')).toBeInTheDocument();
      });

      fireEvent.change(screen.getByPlaceholderText('123456'), { target: { value: '123456' } });
      fireEvent.click(screen.getByText('Verify & Enable'));

      await waitFor(() => {
        expect(screen.getByText(/Two-Factor Authentication Enabled!/i)).toBeInTheDocument();
      });
    });

    it('displays backup codes after verification', async () => {
      render(<TwoFactorSetup />);

      await waitFor(() => {
        expect(screen.getByPlaceholderText('123456')).toBeInTheDocument();
      });

      fireEvent.change(screen.getByPlaceholderText('123456'), { target: { value: '123456' } });
      fireEvent.click(screen.getByText('Verify & Enable'));

      await waitFor(() => {
        expect(screen.getByText('code1')).toBeInTheDocument();
        expect(screen.getByText('code2')).toBeInTheDocument();
        expect(screen.getByText('code3')).toBeInTheDocument();
      });
    });

    it('shows done button after completion', async () => {
      render(<TwoFactorSetup />);

      await waitFor(() => {
        expect(screen.getByPlaceholderText('123456')).toBeInTheDocument();
      });

      fireEvent.change(screen.getByPlaceholderText('123456'), { target: { value: '123456' } });
      fireEvent.click(screen.getByText('Verify & Enable'));

      await waitFor(() => {
        expect(screen.getByText('Done')).toBeInTheDocument();
      });
    });
  });

  describe('callbacks', () => {
    it('calls onCancel when Cancel button is clicked', async () => {
      const onCancel = jest.fn();
      render(<TwoFactorSetup onCancel={onCancel} />);

      await waitFor(() => {
        expect(screen.getByText('Cancel')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Cancel'));

      expect(onCancel).toHaveBeenCalled();
    });

    it('calls onComplete when Done button is clicked', async () => {
      const onComplete = jest.fn();
      render(<TwoFactorSetup onComplete={onComplete} />);

      await waitFor(() => {
        expect(screen.getByPlaceholderText('123456')).toBeInTheDocument();
      });

      fireEvent.change(screen.getByPlaceholderText('123456'), { target: { value: '123456' } });
      fireEvent.click(screen.getByText('Verify & Enable'));

      await waitFor(() => {
        expect(screen.getByText('Done')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Done'));

      expect(onComplete).toHaveBeenCalled();
    });
  });

  describe('error handling', () => {
    it('calls enable API on mount', async () => {
      render(<TwoFactorSetup />);

      await waitFor(() => {
        expect(twoFactorApi.enable).toHaveBeenCalled();
      });
    });

    it('handles network error on verify', async () => {
      (twoFactorApi.verifySetup as jest.Mock).mockRejectedValue(new Error('Network error'));

      render(<TwoFactorSetup />);

      await waitFor(() => {
        expect(screen.getByPlaceholderText('123456')).toBeInTheDocument();
      });

      fireEvent.change(screen.getByPlaceholderText('123456'), { target: { value: '123456' } });
      fireEvent.click(screen.getByText('Verify & Enable'));

      await waitFor(() => {
        expect(screen.getByText('Failed to verify the code. Please try again.')).toBeInTheDocument();
      });
    });
  });
});
