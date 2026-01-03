import { renderHook, waitFor, act } from '@testing-library/react';
import { useWebhookEvents } from '../hooks/useWebhookEvents';
import { gitProvidersApi } from '@/features/git-providers/services/gitProvidersApi';

jest.mock('@/features/git-providers/services/gitProvidersApi');

const mockGitProvidersApi = gitProvidersApi as jest.Mocked<typeof gitProvidersApi>;

describe('useWebhookEvents', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  const mockEvents = [
    {
      id: 'event-1',
      event_type: 'push',
      status: 'processed',
      payload: { ref: 'refs/heads/main' },
      created_at: new Date().toISOString(),
    },
    {
      id: 'event-2',
      event_type: 'pull_request',
      status: 'pending',
      payload: { action: 'opened' },
      created_at: new Date().toISOString(),
    },
  ];

  const mockStats = {
    total: 100,
    processed: 90,
    pending: 5,
    failed: 5,
  };

  it('fetches webhook events on mount', async () => {
    mockGitProvidersApi.getWebhookEvents.mockResolvedValue({
      events: mockEvents,
      pagination: { current_page: 1, total_pages: 1, total_count: 2 },
      stats: mockStats,
    });

    const { result } = renderHook(() => useWebhookEvents());

    expect(result.current.loading).toBe(true);

    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    expect(result.current.events).toHaveLength(2);
    expect(result.current.stats).toEqual(mockStats);
  });

  it('supports filtering by event type', async () => {
    mockGitProvidersApi.getWebhookEvents.mockResolvedValue({
      events: [mockEvents[0]],
      pagination: { current_page: 1, total_pages: 1, total_count: 1 },
      stats: mockStats,
    });

    // The hook uses eventType (camelCase) which is converted to event_type (snake_case) in API call
    const { result } = renderHook(() => useWebhookEvents({ eventType: 'push' }));

    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    expect(mockGitProvidersApi.getWebhookEvents).toHaveBeenCalledWith(
      expect.objectContaining({ event_type: 'push' })
    );
  });

  it('supports filtering by status', async () => {
    mockGitProvidersApi.getWebhookEvents.mockResolvedValue({
      events: [mockEvents[1]],
      pagination: { current_page: 1, total_pages: 1, total_count: 1 },
      stats: mockStats,
    });

    const { result } = renderHook(() => useWebhookEvents({ status: 'pending' }));

    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    expect(mockGitProvidersApi.getWebhookEvents).toHaveBeenCalledWith(
      expect.objectContaining({ status: 'pending' })
    );
  });

  it('handles pagination', async () => {
    mockGitProvidersApi.getWebhookEvents.mockResolvedValue({
      events: mockEvents,
      pagination: { current_page: 1, total_pages: 5, total_count: 100 },
      stats: mockStats,
    });

    const { result } = renderHook(() => useWebhookEvents());

    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    expect(result.current.pagination).toEqual({
      current_page: 1,
      total_pages: 5,
      total_count: 100,
    });
  });

  it('provides retry function for failed events', async () => {
    mockGitProvidersApi.getWebhookEvents.mockResolvedValue({
      events: mockEvents,
      pagination: { current_page: 1, total_pages: 1, total_count: 2 },
      stats: mockStats,
    });

    mockGitProvidersApi.retryWebhookEvent.mockResolvedValue({
      message: 'Retry initiated',
      event: { id: 'event-1', status: 'pending' },
    });

    const { result } = renderHook(() => useWebhookEvents());

    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    expect(typeof result.current.retryEvent).toBe('function');

    await act(async () => {
      await result.current.retryEvent('event-1');
    });

    expect(mockGitProvidersApi.retryWebhookEvent).toHaveBeenCalledWith('event-1');
  });

  it('handles errors gracefully', async () => {
    mockGitProvidersApi.getWebhookEvents.mockRejectedValue(new Error('Failed to fetch'));

    const { result } = renderHook(() => useWebhookEvents());

    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    expect(result.current.error).toBe('Failed to fetch');
    expect(result.current.events).toEqual([]);
  });

  it('provides refresh function', async () => {
    mockGitProvidersApi.getWebhookEvents.mockResolvedValue({
      events: mockEvents,
      pagination: { current_page: 1, total_pages: 1, total_count: 2 },
      stats: mockStats,
    });

    const { result } = renderHook(() => useWebhookEvents());

    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    expect(typeof result.current.refresh).toBe('function');

    // Initial call
    expect(mockGitProvidersApi.getWebhookEvents).toHaveBeenCalledTimes(1);

    // Refresh should trigger new API call
    await act(async () => {
      await result.current.refresh();
    });

    expect(mockGitProvidersApi.getWebhookEvents).toHaveBeenCalledTimes(2);
  });

  it('excludes "all" status from API call', async () => {
    mockGitProvidersApi.getWebhookEvents.mockResolvedValue({
      events: mockEvents,
      pagination: { current_page: 1, total_pages: 1, total_count: 2 },
      stats: mockStats,
    });

    const { result } = renderHook(() => useWebhookEvents({ status: 'all' }));

    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    // 'all' should be converted to undefined in the API call
    expect(mockGitProvidersApi.getWebhookEvents).toHaveBeenCalledWith(
      expect.objectContaining({ status: undefined })
    );
  });
});
