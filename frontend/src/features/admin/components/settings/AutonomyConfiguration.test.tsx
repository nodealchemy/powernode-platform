import { screen, waitFor, fireEvent, render } from '@testing-library/react';
import { Provider } from 'react-redux';
import { MemoryRouter, Routes, Route } from 'react-router-dom';
import { configureStore } from '@reduxjs/toolkit';
import { renderWithProviders } from '@/shared/utils/test-utils';
import { AutonomyConfiguration, CLOSURE_DRIVER_SETTING_KEY } from './AutonomyConfiguration';
import { AdminSettingsPage } from '@/pages/app/admin/AdminSettingsPage';
import { BreadcrumbProvider } from '@/shared/hooks/BreadcrumbContext';
import { siteSettingsApi, SiteSetting } from '@/features/admin/settings/services/siteSettingsApi';

jest.mock('@/features/admin/settings/services/siteSettingsApi');
jest.mock('@/shared/utils/permissionUtils', () => ({
  ...jest.requireActual('@/shared/utils/permissionUtils'),
  hasPermissions: () => true
}));

const mockSiteSettingsApi = siteSettingsApi as jest.Mocked<typeof siteSettingsApi>;

const closureRow = (value: string): SiteSetting => ({
  id: 'setting-1',
  key: CLOSURE_DRIVER_SETTING_KEY,
  value,
  parsed_value: value === 'true',
  description: 'Run the AI autonomy closure driver on its cron cadence.',
  setting_type: 'boolean',
  is_public: false,
  created_at: '2026-09-10T00:00:00Z',
  updated_at: '2026-09-10T00:00:00Z'
});

const listing = (settings: SiteSetting[]) => ({
  success: true,
  data: { settings, total_count: settings.length }
});

const MANAGER = { id: 'u1', email: 'ops@example.com', permissions: ['admin.settings.read', 'settings.manage'] };
const VIEWER = { id: 'u2', email: 'ro@example.com', permissions: ['admin.settings.read'] };

const findToggle = () => screen.findByRole('switch', { name: /closure driver/i });

describe('AutonomyConfiguration', () => {
  beforeEach(() => jest.clearAllMocks());

  const renderAs = (user: typeof MANAGER) =>
    renderWithProviders(<AutonomyConfiguration />, {
      preloadedState: { auth: { user, isAuthenticated: true } } as never
    });

  describe('which store it writes', () => {
    it('renders OFF and CREATES the row when the setting has never been written', async () => {
      mockSiteSettingsApi.getSiteSettings.mockResolvedValue(listing([]));
      mockSiteSettingsApi.createSiteSetting.mockResolvedValue({
        success: true, data: { setting: closureRow('true'), message: 'created' }
      });

      renderAs(MANAGER);
      const toggle = await findToggle();
      expect(toggle).not.toBeChecked();

      fireEvent.click(toggle);

      await waitFor(() => expect(mockSiteSettingsApi.createSiteSetting).toHaveBeenCalledTimes(1));
      expect(mockSiteSettingsApi.createSiteSetting).toHaveBeenCalledWith(
        expect.objectContaining({ key: CLOSURE_DRIVER_SETTING_KEY, value: 'true', setting_type: 'boolean' })
      );
      expect(mockSiteSettingsApi.updateSiteSetting).not.toHaveBeenCalled();
      await waitFor(() => expect(toggle).toBeChecked());
    });

    it('renders ON from a stored true and UPDATES the existing row when turned off', async () => {
      mockSiteSettingsApi.getSiteSettings.mockResolvedValue(listing([closureRow('true')]));
      mockSiteSettingsApi.updateSiteSetting.mockResolvedValue({
        success: true, data: { setting: closureRow('false'), message: 'updated' }
      });

      renderAs(MANAGER);
      const toggle = await findToggle();
      await waitFor(() => expect(toggle).toBeChecked());

      fireEvent.click(toggle);

      await waitFor(() => expect(mockSiteSettingsApi.updateSiteSetting).toHaveBeenCalledWith('setting-1', { value: 'false' }));
      expect(mockSiteSettingsApi.createSiteSetting).not.toHaveBeenCalled();
      await waitFor(() => expect(toggle).not.toBeChecked());
    });
  });

  // F2 — the control gates on settings.manage, the permission its write
  // endpoint names. The enclosing screen only gates on admin.settings.READ.
  describe('permission gate', () => {
    it('is operable for a user holding settings.manage', async () => {
      mockSiteSettingsApi.getSiteSettings.mockResolvedValue(listing([closureRow('false')]));

      renderAs(MANAGER);

      expect(await findToggle()).toBeEnabled();
      expect(screen.queryByTestId('closure-driver-readonly')).not.toBeInTheDocument();
    });

    it('is read-only for a user without it, and a click writes nothing', async () => {
      mockSiteSettingsApi.getSiteSettings.mockResolvedValue(listing([closureRow('false')]));

      renderAs(VIEWER);
      const toggle = await findToggle();

      expect(toggle).toBeDisabled();
      expect(screen.getByTestId('closure-driver-readonly')).toBeInTheDocument();

      fireEvent.click(toggle);
      expect(mockSiteSettingsApi.updateSiteSetting).not.toHaveBeenCalled();
      expect(mockSiteSettingsApi.createSiteSetting).not.toHaveBeenCalled();
    });
  });

  // F4 — a failed load must not render a confident OFF for a switch whose real
  // state is unknown.
  describe('failed load', () => {
    it('says unknown and refuses to act', async () => {
      mockSiteSettingsApi.getSiteSettings.mockRejectedValue(new Error('boom'));

      renderAs(MANAGER);

      expect(await screen.findByTestId('closure-driver-unknown')).toBeInTheDocument();
      const toggle = await findToggle();
      expect(toggle).toBeDisabled();
      expect(toggle).not.toBeChecked();
    });

    it('does NOT say unknown when the row is merely absent', async () => {
      // The other arm: absent is a real state meaning OFF, and must stay
      // distinguishable from "could not read".
      mockSiteSettingsApi.getSiteSettings.mockResolvedValue(listing([]));

      renderAs(MANAGER);

      const toggle = await findToggle();
      expect(toggle).toBeEnabled();
      expect(screen.queryByTestId('closure-driver-unknown')).not.toBeInTheDocument();
    });
  });

  // F5 — both arms of the failed write, so "refused to move" is
  // distinguishable from "never moved".
  describe('failed write', () => {
    it('stays OFF when enabling fails', async () => {
      mockSiteSettingsApi.getSiteSettings.mockResolvedValue(listing([closureRow('false')]));
      mockSiteSettingsApi.updateSiteSetting.mockRejectedValue(new Error('boom'));

      renderAs(MANAGER);
      const toggle = await findToggle();
      fireEvent.click(toggle);

      await waitFor(() => expect(mockSiteSettingsApi.updateSiteSetting).toHaveBeenCalled());
      await waitFor(() => expect(toggle).not.toBeChecked());
    });

    it('stays ON when disabling fails', async () => {
      mockSiteSettingsApi.getSiteSettings.mockResolvedValue(listing([closureRow('true')]));
      mockSiteSettingsApi.updateSiteSetting.mockRejectedValue(new Error('boom'));

      renderAs(MANAGER);
      const toggle = await findToggle();
      await waitFor(() => expect(toggle).toBeChecked());

      fireEvent.click(toggle);

      await waitFor(() => expect(mockSiteSettingsApi.updateSiteSetting).toHaveBeenCalled());
      await waitFor(() => expect(toggle).toBeChecked());
    });
  });
});

