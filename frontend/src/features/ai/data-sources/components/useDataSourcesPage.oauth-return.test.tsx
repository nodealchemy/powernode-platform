import { renderHook, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { useDataSourcesPage } from './useDataSourcesPage';
import { dataSourcesApi } from '@/shared/services/ai/DataSourcesApiService';

// x-com-provider campaign (I5): Api::V1::Ai::DataSourceOauthController#callback
// redirects the browser back to this page with ?oauth=success|failed[&data_source_id=
// ...][&error=...] instead of a raw JSON body. The hook must surface a toast, reopen
// the source's detail view, and strip the params so a refresh doesn't replay it.

jest.mock('@/shared/services/ai/DataSourcesApiService', () => ({
  dataSourcesApi: {
    getDataSources: jest.fn(),
    deleteDataSource: jest.fn(),
  },
}));

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

function renderWithEntry(initialEntry: string) {
  return renderHook(() => useDataSourcesPage(), {
    wrapper: ({ children }) => <MemoryRouter initialEntries={[initialEntry]}>{children}</MemoryRouter>,
  });
}

describe('useDataSourcesPage OAuth2 return handling', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (dataSourcesApi.getDataSources as jest.Mock).mockResolvedValue(emptyResponse);
  });

  it('shows a success toast and reopens the source detail view on ?oauth=success', async () => {
    const hook = renderWithEntry('/data-sources?oauth=success&data_source_id=ds-1');

    await waitFor(() => expect(hook.result.current.selectedDataSourceId).toBe('ds-1'));
    expect(mockAddNotification).toHaveBeenCalledWith(expect.objectContaining({ type: 'success' }));
  });

  it('shows an error toast (with the provider error message) on ?oauth=failed', async () => {
    const hook = renderWithEntry('/data-sources?oauth=failed&data_source_id=ds-1&error=access_denied');

    await waitFor(() => expect(hook.result.current.selectedDataSourceId).toBe('ds-1'));
    expect(mockAddNotification).toHaveBeenCalledWith(
      expect.objectContaining({ type: 'error', message: 'access_denied' })
    );
  });

  it('does not open any detail view when oauth=failed carries no data_source_id', async () => {
    const hook = renderWithEntry('/data-sources?oauth=failed&error=state_expired');

    await waitFor(() => expect(mockAddNotification).toHaveBeenCalled());
    expect(hook.result.current.selectedDataSourceId).toBeNull();
  });

  it('does nothing when there is no oauth query param', async () => {
    renderWithEntry('/data-sources');

    await waitFor(() => expect(dataSourcesApi.getDataSources).toHaveBeenCalled());
    expect(mockAddNotification).not.toHaveBeenCalled();
  });
});
