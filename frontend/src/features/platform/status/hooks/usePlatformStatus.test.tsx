import { renderHook, act, waitFor } from '@testing-library/react';
import { usePlatformStatus, STATUS_POLL_MS } from './usePlatformStatus';
import * as api from '@/features/platform/status/api/platformStatusApi';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import { featureRegistry } from '@/shared/services/featureRegistry';
import type { ComponentStatusSummary } from '@/shared/types/platformStatus';

jest.mock('@/features/platform/status/api/platformStatusApi');
jest.mock('@/shared/hooks/usePageWebSocket');

const mockedApi = api as jest.Mocked<typeof api>;
const mockedSocket = usePageWebSocket as jest.MockedFunction<typeof usePageWebSocket>;

// usePlatformStatus (C2) — the page's data layer.
//
// The property under test that is easiest to get wrong and hardest to see is
// the POLL'S RELATIONSHIP TO THE SOCKET. design §6 asks for the poll to be a
// "genuine fallback"; a poll that runs alongside a healthy channel still makes
// the page look correct, so nothing fails when it regresses. Both arms are
// asserted below.

const row = (overrides: Partial<ComponentStatusSummary> = {}): ComponentStatusSummary => ({
  id: overrides.id ?? 'row-1',
  component_kind: 'ai_provider',
  component_ref: 'provider-1',
  display_name: 'Anthropic',
  verdict: 'ok',
  held: false,
  held_by_intent: false,
  unhealthy: false,
  shared: false,
  scope: 'account',
  environment_id: null,
  plane: 'none',
  presentation: { icon: 'Plug', label: 'AI Provider', group_order: 10 },
  condition_count: 2,
  reason: null,
  remediation_state: 'none',
  observed_at: '2026-09-10T12:00:00Z',
  last_seen_sweep_at: '2026-09-10T12:00:00Z',
  last_transition_at: null,
  ...overrides,
});

const indexResult = (rows: ComponentStatusSummary[]): api.ComponentStatusIndexResult => ({
  component_statuses: rows,
  filters: {},
  unknown_environment: false,
  pagination: { current_page: 1, per_page: 100, total_count: rows.length, total_pages: 1 },
});

const rollupResult = () => ({
  rollup: {
    verdict: 'ok' as const,
    held_count: 0,
    counts_by_verdict: { ok: 1, held: 0, progressing: 0, not_measured: 0, degraded: 0, down: 0 },
    total: 1,
  },
  shared: {
    verdict: 'ok' as const,
    held_count: 0,
    counts_by_verdict: { ok: 0, held: 0, progressing: 0, not_measured: 0, degraded: 0, down: 0 },
    total: 0,
  },
  by_kind: {},
  shared_by_kind: {},
  filters: {},
  unknown_environment: false,
  observed_at: '2026-09-10T12:00:00Z',
});

/** Captures the onDataUpdate callback so a test can push a broadcast at it. */
let lastOnDataUpdate: ((update: { channel: string; type: string; data: unknown; timestamp: Date }) => void) | undefined;

const mockSocket = (isConnected: boolean) => {
  mockedSocket.mockImplementation((options) => {
    lastOnDataUpdate = options.onDataUpdate;
    return {
      isConnected,
      error: null,
      activeChannels: isConnected ? ['platformStatus'] : [],
      subscribeToChannel: jest.fn(),
      unsubscribeFromChannel: jest.fn(),
    };
  });
};

