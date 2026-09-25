import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { AdminSettingsVaultTabPage } from './AdminSettingsVaultTabPage';

const mockGetVaultConfig = jest.fn();
const mockUpdateVaultConfig = jest.fn();
const mockTestVaultConnection = jest.fn();

jest.mock('@/features/admin/services/adminSettingsApi', () => ({
  adminSettingsApi: {
    getVaultConfig: (...args: unknown[]) => mockGetVaultConfig(...args),
    updateVaultConfig: (...args: unknown[]) => mockUpdateVaultConfig(...args),
    testVaultConnection: (...args: unknown[]) => mockTestVaultConnection(...args)
  }
}));

// A STABLE reference, not `() => ({ showNotification: jest.fn() })` — the
// component's loadConfig is useCallback([showNotification])-wrapped, so a
// fresh function identity on every render would re-run its
// useEffect(loadConfig, [loadConfig]) on every keystroke, flipping the form
// back into its loading state mid-interaction.
const mockShowNotification = jest.fn();
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ showNotification: mockShowNotification })
}));

// fc-38 review item #1 (HIGH): the server now returns "" plus a
// *_configured flag for both AppRole credentials — never any part of the
// real value — so these tests use that shape, not the old last-4-chars mask.
const vaultData = (overrides: Partial<{ vault_role_id_configured: boolean; vault_secret_id_configured: boolean }> = {}) => ({
  status: { connected: false, sealed: null, initialized: null, version: null, cluster_name: null },
  config: {
    vault_addr: 'http://vault.internal:8200',
    vault_role_id: '',
    vault_role_id_configured: overrides.vault_role_id_configured ?? true,
    vault_secret_id: '',
    vault_secret_id_configured: overrides.vault_secret_id_configured ?? true,
    configured: true
  },
  keys: { secured_count: 0, recent_operations: [] }
});

describe('AdminSettingsVaultTabPage', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockGetVaultConfig.mockResolvedValue({ success: true, data: vaultData() });
    mockUpdateVaultConfig.mockResolvedValue({ success: true, data: { message: 'saved' } });
  });

  it('never pre-populates the role ID or secret ID fields from the loaded config', async () => {
    render(<AdminSettingsVaultTabPage />);

    await waitFor(() => expect(screen.getAllByPlaceholderText(/Configured — enter a new value to change/)).toHaveLength(2));

    expect(screen.getByLabelText('AppRole Role ID')).toHaveValue('');
    expect(screen.getByLabelText('AppRole Secret ID')).toHaveValue('');
  });

  it('shows a "Configured" placeholder instead of any part of the credential', async () => {
    render(<AdminSettingsVaultTabPage />);

    await waitFor(() => {
      expect(screen.getByLabelText('AppRole Role ID')).toHaveAttribute('placeholder', 'Configured — enter a new value to change');
      expect(screen.getByLabelText('AppRole Secret ID')).toHaveAttribute('placeholder', 'Configured — enter a new value to change');
    });
  });

  // The actual regression: saving vault_addr alone used to resend the
  // pre-populated (masked) role_id/secret_id, silently overwriting both
  // real credentials.
  it('saving vault_addr alone does not send vault_role_id or vault_secret_id at all', async () => {
    render(<AdminSettingsVaultTabPage />);
    await waitFor(() => expect(screen.getByLabelText('Vault Address')).toHaveValue('http://vault.internal:8200'));

    fireEvent.change(screen.getByLabelText('Vault Address'), { target: { value: 'http://vault.updated.internal:8200' } });
    fireEvent.click(screen.getByText('Save Configuration'));

    await waitFor(() => expect(mockUpdateVaultConfig).toHaveBeenCalledWith({ vault_addr: 'http://vault.updated.internal:8200' }));

    const payload = mockUpdateVaultConfig.mock.calls[0][0];
    expect(payload).not.toHaveProperty('vault_role_id');
    expect(payload).not.toHaveProperty('vault_secret_id');
  });

  it('sends vault_role_id only after the user actually edits it', async () => {
    render(<AdminSettingsVaultTabPage />);
    await waitFor(() => expect(screen.getByLabelText('AppRole Role ID')).toBeInTheDocument());

    fireEvent.change(screen.getByLabelText('AppRole Role ID'), { target: { value: 'new-role-id' } });
    fireEvent.click(screen.getByText('Save Configuration'));

    await waitFor(() => {
      const payload = mockUpdateVaultConfig.mock.calls[0][0];
      expect(payload.vault_role_id).toBe('new-role-id');
      expect(payload).not.toHaveProperty('vault_secret_id');
    });
  });
});
