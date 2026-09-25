import { render, screen, waitFor } from '@testing-library/react';
import { Provider } from 'react-redux';
import { MemoryRouter } from 'react-router-dom';
import { configureStore } from '@reduxjs/toolkit';
import { AdminSettingsOverviewPage } from './AdminSettingsOverviewPage';
import { featureRegistry } from '@/shared/services/featureRegistry';

// Mock ONE LAYER BELOW adminSettingsApi — at the raw `api` client — so the
// real getOverview() unwraps the actual server envelope,
// { success, data: {...} } (ApiResponse#render_success).
const mockGet = jest.fn();
jest.mock('@/shared/services/api', () => ({
  api: {
    get: (...args: unknown[]) => mockGet(...args)
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

// The admin_overview payload core serves: metrics and the settings summary.
const overview = (settingsSummary: Record<string, unknown> = {}) => ({
  metrics: {
    total_users: 10,
    total_accounts: 3,
    active_accounts: 2,
    suspended_accounts: 1,
    cancelled_accounts: 0
  },
  settings_summary: settingsSummary
});

const respondWith = (data: Record<string, unknown>) =>
  mockGet.mockResolvedValue({ data: { success: true, data } });

describe('AdminSettingsOverviewPage', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    featureRegistry.clear();
  });

  afterEach(() => featureRegistry.clear());

  const renderPage = (permissions: string[] = ['admin.settings.read']) => {
    const store = configureStore({
      reducer: {
        auth: (state = { user: { id: 'u1', permissions }, isAuthenticated: true }) => state
      }
    });

    return render(
      <Provider store={store}>
        <MemoryRouter>
          <AdminSettingsOverviewPage />
        </MemoryRouter>
      </Provider>
    );
  };

  it('reads the overview from GET /admin_settings', async () => {
    respondWith(overview());

    renderPage();

    await screen.findByText('Total Users');
    expect(mockGet).toHaveBeenCalledWith('/admin_settings');
  });

  it('renders no maintenance mode toggle — only a link to the Maintenance tab', async () => {
    respondWith(overview({ maintenance_mode: false }));

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
    respondWith(overview({ maintenance_mode: true }));

    renderPage();

    const link = await screen.findByText('Manage Maintenance Mode');
    link.click();

    expect(mockNavigate).toHaveBeenCalledWith('/app/admin/maintenance/mode');
  });

  // fc-45: the overview is metrics only.
  it('shows the core metrics, with no invented change figures', async () => {
    respondWith(overview());

    renderPage();

    await screen.findByText('Total Users');
    expect(screen.getByText('10')).toBeInTheDocument();
    expect(screen.getByText('Active Accounts')).toBeInTheDocument();
    expect(screen.getByText('2/3')).toBeInTheDocument();
    expect(screen.queryByText(/%/)).not.toBeInTheDocument();
  });

  it('shows no billing figures, activity lists, quick actions or configuration cards', async () => {
    respondWith(overview());

    renderPage();

    await screen.findByText('Total Users');
    [
      'Monthly Revenue', 'Active Subscriptions', 'Payment Gateway Status', 'Stripe', 'PayPal',
      'Recent Activity', 'Recent Accounts', 'System Logs', 'Recent Users',
      'Quick Actions', 'Configuration Overview'
    ].forEach((text) => expect(screen.queryByText(text)).not.toBeInTheDocument());
    // The one link is to the platform status page (fc-47).
    expect(screen.getAllByRole('link').map((l) => l.getAttribute('href'))).toEqual(['/app/status']);
  });

  // fc-47: platform health is on /app/status. The overview renders no health
  // verdict or uptime of its own, only a link to the status page.
  it('shows no System Health card or uptime, and links to /app/status', async () => {
    respondWith(overview());

    renderPage();

    await screen.findByText('Total Users');
    expect(screen.queryByText('System Health')).not.toBeInTheDocument();
    expect(screen.queryByText(/Uptime/)).not.toBeInTheDocument();
    expect(screen.queryByText('All systems operational')).not.toBeInTheDocument();
    expect(screen.getByRole('link', { name: /Platform status/ })).toHaveAttribute('href', '/app/status');
  });

  // Extension status cards mount through a generic component-slot prefix;
  // core names no extension.
  it("renders every component registered under 'admin.settings.overview.'", async () => {
    featureRegistry.registerComponentSlots({
      'admin.settings.overview.first': () => <div>First extension card</div>,
      'admin.settings.overview.second': () => <div>Second extension card</div>,
      'admin.settings.elsewhere': () => <div>Not an overview card</div>
    });
    respondWith(overview());

    renderPage();

    expect(await screen.findByText('First extension card')).toBeInTheDocument();
    expect(screen.getByText('Second extension card')).toBeInTheDocument();
    expect(screen.queryByText('Not an overview card')).not.toBeInTheDocument();
  });

  it("hides a slot card from a viewer without the slot's declared permissions", async () => {
    featureRegistry.registerComponentSlots({
      'admin.settings.overview.gated': () => <div>Gated extension card</div>
    });
    featureRegistry.registerSlotMeta({ 'admin.settings.overview.gated': { permissions: ['some.extension.read'] } });
    respondWith(overview());

    const { unmount } = renderPage(['admin.settings.read']);
    await screen.findByText('Total Users');
    expect(screen.queryByText('Gated extension card')).not.toBeInTheDocument();
    unmount();

    renderPage(['admin.settings.read', 'some.extension.read']);
    expect(await screen.findByText('Gated extension card')).toBeInTheDocument();
  });
});