describe('usePlatformStatus', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    featureRegistry.clear();
    mockedApi.fetchComponentStatuses.mockResolvedValue(indexResult([row()]));
    mockedApi.fetchStatusRollup.mockResolvedValue(rollupResult());
    mockSocket(true);
  });

  it('loads rows and the rollup on mount', async () => {
    const { result } = renderHook(() => usePlatformStatus({}));

    await waitFor(() => expect(result.current.loading).toBe(false));
    expect(result.current.rows).toHaveLength(1);
    expect(result.current.rollup?.rollup.verdict).toBe('ok');
    expect(result.current.totalCount).toBe(1);
  });

  it('reports the read failing rather than rendering an empty platform', async () => {
    // Both arms of the honesty oracle: an error is surfaced AND the rows stay
    // empty, so nothing downstream can mistake a failed read for a healthy one.
    mockedApi.fetchComponentStatuses.mockRejectedValueOnce(new Error('boom'));
    const { result } = renderHook(() => usePlatformStatus({}));

    await waitFor(() => expect(result.current.loading).toBe(false));
    expect(result.current.error).toBe('boom');
    expect(result.current.rows).toEqual([]);
  });

  describe('the poll is a genuine fallback', () => {
    beforeEach(() => jest.useFakeTimers());
    afterEach(() => jest.useRealTimers());

    it('does NOT poll while the socket is connected', async () => {
      mockSocket(true);
      renderHook(() => usePlatformStatus({}));
      await act(async () => {
        await Promise.resolve();
      });
      const afterMount = mockedApi.fetchComponentStatuses.mock.calls.length;

      act(() => {
        jest.advanceTimersByTime(STATUS_POLL_MS * 3);
      });

      expect(mockedApi.fetchComponentStatuses).toHaveBeenCalledTimes(afterMount);
    });

    it('DOES poll while the socket is down', async () => {
      mockSocket(false);
      renderHook(() => usePlatformStatus({}));
      await act(async () => {
        await Promise.resolve();
      });
      const afterMount = mockedApi.fetchComponentStatuses.mock.calls.length;

      act(() => {
        jest.advanceTimersByTime(STATUS_POLL_MS);
      });

      expect(mockedApi.fetchComponentStatuses.mock.calls.length).toBeGreaterThan(afterMount);
    });
  });

  describe('live transitions', () => {
    it('patches the verdict a transition carries', async () => {
      const { result } = renderHook(() => usePlatformStatus({}));
      await waitFor(() => expect(result.current.rows).toHaveLength(1));

      act(() => {
        lastOnDataUpdate?.({
          channel: 'platformStatus',
          type: 'component_status_changed',
          data: {
            type: 'component_status_changed',
            component_kind: 'ai_provider',
            component_ref: 'provider-1',
            from_verdict: 'ok',
            to_verdict: 'down',
            reason: 'CredentialsRejected',
            occurred_at: '2026-09-10T13:00:00Z',
          },
          timestamp: new Date(),
        });
      });

      expect(result.current.rows[0].verdict).toBe('down');
      expect(result.current.rows[0].reason).toBe('CredentialsRejected');
      // Derived flags follow the verdict; `held_by_intent` does NOT, because the
      // payload does not carry it and guessing would be an invention.
      expect(result.current.rows[0].unhealthy).toBe(true);
      expect(result.current.rows[0].held).toBe(false);
    });

    it('drops a removed row rather than leaving a stale verdict on screen', async () => {
      const { result } = renderHook(() => usePlatformStatus({}));
      await waitFor(() => expect(result.current.rows).toHaveLength(1));

      act(() => {
        lastOnDataUpdate?.({
          channel: 'platformStatus',
          type: 'component_status_changed',
          data: {
            type: 'component_status_changed',
            component_kind: 'ai_provider',
            component_ref: 'provider-1',
            from_verdict: 'ok',
            to_verdict: null,
            removed: true,
          },
          timestamp: new Date(),
        });
      });

      expect(result.current.rows).toHaveLength(0);
    });

    it('ignores messages from another channel and other message types', async () => {
      // The negative arm. onDataUpdate fires for EVERY channel the page is
      // subscribed to, so a hook that did not check would apply a notification
      // payload as a status transition.
      const { result } = renderHook(() => usePlatformStatus({}));
      await waitFor(() => expect(result.current.rows).toHaveLength(1));

      act(() => {
        lastOnDataUpdate?.({
          channel: 'notifications',
          type: 'component_status_changed',
          data: {
            type: 'component_status_changed',
            component_kind: 'ai_provider',
            component_ref: 'provider-1',
            to_verdict: 'down',
          },
          timestamp: new Date(),
        });
        lastOnDataUpdate?.({
          channel: 'platformStatus',
          type: 'connection_established',
          data: { type: 'connection_established' },
          timestamp: new Date(),
        });
      });

      expect(result.current.rows[0].verdict).toBe('ok');
    });
  });

  it('re-reads when the feature registry version changes', async () => {
    const { result } = renderHook(() => usePlatformStatus({}));
    await waitFor(() => expect(result.current.rows).toHaveLength(1));
    const before = mockedApi.fetchComponentStatuses.mock.calls.length;

    // An extension registering at runtime brings its own contributors, so the
    // set of kinds the server can report is not fixed at mount.
    mockedApi.fetchComponentStatuses.mockResolvedValue(
      indexResult([row(), row({ id: 'row-2', component_kind: 'node_instance', component_ref: 'i-2' })])
    );

    await act(async () => {
      featureRegistry.registerComponentSlots({
        'platform.status.drawer.node_instance': { component: () => null },
      });
    });

    await waitFor(() =>
      expect(mockedApi.fetchComponentStatuses.mock.calls.length).toBeGreaterThan(before)
    );
    await waitFor(() => expect(result.current.rows).toHaveLength(2));
  });

  it('keeps every plane it has seen in the option set, even once a plane is selected', async () => {
    // The union, not the current response. A filtered response carries only the
    // selected plane plus the plane-less rows, so deriving options from it would
    // collapse the selector to the option already chosen and strand the operator.
    mockedApi.fetchComponentStatuses.mockResolvedValueOnce(
      indexResult([
        row({ id: 'a', environment_id: 'env-dev', plane: 'in' }),
        row({ id: 'b', component_ref: 'p2', environment_id: 'env-ci', plane: 'in' }),
      ])
    );
    const { result, rerender } = renderHook(({ q }) => usePlatformStatus(q), {
      initialProps: { q: {} as Record<string, string> },
    });
    await waitFor(() => expect(result.current.knownEnvironmentIds).toEqual(['env-dev', 'env-ci']));

    mockedApi.fetchComponentStatuses.mockResolvedValue(
      indexResult([row({ id: 'a', environment_id: 'env-dev', plane: 'in' })])
    );
    rerender({ q: { environment: 'env-dev' } });

    await waitFor(() => expect(result.current.rows).toHaveLength(1));
    expect(result.current.knownEnvironmentIds).toEqual(['env-dev', 'env-ci']);
  });
});
