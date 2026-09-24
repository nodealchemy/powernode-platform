import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { TwoFactorSettings } from './TwoFactorSettings';

// Mock ONE LAYER BELOW twoFactorApi — the raw api client — with the real
// {success, data} envelope, so these tests exercise twoFactorApi's own
// unwrap logic instead of assuming it away (IMP-99e8e4701150).
const mockGet = jest.fn();
const mockPost = jest.fn();
const mockDelete = jest.fn();

jest.mock('@/shared/services/api', () => ({
  api: {
    get: (...args: unknown[]) => mockGet(...args),
    post: (...args: unknown[]) => mockPost(...args),
    delete: (...args: unknown[]) => mockDelete(...args)
  }
}));

function envelope(data?: Record<string, unknown>, error?: string, success = true) {
  return {
    data: {
      success,
      ...(data ? { data } : {}),
      ...(error ? { error } : {})
    }
  };
}

// Mock TwoFactorSetup component — its own enable/verify_setup flow is covered
// by TwoFactorSetup.test.tsx; here we only need its onComplete/onCancel wiring.
jest.mock('@/features/account/auth/components/TwoFactorSetup', () => ({
  TwoFactorSetup: ({ onComplete, onCancel }: { onComplete: () => void; onCancel: () => void }) => (
    <div data-testid="two-factor-setup">
      <button onClick={onComplete}>Complete Setup</button>
      <button onClick={onCancel}>Cancel Setup</button>
    </div>
  )
}));

// Mock Modal
jest.mock('@/shared/components/ui/Modal', () => ({
  __esModule: true,
  default: ({ isOpen, onClose, title, children }: { isOpen: boolean; onClose: () => void; title?: string; children?: React.ReactNode }) =>
    isOpen ? (
      <div data-testid="modal">
        <h2>{title}</h2>
        {children}
        <button onClick={onClose}>Close Modal</button>
      </div>
    ) : null
}));

