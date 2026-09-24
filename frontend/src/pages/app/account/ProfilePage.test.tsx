import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { Provider } from 'react-redux';
import { MemoryRouter } from 'react-router-dom';
import { configureStore } from '@reduxjs/toolkit';
import { ProfilePage } from './ProfilePage';
import { BreadcrumbProvider } from '@/shared/hooks/BreadcrumbContext';
import { settingsApi } from '@/shared/services/settings/settingsApi';

// Settings API — Profile -> Security also renders Change Password / SSH keys,
// which pull their data from here. Mocked wholesale (unrelated to the 2FA
// envelope this file is otherwise pinning down).
jest.mock('@/shared/services/settings/settingsApi', () => ({
  settingsApi: {
    getUserSettings: jest.fn(),
    updateUserSettings: jest.fn(),
    updateProfile: jest.fn(),
    updateSshKeys: jest.fn(),
    changePassword: jest.fn()
  }
}));

// Mock ONE LAYER BELOW twoFactorApi — at the raw `api` client — so the real
// twoFactorApi (and the real TwoFactorSettings/TwoFactorSetup components) run
// against the actual server envelope: { success, data: {...}, message? } on
// success, { success: false, error } on failure (ApiResponse#render_success /
// #render_error, server/app/controllers/concerns/api_response.rb). Mocking
// twoFactorApi itself would hide any bug in twoFactorApi's own unwrapping.
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

jest.mock('@/shared/utils/sanitizeHtml', () => ({
  sanitizeQrCode: (html: string) => html
}));

// Real-time settings sync is out of scope here — same pattern as other
// page tests that stub out the websocket hook their page wires up.
jest.mock('@/shared/hooks/useSettingsWebSocket', () => ({
  useSettingsWebSocket: () => ({
    isConnected: false,
    requestSettingsSync: jest.fn(),
    ping: jest.fn(),
    error: null
  })
}));

jest.mock('@/shared/components/ui/WebSocketStatusIndicator', () => ({
  WebSocketStatusIndicator: () => <div data-testid="ws-status-indicator" />
}));

jest.mock('@/shared/hooks/ThemeContext', () => ({
  useTheme: () => ({
    theme: 'light',
    setTheme: jest.fn(),
    toggleTheme: jest.fn(),
    loading: false
  })
}));

Object.assign(navigator, {
  clipboard: {
    writeText: jest.fn()
  }
});

const mockGetUserSettings = settingsApi.getUserSettings as jest.Mock;

const emptyUserSettings = {
  success: true,
  data: {
    user_preferences: {},
    account_settings: {},
    notification_preferences: {},
    security_settings: {}
  }
};

// Wraps a payload in the AxiosResponse-shaped envelope `api.get/post/delete`
// resolve to. The outer `data` is the Axios response body; inside sits the
// Rails double-envelope `{ success, data, message? }`.
const ok = (data: Record<string, unknown> = {}, message?: string) => ({
  data: { success: true, data, ...(message ? { message } : {}) }
});

// Per-endpoint handlers the mocked api.get/post/delete dispatch to by URL —
// each test configures only the handlers it exercises.
const statusHandler = jest.fn();
const enableHandler = jest.fn();
const verifySetupHandler = jest.fn();
const disableHandler = jest.fn();
const regenerateHandler = jest.fn();

const renderProfileSecurity = () => {
  const store = configureStore({
    reducer: {
      auth: (state = { user: { id: 'u1', name: 'Test User', email: 'test@example.com', permissions: [] }, isAuthenticated: true }) => state
    }
  });

  return render(
    <Provider store={store}>
      <MemoryRouter initialEntries={['/app/profile/security']}>
        <BreadcrumbProvider>
          <ProfilePage />
        </BreadcrumbProvider>
      </MemoryRouter>
    </Provider>
  );
};

