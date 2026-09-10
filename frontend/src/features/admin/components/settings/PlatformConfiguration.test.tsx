import { screen, waitFor, fireEvent } from '@testing-library/react';
import { renderWithProviders } from '@/shared/utils/test-utils';
import { PlatformConfiguration, CLOSURE_DRIVER_SETTING_KEY } from './PlatformConfiguration';
import { adminSettingsApi } from '@/features/admin/services/adminSettingsApi';
import { siteSettingsApi, SiteSetting } from '@/features/admin/settings/services/siteSettingsApi';

jest.mock('@/features/admin/services/adminSettingsApi');
jest.mock('@/features/admin/settings/services/siteSettingsApi');

const mockAdminSettingsApi = adminSettingsApi as jest.Mocked<typeof adminSettingsApi>;
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

// D3 — the autonomy closure-driver toggle. The load-bearing property is that it
// reads and writes a SiteSetting: the server-side gate
// (Ai::Autonomy::ClosureDriverService.enabled?) reads SiteSetting, while every
// other field on this page is an AdminSetting, and those are different tables.
// A toggle wired to the wrong one would render and save perfectly while
// actuating nothing, so each example asserts WHICH api was called, not just
// that the switch moved.
describe('PlatformConfiguration — autonomy closure driver', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockAdminSettingsApi.getOverview.mockResolvedValue({ success: true, data: {} as never });
  });

  const findToggle = async () =>
    await screen.findByRole('switch', { name: /closure driver/i });

  it('renders OFF and CREATES the row when the setting has never been written', async () => {
    mockSiteSettingsApi.getSiteSettings.mockResolvedValue(listing([]));
    mockSiteSettingsApi.createSiteSetting.mockResolvedValue({
      success: true,
      data: { setting: closureRow('true'), message: 'created' }
    });

    renderWithProviders(<PlatformConfiguration />);

    const toggle = await findToggle();
    expect(toggle).not.toBeChecked();

    fireEvent.click(toggle);

    await waitFor(() => expect(mockSiteSettingsApi.createSiteSetting).toHaveBeenCalledTimes(1));
    expect(mockSiteSettingsApi.createSiteSetting).toHaveBeenCalledWith(
      expect.objectContaining({
        key: CLOSURE_DRIVER_SETTING_KEY,
        value: 'true',
        setting_type: 'boolean',
        is_public: false
      })
    );
    // The other arm of "which store": the AdminSetting path is not touched.
    expect(mockSiteSettingsApi.updateSiteSetting).not.toHaveBeenCalled();
    expect(mockAdminSettingsApi.updateSettings).not.toHaveBeenCalled();
    await waitFor(() => expect(toggle).toBeChecked());
  });

  it('renders ON from a stored true and UPDATES the existing row when turned off', async () => {
    mockSiteSettingsApi.getSiteSettings.mockResolvedValue(listing([closureRow('true')]));
    mockSiteSettingsApi.updateSiteSetting.mockResolvedValue({
      success: true,
      data: { setting: closureRow('false'), message: 'updated' }
    });

    renderWithProviders(<PlatformConfiguration />);

    const toggle = await findToggle();
    await waitFor(() => expect(toggle).toBeChecked());

    fireEvent.click(toggle);

    await waitFor(() => expect(mockSiteSettingsApi.updateSiteSetting).toHaveBeenCalledTimes(1));
    expect(mockSiteSettingsApi.updateSiteSetting).toHaveBeenCalledWith('setting-1', { value: 'false' });
    expect(mockSiteSettingsApi.createSiteSetting).not.toHaveBeenCalled();
    await waitFor(() => expect(toggle).not.toBeChecked());
  });

  it('renders OFF from a stored false', async () => {
    mockSiteSettingsApi.getSiteSettings.mockResolvedValue(listing([closureRow('false')]));

    renderWithProviders(<PlatformConfiguration />);

    expect(await findToggle()).not.toBeChecked();
  });

  it('leaves the switch where it was when the write fails', async () => {
    mockSiteSettingsApi.getSiteSettings.mockResolvedValue(listing([closureRow('false')]));
    mockSiteSettingsApi.updateSiteSetting.mockRejectedValue(new Error('boom'));

    renderWithProviders(<PlatformConfiguration />);

    const toggle = await findToggle();
    fireEvent.click(toggle);

    await waitFor(() => expect(mockSiteSettingsApi.updateSiteSetting).toHaveBeenCalled());
    // The stored value did not change, so the control must not claim it did.
    await waitFor(() => expect(toggle).not.toBeChecked());
  });
});