// Mock clipboard and the download helper's Blob/URL usage (unavailable in jsdom)
const mockWriteText = jest.fn();
Object.assign(navigator, {
  clipboard: {
    writeText: mockWriteText
  }
});
describe('TwoFactorSettings', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    // jest.config.js sets resetMocks: true, which wipes a mock's
    // IMPLEMENTATION (not just its call history) before every test — a
    // beforeAll assignment here would only ever take effect for the first
    // example. Must be (re)assigned per-test, after that reset has run.
    URL.createObjectURL = jest.fn(() => 'blob:mock');
    URL.revokeObjectURL = jest.fn();
  });

  describe('loading state', () => {
    it('shows loading spinner while fetching status', () => {
      mockGet.mockImplementation(() => new Promise(() => {})); // Never resolves

      render(<TwoFactorSettings />);

      expect(document.querySelector('.flex.items-center.justify-center')).toBeInTheDocument();
    });
  });

  describe('when 2FA is disabled', () => {
    beforeEach(() => {
      mockGet.mockResolvedValue(envelope({ two_factor_enabled: false, backup_codes_count: 0 }));
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

    // IMP-99e8e4701150 review N3 — closing the setup modal via its own
    // close affordance (X / backdrop — "Close Modal" in the mocked Modal
    // above), not just the Done button's onComplete, must refresh status:
    // otherwise a user who verifies successfully and then closes out before
    // clicking Done sees a stale "Disabled" card.
    it('refreshes status when the setup modal is closed via its own close button', async () => {
      render(<TwoFactorSettings />);

      await waitFor(() => {
        expect(screen.getByText('Enable 2FA')).toBeInTheDocument();
      });
      expect(mockGet).toHaveBeenCalledTimes(1);

      fireEvent.click(screen.getByText('Enable 2FA'));
      fireEvent.click(screen.getByText('Close Modal'));

      await waitFor(() => {
        expect(mockGet).toHaveBeenCalledTimes(2);
      });
    });
  });

  describe('when 2FA is enabled', () => {
    beforeEach(() => {
      mockGet.mockResolvedValue(envelope({
        two_factor_enabled: true,
        backup_codes_count: 8,
        enabled_at: '2025-01-15T10:00:00Z'
      }));
    });

    it('displays enabled status', async () => {
      render(<TwoFactorSettings />);

      await waitFor(() => {
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

    it('does not show a View Codes action (codes are never re-fetchable)', async () => {
      render(<TwoFactorSettings />);

      await waitFor(() => {
        expect(screen.getByText('Backup Codes')).toBeInTheDocument();
      });

      expect(screen.queryByText('View Codes')).not.toBeInTheDocument();
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
      mockGet.mockResolvedValue(envelope({ two_factor_enabled: true, backup_codes_count: 8 }));
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

    it('refuses to submit without a code', async () => {
      render(<TwoFactorSettings />);

      await waitFor(() => {
        expect(screen.getByText('Disable')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Disable'));
      fireEvent.click(screen.getByText('Disable 2FA'));

      await waitFor(() => {
        expect(screen.getByText(/an unused backup code/)).toBeInTheDocument();
      });
      expect(mockDelete).not.toHaveBeenCalled();
    });

    it('calls disable API with the entered code when confirmed', async () => {
      mockDelete.mockResolvedValue(envelope());

      render(<TwoFactorSettings />);

      await waitFor(() => {
        expect(screen.getByText('Disable')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Disable'));
      fireEvent.change(screen.getByPlaceholderText('123456'), { target: { value: '654321' } });
      fireEvent.click(screen.getByText('Disable 2FA'));

      await waitFor(() => {
        expect(mockDelete).toHaveBeenCalledWith('/two_factor/disable', { data: { code: '654321' } });
      });
    });

    it('closes modal after successful disable', async () => {
      mockDelete.mockResolvedValue(envelope());

      render(<TwoFactorSettings />);

      await waitFor(() => {
        expect(screen.getByText('Disable')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Disable'));
      fireEvent.change(screen.getByPlaceholderText('123456'), { target: { value: '654321' } });
      fireEvent.click(screen.getByText('Disable 2FA'));

      await waitFor(() => {
        expect(screen.queryByText('Disable Two-Factor Authentication')).not.toBeInTheDocument();
      });
    });

    it('shows disabling state', async () => {
      mockDelete.mockImplementation(() => new Promise(() => {})); // Never resolves

      render(<TwoFactorSettings />);

      await waitFor(() => {
        expect(screen.getByText('Disable')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Disable'));
      fireEvent.change(screen.getByPlaceholderText('123456'), { target: { value: '654321' } });
      fireEvent.click(screen.getByText('Disable 2FA'));

      expect(screen.getByText('Disabling...')).toBeInTheDocument();
    });

    it('shows a server error when the code is rejected', async () => {
      // render_error responds with a non-2xx status (422 here — a wrong
      // re-auth code, never 401; review H2), so axios REJECTS — it never
      // resolves with {success:false}. mockResolvedValue({success:false})
      // describes a response shape disable() cannot actually receive.
      mockDelete.mockRejectedValue({
        response: {
          status: 422,
          data: { success: false, error: 'A valid authentication code or backup code is required to disable two-factor authentication' }
        }
      });

      render(<TwoFactorSettings />);

      await waitFor(() => {
        expect(screen.getByText('Disable')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Disable'));
      fireEvent.change(screen.getByPlaceholderText('123456'), { target: { value: '000000' } });
      fireEvent.click(screen.getByText('Disable 2FA'));

      await waitFor(() => {
        expect(screen.getByText(/A valid authentication code or backup code is required/)).toBeInTheDocument();
      });
    });
  });

  describe('regenerate backup codes', () => {
    beforeEach(() => {
      mockGet.mockResolvedValue(envelope({ two_factor_enabled: true, backup_codes_count: 8 }));
    });

    it('opens a confirmation modal requiring a code', async () => {
      render(<TwoFactorSettings />);

      await waitFor(() => {
        expect(screen.getByText('Regenerate')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Regenerate'));

      expect(screen.getByText('Regenerate Backup Codes')).toBeInTheDocument();
      expect(mockPost).not.toHaveBeenCalled();
    });

    it('refuses to submit without a code', async () => {
      render(<TwoFactorSettings />);

      await waitFor(() => {
        expect(screen.getByText('Regenerate')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Regenerate'));
      fireEvent.click(screen.getAllByText('Regenerate')[1]);

      await waitFor(() => {
        expect(screen.getByText(/an unused backup code/)).toBeInTheDocument();
      });
      expect(mockPost).not.toHaveBeenCalled();
    });

    it('regenerates with a valid code and shows the new codes once', async () => {
      mockPost.mockResolvedValue(envelope({ backup_codes: ['NEW111', 'NEW222', 'NEW333'] }));

      render(<TwoFactorSettings />);

      await waitFor(() => {
        expect(screen.getByText('Regenerate')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Regenerate'));
      fireEvent.change(screen.getByPlaceholderText('123456'), { target: { value: '111111' } });
      fireEvent.click(screen.getAllByText('Regenerate')[1]);

      await waitFor(() => {
        expect(mockPost).toHaveBeenCalledWith('/two_factor/regenerate_backup_codes', { code: '111111' });
      });

      await waitFor(() => {
        expect(screen.getByText('New Backup Codes')).toBeInTheDocument();
        expect(screen.getByText('NEW111')).toBeInTheDocument();
        expect(screen.getByText('NEW222')).toBeInTheDocument();
        expect(screen.getByText('NEW333')).toBeInTheDocument();
      });
    });

    it('copies the new backup codes to clipboard', async () => {
      mockPost.mockResolvedValue(envelope({ backup_codes: ['NEW111', 'NEW222'] }));

      render(<TwoFactorSettings />);

      await waitFor(() => {
        expect(screen.getByText('Regenerate')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Regenerate'));
      fireEvent.change(screen.getByPlaceholderText('123456'), { target: { value: '111111' } });
      fireEvent.click(screen.getAllByText('Regenerate')[1]);

      await waitFor(() => {
        expect(screen.getByText('Copy Codes')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Copy Codes'));

      expect(mockWriteText).toHaveBeenCalledWith('NEW111\nNEW222');
    });

    it('downloading the new backup codes creates and revokes an object URL', async () => {
      mockPost.mockResolvedValue(envelope({ backup_codes: ['NEW111', 'NEW222'] }));

      render(<TwoFactorSettings />);

      await waitFor(() => {
        expect(screen.getByText('Regenerate')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Regenerate'));
      fireEvent.change(screen.getByPlaceholderText('123456'), { target: { value: '111111' } });
      fireEvent.click(screen.getAllByText('Regenerate')[1]);

      await waitFor(() => {
        expect(screen.getByText('Download')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Download'));

      expect(URL.createObjectURL).toHaveBeenCalled();
      expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:mock');
    });

    it('disables Done until the acknowledgement is checked', async () => {
      mockPost.mockResolvedValue(envelope({ backup_codes: ['NEW111', 'NEW222'] }));

      render(<TwoFactorSettings />);

      await waitFor(() => {
        expect(screen.getByText('Regenerate')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Regenerate'));
      fireEvent.change(screen.getByPlaceholderText('123456'), { target: { value: '111111' } });
      fireEvent.click(screen.getAllByText('Regenerate')[1]);

      await waitFor(() => {
        expect(screen.getByText('Done')).toBeInTheDocument();
      });

      expect(screen.getByText('Done').closest('button')).toBeDisabled();

      fireEvent.click(screen.getByRole('checkbox'));

      expect(screen.getByText('Done').closest('button')).not.toBeDisabled();
    });

    it('shows regenerating state', async () => {
      mockPost.mockImplementation(() => new Promise(() => {})); // Never resolves

      render(<TwoFactorSettings />);

      await waitFor(() => {
        expect(screen.getByText('Regenerate')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Regenerate'));
      fireEvent.change(screen.getByPlaceholderText('123456'), { target: { value: '111111' } });
      fireEvent.click(screen.getAllByText('Regenerate')[1]);

      // Both the card's Regenerate button and the modal's submit button
      // reflect isRegenerating, so this is intentionally plural.
      expect(screen.getAllByText('Regenerating...').length).toBeGreaterThan(0);
    });
  });

  describe('error handling', () => {
    it('shows error when status fetch fails', async () => {
      mockGet.mockResolvedValue(envelope(undefined, undefined, false));

      render(<TwoFactorSettings />);

      await waitFor(() => {
        expect(screen.getByText('Failed to load two-factor authentication status')).toBeInTheDocument();
      });
    });
  });

  // The section title + description now live in the caller's card header
  // (ProfilePage's Security tab uses the same px-6/py-4/border-b style as its
  // sibling cards) — this component owns only the status row and its label.
  describe('status label', () => {
    beforeEach(() => {
      mockGet.mockResolvedValue(envelope({ two_factor_enabled: false, backup_codes_count: 0 }));
    });

    it('labels the status row', async () => {
      render(<TwoFactorSettings />);

      await waitFor(() => {
        expect(screen.getByText('Two-Factor Authentication')).toBeInTheDocument();
      });
    });
  });
});
