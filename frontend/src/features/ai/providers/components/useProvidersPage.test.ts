import { renderHook, act, waitFor } from '@testing-library/react';
import { useProvidersPage } from './useProvidersPage';
import { providersApi } from '@/shared/services/ai';

// Regression: handleRefresh ([]), handleSetupDefaults and handleBulkTest
// ([addNotification]) captured the initial loadProviders closure, so Refresh /
// Test All / Setup Defaults reloaded the list WITHOUT the active filters and
// search query — silently resetting the visible list to the unfiltered page.
jest.mock('@/shared/services/ai', () => ({
  providersApi: {
    getProviders: jest.fn(),
    setupDefaultProviders: jest.fn(),
    testAllProviders: jest.fn(),
    deleteProvider: jest.fn(),
  },
}));
// Stable addNotification identity, matching the context-provided function in the
// real app (a fresh fn per render would defeat the [addNotification] dep arrays).
const mockAddNotification = jest.fn();
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ addNotification: mockAddNotification }),
}));
jest.mock('@/shared/hooks/usePermissions', () => ({
  usePermissions: () => ({ hasPermission: () => true }),
}));

const emptyResponse = {
  items: [],
  pagination: { current_page: 1, total_pages: 1, total_count: 0, per_page: 20 },
};

describe('useProvidersPage refresh callbacks keep active filters/search', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (providersApi.getProviders as jest.Mock).mockResolvedValue(emptyResponse);
    (providersApi.setupDefaultProviders as jest.Mock).mockResolvedValue({
      created_providers: [{ id: 'p1' }],
    });
    (providersApi.testAllProviders as jest.Mock).mockResolvedValue({
      summary: { successful: 1, failed: 0 },
    });
  });

  async function renderWithActiveSearch() {
    const hook = renderHook(() => useProvidersPage());
    await waitFor(() => expect(providersApi.getProviders).toHaveBeenCalledTimes(1));

    act(() => {
      hook.result.current.handleSearch('anthropic');
      hook.result.current.handleFilterChange({ provider_type: 'anthropic' });
    });
    await waitFor(() =>
      expect(providersApi.getProviders).toHaveBeenLastCalledWith(
        expect.objectContaining({ search: 'anthropic', provider_type: 'anthropic' }),
      ),
    );
    (providersApi.getProviders as jest.Mock).mockClear();
    return hook;
  }

  it('handleRefresh reloads with the current filters and search', async () => {
    const { result } = await renderWithActiveSearch();

    await act(async () => {
      result.current.handleRefresh();
    });

    await waitFor(() => expect(providersApi.getProviders).toHaveBeenCalledTimes(1));
    expect(providersApi.getProviders).toHaveBeenLastCalledWith(
      expect.objectContaining({ search: 'anthropic', provider_type: 'anthropic' }),
    );
  });

  it('handleBulkTest reloads with the current filters and search', async () => {
    const { result } = await renderWithActiveSearch();

    await act(async () => {
      await result.current.handleBulkTest();
    });

    expect(providersApi.getProviders).toHaveBeenLastCalledWith(
      expect.objectContaining({ search: 'anthropic', provider_type: 'anthropic' }),
    );
  });

  it('handleSetupDefaults reloads with the current filters and search', async () => {
    const { result } = await renderWithActiveSearch();

    await act(async () => {
      await result.current.handleSetupDefaults(['anthropic']);
    });

    expect(providersApi.getProviders).toHaveBeenLastCalledWith(
      expect.objectContaining({ search: 'anthropic', provider_type: 'anthropic' }),
    );
  });
});
