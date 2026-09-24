import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { Provider } from 'react-redux';
import { MemoryRouter } from 'react-router-dom';
import { configureStore } from '@reduxjs/toolkit';
import { ProfilePage } from './ProfilePage';
import { BreadcrumbProvider } from '@/shared/hooks/BreadcrumbContext';
import { twoFactorApi } from '@/shared/services/account/twoFactorApi';
import { settingsApi } from '@/shared/services/settings/settingsApi';

// Settings API — Profile -> Security also renders Change Password / SSH keys,
// which pull their data from here.
jest.mock('@/shared/services/settings/settingsApi', () => ({
  settingsApi: {
    getUserSettings: jest.fn(),
    updateUserSettings: jest.fn(),
    updateProfile: jest.fn(),
    updateSshKeys: jest.fn(),
    changePassword: jest.fn()
  }
}));

// 2FA API — real TwoFactorSettings/TwoFactorSetup components are mounted
// (not mocked) so this exercises the actual enable -> verify -> disable flow.
jest.mock('@/shared/services/account/twoFactorApi', () => ({
  twoFactorApi: {
    getStatus: jest.fn(),
    enable: jest.fn(),
    verifySetup: jest.fn(),
    disable: jest.fn(),
    getBackupCodes: jest.fn(),
    regenerateBackupCodes: jest.fn()
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
const mockGetStatus = twoFactorApi.getStatus as jest.Mock;
const mockEnable = twoFactorApi.enable as jest.Mock;
const mockVerifySetup = twoFactorApi.verifySetup as jest.Mock;
const mockDisable = twoFactorApi.disable as jest.Mock;

const emptyUserSettings = {
  success: true,
  data: {
    user_preferences: {},
    account_settings: {},
    notification_preferences: {},
    security_settings: {}
  }
};

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
  });

  it('mounts the 2FA section alongside Change Password', async () => {
    mockGetStatus.mockResolvedValue({
      success: true,
      two_factor_enabled: false,
      backup_codes_count: 0
    });

    renderProfileSecurity();

    await waitFor(() => {
      expect(screen.getAllByText('Two-Factor Authentication').length).toBeGreaterThan(0);
    });
    expect(screen.getAllByText('Change Password').length).toBeGreaterThan(0);
    expect(mockGetStatus).toHaveBeenCalled();
  });

  it('runs the enable -> verify -> enabled flow end to end', async () => {
    mockGetStatus
      .mockResolvedValueOnce({
        success: true,
        two_factor_enabled: false,
        backup_codes_count: 0
      })
      .mockResolvedValueOnce({
        success: true,
        two_factor_enabled: true,
        backup_codes_count: 3,
        enabled_at: '2026-01-01T00:00:00Z'
      });
    mockEnable.mockResolvedValue({
      success: true,
      qr_code: '<svg>qr</svg>',
      manual_entry_key: 'ABCD1234EFGH5678',
      backup_codes: ['code1', 'code2', 'code3']
    });
    mockVerifySetup.mockResolvedValue({ success: true });

    renderProfileSecurity();

    await waitFor(() => {
      expect(screen.getByText('Enable 2FA')).toBeInTheDocument();
    });

    fireEvent.click(screen.getByText('Enable 2FA'));

    await waitFor(() => {
      expect(mockEnable).toHaveBeenCalled();
      expect(screen.getByPlaceholderText('123456')).toBeInTheDocument();
    });

    fireEvent.change(screen.getByPlaceholderText('123456'), { target: { value: '123456' } });
    fireEvent.click(screen.getByText('Verify & Enable'));

    await waitFor(() => {
      expect(mockVerifySetup).toHaveBeenCalledWith('123456');
      expect(screen.getByText(/Two-Factor Authentication Enabled!/i)).toBeInTheDocument();
    });

    fireEvent.click(screen.getByText('Done'));

    await waitFor(() => {
      expect(screen.getByText('Disable')).toBeInTheDocument();
    });
  });

  it('disables 2FA from the mounted Security tab', async () => {
    mockGetStatus.mockResolvedValue({
      success: true,
      two_factor_enabled: true,
      backup_codes_count: 5
    });
    mockDisable.mockResolvedValue({ success: true });

    renderProfileSecurity();

    await waitFor(() => {
      expect(screen.getByText('Disable')).toBeInTheDocument();
    });

    fireEvent.click(screen.getByText('Disable'));
    fireEvent.click(screen.getByText('Disable 2FA'));

    await waitFor(() => {
      expect(mockDisable).toHaveBeenCalled();
      expect(screen.getByText('Enable 2FA')).toBeInTheDocument();
    });
  });
});
