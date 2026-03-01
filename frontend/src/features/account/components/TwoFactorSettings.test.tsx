import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { TwoFactorSettings } from './TwoFactorSettings';

// Mock the API
const mockGetStatus = jest.fn();
const mockDisable = jest.fn();
const mockGetBackupCodes = jest.fn();
const mockRegenerateBackupCodes = jest.fn();

jest.mock('@/shared/services/account/twoFactorApi', () => ({
  twoFactorApi: {
    getStatus: (...args: any[]) => mockGetStatus(...args),
    disable: (...args: any[]) => mockDisable(...args),
    getBackupCodes: (...args: any[]) => mockGetBackupCodes(...args),
    regenerateBackupCodes: (...args: any[]) => mockRegenerateBackupCodes(...args)
  }
}));

// Mock TwoFactorSetup component
jest.mock('@/features/account/auth/components/TwoFactorSetup', () => ({
  TwoFactorSetup: ({ onComplete, onCancel }: any) => (
    <div data-testid="two-factor-setup">
      <button onClick={onComplete}>Complete Setup</button>
      <button onClick={onCancel}>Cancel Setup</button>
    </div>
  )
}));

// Mock Modal
jest.mock('@/shared/components/ui/Modal', () => ({
  __esModule: true,
  default: ({ isOpen, onClose, title, children }: any) =>
    isOpen ? (
      <div data-testid="modal">
        <h2>{title}</h2>
        {children}
        <button onClick={onClose}>Close Modal</button>
      </div>
    ) : null
}));

// Mock clipboard
const mockWriteText = jest.fn();
Object.assign(navigator, {
  clipboard: {
    writeText: mockWriteText
  }
});