describe('ProfilePage - Security tab - 2FA enrolment', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockGetUserSettings.mockResolvedValue(emptyUserSettings);

    mockGet.mockImplementation((url: string) => {
      if (url === '/two_factor/status') return statusHandler();
      return Promise.reject(new Error(`unexpected GET ${url}`));
    });
    mockPost.mockImplementation((url: string, body?: unknown) => {
      if (url === '/two_factor/enable') return enableHandler();
      if (url === '/two_factor/verify_setup') return verifySetupHandler(body);
      if (url === '/two_factor/regenerate_backup_codes') return regenerateHandler();
      return Promise.reject(new Error(`unexpected POST ${url}`));
    });
    mockDelete.mockImplementation((url: string) => {
      if (url === '/two_factor/disable') return disableHandler();
      return Promise.reject(new Error(`unexpected DELETE ${url}`));
    });
  });

  it('shows Disabled when the server reports 2FA off', async () => {
    statusHandler.mockResolvedValue(ok({ two_factor_enabled: false, backup_codes_count: 0 }));

    renderProfileSecurity();

    await waitFor(() => {
      expect(screen.getByText('Disabled')).toBeInTheDocument();
    });
    expect(screen.getByText('Enable 2FA')).toBeInTheDocument();
    expect(screen.getAllByText('Change Password').length).toBeGreaterThan(0);
  });

  it('shows Enabled with the real backup codes count when the server reports 2FA on', async () => {
    statusHandler.mockResolvedValue(ok({
      two_factor_enabled: true,
      backup_codes_count: 7,
      enabled_at: '2026-01-01T00:00:00Z'
    }));

    renderProfileSecurity();

    await waitFor(() => {
      expect(screen.getByText(/Enabled.*Enabled on/)).toBeInTheDocument();
    });
    expect(screen.getByText('You have 7 backup codes remaining')).toBeInTheDocument();
    expect(screen.getByText('Disable')).toBeInTheDocument();
  });

  it('runs the enable -> verify -> enabled flow end to end against the real envelope', async () => {
    // IMP-99e8e4701150: enable() only starts a PENDING enrolment (qr_code /
    // manual_entry_key / expires_at) — no backup codes yet. They come back
    // from verify_setup, exactly once, when the pending secret is confirmed.
    statusHandler
      .mockResolvedValueOnce(ok({ two_factor_enabled: false, backup_codes_count: 0 }))
      .mockResolvedValueOnce(ok({ two_factor_enabled: true, backup_codes_count: 3, enabled_at: '2026-01-01T00:00:00Z' }));
    enableHandler.mockResolvedValue(ok({
      qr_code: '<svg>qr</svg>',
      manual_entry_key: 'ABCD1234EFGH5678',
      expires_at: '2026-01-01T00:15:00Z'
    }, 'Scan the QR code with your authenticator app, then verify a code to finish enabling two-factor authentication'));
    verifySetupHandler.mockResolvedValue(ok({
      backup_codes: ['code1', 'code2', 'code3']
    }, 'Two-factor authentication has been enabled'));

    renderProfileSecurity();

    await waitFor(() => {
      expect(screen.getByText('Enable 2FA')).toBeInTheDocument();
    });

    fireEvent.click(screen.getByText('Enable 2FA'));

    // Setup step reads qr_code / manual_entry_key off the unwrapped response —
    // this is exactly what a flat-shape mock at the twoFactorApi layer can't see.
    await waitFor(() => {
      expect(screen.getByText(/Manual Setup Key/i)).toBeInTheDocument();
      expect(screen.getByPlaceholderText('123456')).toBeInTheDocument();
    });

    fireEvent.change(screen.getByPlaceholderText('123456'), { target: { value: '123456' } });
    fireEvent.click(screen.getByText('Verify & Enable'));

    await waitFor(() => {
      expect(verifySetupHandler).toHaveBeenCalledWith({ token: '123456' });
      expect(screen.getByText(/Two-Factor Authentication Enabled!/i)).toBeInTheDocument();
    });
    // Backup codes shown at completion came from the verify_setup() response.
    expect(screen.getByText('code1')).toBeInTheDocument();
    expect(screen.getByText('code2')).toBeInTheDocument();
    expect(screen.getByText('code3')).toBeInTheDocument();

    // Done is gated behind the "I have saved these" acknowledgement.
    expect(screen.getByText('Done').closest('button')).toBeDisabled();
    fireEvent.click(screen.getByRole('checkbox'));
    fireEvent.click(screen.getByText('Done'));

    await waitFor(() => {
      expect(screen.getByText('Disable')).toBeInTheDocument();
    });
  });

  it('disables 2FA from the mounted Security tab', async () => {
    statusHandler.mockResolvedValue(ok({ two_factor_enabled: true, backup_codes_count: 5 }));
    disableHandler.mockResolvedValue(ok({}, 'Two-factor authentication has been disabled'));

    renderProfileSecurity();

    await waitFor(() => {
      expect(screen.getByText('Disable')).toBeInTheDocument();
    });

    fireEvent.click(screen.getByText('Disable'));
    // Disable now requires re-authentication: a current TOTP code or an
    // unused backup code (IMP-99e8e4701150).
    fireEvent.change(screen.getByPlaceholderText('123456'), { target: { value: '654321' } });
    fireEvent.click(screen.getByText('Disable 2FA'));

    await waitFor(() => {
      expect(disableHandler).toHaveBeenCalled();
      expect(screen.getByText('Enable 2FA')).toBeInTheDocument();
    });
  });

  // GET /two_factor/backup_codes is gone (IMP-99e8e4701150) — codes are never
  // re-fetchable after generation, so there is no "View Codes" action to test.

  it('regenerates backup codes through the real envelope', async () => {
    statusHandler.mockResolvedValue(ok({ two_factor_enabled: true, backup_codes_count: 2 }));
    regenerateHandler.mockResolvedValue(ok({
      backup_codes: ['NEW111', 'NEW222', 'NEW333', 'NEW444', 'NEW555']
    }, 'Backup codes regenerated successfully'));

    renderProfileSecurity();

    await waitFor(() => {
      expect(screen.getByText('You have 2 backup codes remaining')).toBeInTheDocument();
    });

    // Regenerate now requires re-authentication and shows the new codes
    // once, in their own modal (IMP-99e8e4701150).
    fireEvent.click(screen.getByText('Regenerate'));
    fireEvent.change(screen.getByPlaceholderText('123456'), { target: { value: '654321' } });
    fireEvent.click(screen.getAllByText('Regenerate')[1]);

    // The new count comes from unwrapping `backup_codes` off the real
    // envelope — a flat-shape mock of twoFactorApi can't exercise this.
    await waitFor(() => {
      expect(regenerateHandler).toHaveBeenCalled();
      expect(screen.getByText('You have 5 backup codes remaining')).toBeInTheDocument();
      expect(screen.getByText('New Backup Codes')).toBeInTheDocument();
      expect(screen.getByText('NEW111')).toBeInTheDocument();
    });
  });

  it('surfaces a server error message on disable failure', async () => {
    statusHandler.mockResolvedValue(ok({ two_factor_enabled: true, backup_codes_count: 2 }));
    // render_error responds with a non-2xx status (:bad_request here), so axios
    // REJECTS — it never resolves with {success:false}. Mirror that.
    disableHandler.mockRejectedValue({
      response: { status: 400, data: { success: false, error: 'Two-factor authentication is not enabled for this account' } }
    });

    renderProfileSecurity();

    await waitFor(() => {
      expect(screen.getByText('Disable')).toBeInTheDocument();
    });

    fireEvent.click(screen.getByText('Disable'));
    fireEvent.change(screen.getByPlaceholderText('123456'), { target: { value: '654321' } });
    fireEvent.click(screen.getByText('Disable 2FA'));

    await waitFor(() => {
      expect(screen.getByText('Two-factor authentication is not enabled for this account')).toBeInTheDocument();
    });
  });
});

