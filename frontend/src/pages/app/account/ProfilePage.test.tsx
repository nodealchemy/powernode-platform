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
const fail = (error: string) => ({ data: { success: false, error } });

// Per-endpoint handlers the mocked api.get/post/delete dispatch to by URL —
// each test configures only the handlers it exercises.
const statusHandler = jest.fn();
const enableHandler = jest.fn();
const verifySetupHandler = jest.fn();
const disableHandler = jest.fn();
const backupCodesHandler = jest.fn();
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
      if (url === '/two_factor/backup_codes') return backupCodesHandler();
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
    statusHandler
      .mockResolvedValueOnce(ok({ two_factor_enabled: false, backup_codes_count: 0 }))
      .mockResolvedValueOnce(ok({ two_factor_enabled: true, backup_codes_count: 3, enabled_at: '2026-01-01T00:00:00Z' }));
    enableHandler.mockResolvedValue(ok({
      qr_code: '<svg>qr</svg>',
      manual_entry_key: 'ABCD1234EFGH5678',
      backup_codes: ['code1', 'code2', 'code3']
    }, 'Two-factor authentication has been enabled'));
    verifySetupHandler.mockResolvedValue(ok({}, 'Two-factor authentication setup verified successfully'));

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
    // Backup codes shown at completion came from the enable() response.
    expect(screen.getByText('code1')).toBeInTheDocument();
    expect(screen.getByText('code2')).toBeInTheDocument();
    expect(screen.getByText('code3')).toBeInTheDocument();

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
    fireEvent.click(screen.getByText('Disable 2FA'));

    await waitFor(() => {
      expect(disableHandler).toHaveBeenCalled();
      expect(screen.getByText('Enable 2FA')).toBeInTheDocument();
    });
  });

  it('views backup codes fetched through the real envelope', async () => {
    statusHandler.mockResolvedValue(ok({ two_factor_enabled: true, backup_codes_count: 3 }));
    backupCodesHandler.mockResolvedValue(ok({
      backup_codes: ['AAA111', 'BBB222', 'CCC333'],
      generated_at: '2026-01-01T00:00:00Z'
    }));

    renderProfileSecurity();

    await waitFor(() => {
      expect(screen.getByText('View Codes')).toBeInTheDocument();
    });

    fireEvent.click(screen.getByText('View Codes'));

    await waitFor(() => {
      expect(screen.getByText('AAA111')).toBeInTheDocument();
      expect(screen.getByText('BBB222')).toBeInTheDocument();
      expect(screen.getByText('CCC333')).toBeInTheDocument();
    });
  });

  it('regenerates backup codes through the real envelope', async () => {
    statusHandler.mockResolvedValue(ok({ two_factor_enabled: true, backup_codes_count: 2 }));
    regenerateHandler.mockResolvedValue(ok({
      backup_codes: ['NEW111', 'NEW222', 'NEW333', 'NEW444', 'NEW555']
    }, 'Backup codes regenerated successfully'));

    renderProfileSecurity();

    await waitFor(() => {
      expect(screen.getByText('You have 2 backup codes remaining')).toBeInTheDocument();
    });

    fireEvent.click(screen.getByText('Regenerate'));

    // The new count comes from unwrapping `backup_codes` off the real
    // envelope — a flat-shape mock of twoFactorApi can't exercise this.
    await waitFor(() => {
      expect(regenerateHandler).toHaveBeenCalled();
      expect(screen.getByText('You have 5 backup codes remaining')).toBeInTheDocument();
    });
  });

  it('surfaces a server error message on disable failure', async () => {
    statusHandler.mockResolvedValue(ok({ two_factor_enabled: true, backup_codes_count: 2 }));
    disableHandler.mockResolvedValue(fail('Two-factor authentication is not enabled for this account'));

    renderProfileSecurity();

    await waitFor(() => {
      expect(screen.getByText('Disable')).toBeInTheDocument();
    });

    fireEvent.click(screen.getByText('Disable'));
    fireEvent.click(screen.getByText('Disable 2FA'));

    await waitFor(() => {
      expect(screen.getByText('Two-factor authentication is not enabled for this account')).toBeInTheDocument();
    });
  });
});