describe('TwoFactorSettings', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('loading state', () => {
    it('shows loading spinner while fetching status', () => {
      mockGetStatus.mockImplementation(() => new Promise(() => {})); // Never resolves

      render(<TwoFactorSettings />);

      expect(document.querySelector('.flex.items-center.justify-center')).toBeInTheDocument();
    });
  });

  describe('when 2FA is disabled', () => {
    beforeEach(() => {
      mockGetStatus.mockResolvedValue({
        success: true,
        two_factor_enabled: false,
        backup_codes_count: 0
      });
    });

    it('displays disabled status', async () => {
      render(<TwoFactorSettings />);

      await waitFor(() => {
        expect(screen.getByText('Disabled')).toBeInTheDocument();
      });
    });

    it('shows Enable 2FA button', async () => {
      render(<TwoFactorSettings />);

      await waitFor(() => {
        expect(screen.getByText('Enable 2FA')).toBeInTheDocument();
      });
    });

    it('does not show backup codes section', async () => {
      render(<TwoFactorSettings />);

      await waitFor(() => {
        expect(screen.getByText('Enable 2FA')).toBeInTheDocument();
      });

      expect(screen.queryByText('Backup Codes')).not.toBeInTheDocument();
    });

    it('opens setup modal when Enable 2FA clicked', async () => {
      render(<TwoFactorSettings />);

      await waitFor(() => {
        expect(screen.getByText('Enable 2FA')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Enable 2FA'));

      expect(screen.getByText('Enable Two-Factor Authentication')).toBeInTheDocument();
      expect(screen.getByTestId('two-factor-setup')).toBeInTheDocument();
    });

    it('closes setup modal on cancel', async () => {
      render(<TwoFactorSettings />);

      await waitFor(() => {
        expect(screen.getByText('Enable 2FA')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Enable 2FA'));
      fireEvent.click(screen.getByText('Cancel Setup'));

      expect(screen.queryByTestId('two-factor-setup')).not.toBeInTheDocument();
    });
  });

  describe('when 2FA is enabled', () => {
    beforeEach(() => {
      mockGetStatus.mockResolvedValue({
        success: true,
        two_factor_enabled: true,
        backup_codes_count: 8,
        enabled_at: '2025-01-15T10:00:00Z'
      });
    });

    it('displays enabled status', async () => {
      render(<TwoFactorSettings />);

      await waitFor(() => {
        // The text includes "Enabled" followed by the date
        expect(screen.getByText(/Enabled.*Enabled on/)).toBeInTheDocument();
      });
    });

    it('shows Disable button', async () => {
      render(<TwoFactorSettings />);

      await waitFor(() => {
        expect(screen.getByText('Disable')).toBeInTheDocument();
      });
    });

    it('shows backup codes section', async () => {
      render(<TwoFactorSettings />);

      await waitFor(() => {
        expect(screen.getByText('Backup Codes')).toBeInTheDocument();
      });
      expect(screen.getByText('You have 8 backup codes remaining')).toBeInTheDocument();
    });

    it('shows View Codes button', async () => {
      render(<TwoFactorSettings />);

      await waitFor(() => {
        expect(screen.getByText('View Codes')).toBeInTheDocument();
      });
    });

    it('shows Regenerate button', async () => {
      render(<TwoFactorSettings />);

      await waitFor(() => {
        expect(screen.getByText('Regenerate')).toBeInTheDocument();
      });
    });
  });

  describe('disable 2FA', () => {
    beforeEach(() => {
      mockGetStatus.mockResolvedValue({
        success: true,
        two_factor_enabled: true,
        backup_codes_count: 8
      });
    });

    it('opens confirmation modal when Disable clicked', async () => {
      render(<TwoFactorSettings />);

      await waitFor(() => {
        expect(screen.getByText('Disable')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Disable'));

      expect(screen.getByText('Disable Two-Factor Authentication')).toBeInTheDocument();
      expect(screen.getByText(/Are you sure you want to disable/)).toBeInTheDocument();
    });

    it('shows warning in disable modal', async () => {
      render(<TwoFactorSettings />);

      await waitFor(() => {
        expect(screen.getByText('Disable')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Disable'));

      expect(screen.getByText(/Disabling 2FA will remove the additional security layer/)).toBeInTheDocument();
    });

    it('calls disable API when confirmed', async () => {
      mockDisable.mockResolvedValue({ success: true });

      render(<TwoFactorSettings />);

      await waitFor(() => {
        expect(screen.getByText('Disable')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Disable'));
      fireEvent.click(screen.getByText('Disable 2FA'));

      await waitFor(() => {
        expect(mockDisable).toHaveBeenCalled();
      });
    });

    it('closes modal after successful disable', async () => {
      mockDisable.mockResolvedValue({ success: true });

      render(<TwoFactorSettings />);

      await waitFor(() => {
        expect(screen.getByText('Disable')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Disable'));
      fireEvent.click(screen.getByText('Disable 2FA'));

      await waitFor(() => {
        expect(screen.queryByText('Disable Two-Factor Authentication')).not.toBeInTheDocument();
      });
    });

    it('shows disabling state', async () => {
      mockDisable.mockImplementation(() => new Promise(() => {})); // Never resolves

      render(<TwoFactorSettings />);

      await waitFor(() => {
        expect(screen.getByText('Disable')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Disable'));
      fireEvent.click(screen.getByText('Disable 2FA'));

      expect(screen.getByText('Disabling...')).toBeInTheDocument();
    });
  });

  describe('backup codes', () => {
    beforeEach(() => {
      mockGetStatus.mockResolvedValue({
        success: true,
        two_factor_enabled: true,
        backup_codes_count: 8
      });
      mockGetBackupCodes.mockResolvedValue({
        success: true,
        backup_codes: ['ABC123', 'DEF456', 'GHI789']
      });
    });

    it('opens backup codes modal when View Codes clicked', async () => {
      render(<TwoFactorSettings />);

      await waitFor(() => {
        expect(screen.getByText('View Codes')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('View Codes'));

      await waitFor(() => {
        expect(screen.getByText('Backup Codes')).toBeInTheDocument();
      });
    });

    it('displays backup codes in modal', async () => {
      render(<TwoFactorSettings />);

      await waitFor(() => {
        expect(screen.getByText('View Codes')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('View Codes'));

      await waitFor(() => {
        expect(screen.getByText('ABC123')).toBeInTheDocument();
      });
      expect(screen.getByText('DEF456')).toBeInTheDocument();
      expect(screen.getByText('GHI789')).toBeInTheDocument();
    });

    it('copies backup codes to clipboard', async () => {
      render(<TwoFactorSettings />);

      await waitFor(() => {
        expect(screen.getByText('View Codes')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('View Codes'));

      await waitFor(() => {
        expect(screen.getByText('Copy Codes')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Copy Codes'));

      expect(mockWriteText).toHaveBeenCalledWith('ABC123\nDEF456\nGHI789');
    });

    it('regenerates backup codes', async () => {
      mockRegenerateBackupCodes.mockResolvedValue({
        success: true,
        backup_codes: ['NEW111', 'NEW222', 'NEW333']
      });

      render(<TwoFactorSettings />);

      await waitFor(() => {
        expect(screen.getByText('View Codes')).toBeInTheDocument();
      });

      // Click regenerate from the main section
      fireEvent.click(screen.getByText('Regenerate'));

      await waitFor(() => {
        expect(mockRegenerateBackupCodes).toHaveBeenCalled();
      });
    });

    it('shows regenerating state', async () => {
      mockRegenerateBackupCodes.mockImplementation(() => new Promise(() => {})); // Never resolves

      render(<TwoFactorSettings />);

      await waitFor(() => {
        expect(screen.getByText('Regenerate')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Regenerate'));

      expect(screen.getByText('Regenerating...')).toBeInTheDocument();
    });
  });

  describe('error handling', () => {
    it('shows error when status fetch fails', async () => {
      mockGetStatus.mockResolvedValue({ success: false });

      render(<TwoFactorSettings />);

      await waitFor(() => {
        expect(screen.getByText('Failed to load two-factor authentication status')).toBeInTheDocument();
      });
    });

    it('shows error when disable fails', async () => {
      mockGetStatus.mockResolvedValue({
        success: true,
        two_factor_enabled: true,
        backup_codes_count: 8
      });
      mockDisable.mockResolvedValue({
        success: false,
        error: 'Disable failed'
      });

      render(<TwoFactorSettings />);

      await waitFor(() => {
        expect(screen.getByText('Disable')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Disable'));
      fireEvent.click(screen.getByText('Disable 2FA'));

      await waitFor(() => {
        expect(screen.getByText('Disable failed')).toBeInTheDocument();
      });
    });

    it('shows error when backup codes fetch fails', async () => {
      mockGetStatus.mockResolvedValue({
        success: true,
        two_factor_enabled: true,
        backup_codes_count: 8
      });
      mockGetBackupCodes.mockResolvedValue({
        success: false,
        error: 'Failed to load'
      });

      render(<TwoFactorSettings />);

      await waitFor(() => {
        expect(screen.getByText('View Codes')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('View Codes'));

      await waitFor(() => {
        expect(screen.getByText('Failed to load')).toBeInTheDocument();
      });
    });
  });

  describe('header', () => {
    beforeEach(() => {
      mockGetStatus.mockResolvedValue({
        success: true,
        two_factor_enabled: false,
        backup_codes_count: 0
      });
    });

    it('displays title', async () => {
      render(<TwoFactorSettings />);

      await waitFor(() => {
        // Multiple elements have this text, so use getAllByText
        const titles = screen.getAllByText('Two-Factor Authentication');
        expect(titles.length).toBeGreaterThan(0);
      });
    });

    it('displays description', async () => {
      render(<TwoFactorSettings />);

      await waitFor(() => {
        expect(screen.getByText(/Add an extra layer of security/)).toBeInTheDocument();
      });
    });
  });
});