// fc-20: the delegations UI is now reachable as a Profile tab. This pins the
// ROUTING/gating wiring (a permitted user reaches it at /app/profile/delegations,
// with the breadcrumb agreeing with the nav label); DelegationsManagement's own
// behaviour has its own full test suite and is not re-asserted here.
describe('ProfilePage - Delegations tab', () => {
  const renderProfileAt = (path: string, permissions: string[]) => {
    const store = configureStore({
      reducer: {
        auth: (state = { user: { id: 'u1', name: 'Test User', email: 'test@example.com', permissions, account: { id: 'acct-1', name: 'Acme', status: 'active' } }, isAuthenticated: true }) => state
      }
    });

    return render(
      <Provider store={store}>
        <MemoryRouter initialEntries={[path]}>
          <BreadcrumbProvider>
            <ProfilePage />
          </BreadcrumbProvider>
        </MemoryRouter>
      </Provider>
    );
  };

  beforeEach(() => {
    jest.clearAllMocks();
    mockGetUserSettings.mockResolvedValue(emptyUserSettings);
    // Generic envelope for delegationApi.getDelegations() and rolesApi.getPermissions()
    // (both are non-critical to this smoke test's assertions).
    mockGet.mockResolvedValue(ok({ delegations: [], meta: { total_count: 0, active_count: 0, expired_count: 0 } }));
  });

  it('shows the Delegations tab, and its content, for a user who holds accounts.manage', async () => {
    renderProfileAt('/app/profile/delegations', ['accounts.manage']);

    await waitFor(() => {
      expect(screen.getByText('Account Delegations')).toBeInTheDocument();
    });
  });

  it('agrees with the sidebar nav label in the breadcrumb trail', async () => {
    renderProfileAt('/app/profile/delegations', ['accounts.manage']);

    await waitFor(() => {
      expect(screen.getByText('Delegations')).toBeInTheDocument();
    });
  });

  it('does not offer the tab to a user without accounts.manage or admin.access', async () => {
    renderProfileAt('/app/profile', ['team.read']);

    await waitFor(() => {
      expect(screen.getByText('Profile Information')).toBeInTheDocument();
    });
    expect(screen.queryByText('Delegations')).not.toBeInTheDocument();
  });
});
