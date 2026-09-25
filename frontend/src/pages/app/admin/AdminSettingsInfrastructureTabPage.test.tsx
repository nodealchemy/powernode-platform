import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { AdminSettingsInfrastructureTabPage } from './AdminSettingsInfrastructureTabPage';

const mockGetInfrastructureConfig = jest.fn();
const mockUpdateInfrastructureConfig = jest.fn();
const mockTestRedisConnection = jest.fn();

jest.mock('@/features/admin/services/adminSettingsApi', () => ({
  adminSettingsApi: {
    getInfrastructureConfig: (...args: unknown[]) => mockGetInfrastructureConfig(...args),
    updateInfrastructureConfig: (...args: unknown[]) => mockUpdateInfrastructureConfig(...args),
    testRedisConnection: (...args: unknown[]) => mockTestRedisConnection(...args)
  }
}));

// A STABLE reference (see AdminSettingsVaultTabPage.test.tsx for why): this
// page has no useCallback([showNotification]) today, but keep the mock
// pattern consistent so a future refactor doesn't silently reintroduce the
// reload-loop bug that pattern causes.
const mockShowNotification = jest.fn();
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ showNotification: mockShowNotification })
}));

// fc-38 review item #1 (HIGH): the server now returns "" plus a
// password_configured flag — never any part of the real password.
const redisData = (passwordConfigured = true) => ({
  redis: {
    host: '127.0.0.1',
    port: 6379,
    database: 0,
    password: '',
    password_configured: passwordConfigured,
    ssl: false,
    url: null,
    connect_timeout: 5,
    read_timeout: 5,
    write_timeout: 5,
    pool_size: 5
  },
  connection: { status: 'connected' as const }
});

describe('AdminSettingsInfrastructureTabPage', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockGetInfrastructureConfig.mockResolvedValue({ success: true, data: redisData() });
    mockUpdateInfrastructureConfig.mockResolvedValue({ success: true, data: { redis: redisData().redis, message: 'saved' } });
  });

  it('never pre-populates the password field from the loaded config', async () => {
    render(<AdminSettingsInfrastructureTabPage />);

    await waitFor(() => expect(screen.getByLabelText('Password')).toHaveAttribute('placeholder', 'Configured — enter a new value to change'));

    expect(screen.getByLabelText('Password')).toHaveValue('');
  });

  it('shows "Optional" as the placeholder when no password is configured', async () => {
    mockGetInfrastructureConfig.mockResolvedValue({ success: true, data: redisData(false) });

    render(<AdminSettingsInfrastructureTabPage />);

    await waitFor(() => expect(screen.getByLabelText('Password')).toHaveAttribute('placeholder', 'Optional'));
  });

  // The regression this guards: resending whatever loadConfig put in state
  // (which used to be the server's own "••••••••" mask) as the real
  // password on every save.
  it('saving host alone does not include a password field in the request at all', async () => {
    render(<AdminSettingsInfrastructureTabPage />);
    await waitFor(() => expect(screen.getByLabelText('Host')).toHaveValue('127.0.0.1'));

    fireEvent.change(screen.getByLabelText('Host'), { target: { value: '10.0.0.5' } });
    fireEvent.click(screen.getByText('Save Connection'));

    await waitFor(() => expect(mockUpdateInfrastructureConfig).toHaveBeenCalled());

    const payload = mockUpdateInfrastructureConfig.mock.calls[0][0];
    expect(payload.host).toBe('10.0.0.5');
    expect(payload).not.toHaveProperty('password');
  });

  it('sends the password only after the user actually edits it', async () => {
    render(<AdminSettingsInfrastructureTabPage />);
    await waitFor(() => expect(screen.getByLabelText('Password')).toBeInTheDocument());

    fireEvent.change(screen.getByLabelText('Password'), { target: { value: 'new-redis-password' } });
    fireEvent.click(screen.getByText('Save Connection'));

    await waitFor(() => {
      const payload = mockUpdateInfrastructureConfig.mock.calls[0][0];
      expect(payload.password).toBe('new-redis-password');
    });
  });
});
