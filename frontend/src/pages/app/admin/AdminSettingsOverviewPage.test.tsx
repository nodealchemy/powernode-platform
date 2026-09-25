import { render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AdminSettingsOverviewPage } from './AdminSettingsOverviewPage';
import { adminSettingsApi } from '@/features/admin/services/adminSettingsApi';
import { servicesApi } from '@/features/admin/services/servicesApi';

jest.mock('@/features/admin/services/adminSettingsApi', () => ({
  adminSettingsApi: {
    getOverview: jest.fn(),
    formatUptime: jest.fn(() => '1h'),
    formatNumber: jest.fn((n: number) => `${n}`),
    formatCurrency: jest.fn((n: number) => `$${n}`)
  }
}));

jest.mock('@/features/admin/services/servicesApi', () => ({
  servicesApi: {
    getDetailedHealthStatus: jest.fn()
  }
}));

jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ showNotification: jest.fn() })
}));

const mockNavigate = jest.fn();
jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useNavigate: () => mockNavigate
}));

describe('AdminSettingsOverviewPage', () => {
  const baseOverview = {
    metrics: {
      system_health: 'healthy',
      uptime: 3600,
      total_users: 10,
      active_accounts: 2,
      total_accounts: 3,
      monthly_revenue: 100,
      active_subscriptions: 1,
      total_subscriptions: 2
    },
    recent_users: [],
    recent_accounts: [],
    recent_logs: [],
    payment_gateways: {
      stripe: { connected: false, environment: 'test', last_webhook: null, webhook_status: 'no_data' },
      paypal: { connected: false, environment: 'sandbox', last_webhook: null, webhook_status: 'no_data' }
    },
    settings_summary: {}
  };

  beforeEach(() => {
    jest.clearAllMocks();
    (servicesApi.getDetailedHealthStatus as jest.Mock).mockResolvedValue(null);
  });

  const renderPage = () =>
    render(
      <MemoryRouter>
        <AdminSettingsOverviewPage />
      </MemoryRouter>
    );

  it('renders no maintenance mode toggle — only a link to the Maintenance tab', async () => {
    (adminSettingsApi.getOverview as jest.Mock).mockResolvedValue({
      success: true,
      data: { ...baseOverview, settings_summary: { maintenance_mode: false } }
    });

    renderPage();

    await waitFor(() => expect(screen.getByText('Maintenance Mode')).toBeInTheDocument());

    // No toggle/switch and no direct-mutation "Disable Maintenance" control —
    // this page no longer writes maintenance_mode itself (see
    // Api::V1::Admin::Maintenance::MaintenanceController#update_mode, now the
    // only writer).
    expect(screen.queryByRole('checkbox')).not.toBeInTheDocument();
    expect(screen.queryByText('Disable Maintenance')).not.toBeInTheDocument();

    expect(screen.getByText('Enable Maintenance Mode')).toBeInTheDocument();
  });

  it('links to the Maintenance Mode tab when maintenance is already active', async () => {
    (adminSettingsApi.getOverview as jest.Mock).mockResolvedValue({
      success: true,
      data: { ...baseOverview, settings_summary: { maintenance_mode: true } }
    });

    renderPage();

    const link = await screen.findByText('Manage Maintenance Mode');
    link.click();

    expect(mockNavigate).toHaveBeenCalledWith('/app/admin/maintenance/mode');
  });

  // fc-06: this quick link's label read "Services" while its destination was
  // /app/admin/workers (WorkersPage, titled "Worker Management") -- label and
  // destination disagreed.
  it('labels the /app/admin/workers quick link Workers, agreeing with its destination', async () => {
    (adminSettingsApi.getOverview as jest.Mock).mockResolvedValue({
      success: true,
      data: baseOverview
    });

    renderPage();

    const link = await screen.findByRole('link', { name: /Workers/i });
    expect(link).toHaveAttribute('href', '/app/admin/workers');
    expect(screen.queryByText('Services')).not.toBeInTheDocument();
  });
});