// F1 — REACHABILITY. The previous version of this control lived in
// PlatformConfiguration, which is rendered only by AdminSettingsPlatformTabPage
// — a page no route reaches and no tab lists. It rendered in jsdom and in no
// browser. A bare component render is exactly the oracle that cannot see that,
// so this renders the settings SHELL at the real URL and looks for the switch.
describe('AutonomyConfiguration reachability through the settings shell', () => {
  const store = () =>
    configureStore({
      reducer: {
        auth: (state = { user: MANAGER, isAuthenticated: true }) => state,
        config: (state = { loadedExtensions: [] }) => state
      }
    });

  const renderShell = (path: string) =>
    render(
      <Provider store={store()}>
        <MemoryRouter initialEntries={[path]}>
          <BreadcrumbProvider>
            {/* Mounted the way DashboardPage mounts it, under the splat —
                rendering AdminSettingsPage bare would leave its inner Routes
                matching against the full path and never hitting /autonomy. */}
            <Routes>
              <Route path="/app/admin/settings/*" element={<AdminSettingsPage />} />
            </Routes>
          </BreadcrumbProvider>
        </MemoryRouter>
      </Provider>
    );

  beforeEach(() => {
    jest.clearAllMocks();
    mockSiteSettingsApi.getSiteSettings.mockResolvedValue(listing([closureRow('false')]));
  });

  it('routes /app/admin/settings/autonomy to the real switch', async () => {
    renderShell('/app/admin/settings/autonomy');

    expect(await findToggle()).toBeInTheDocument();
  });

  it('lists an Autonomy tab pointing at that route', async () => {
    renderShell('/app/admin/settings/autonomy');

    // By ROLE, not text: at this route "Autonomy" is also the page heading, so
    // a bare text query matches two nodes and proves neither.
    const tab = await screen.findByRole('button', { name: /autonomy/i });
    expect(tab).toBeInTheDocument();
  });

  it('does not render the switch on a sibling settings route', async () => {
    // The other arm: proves the assertion above is the ROUTE matching, not the
    // shell rendering every tab's content at once.
    renderShell('/app/admin/settings/vault');

    await waitFor(() => expect(screen.queryByRole('switch', { name: /closure driver/i })).not.toBeInTheDocument());
  });
});
