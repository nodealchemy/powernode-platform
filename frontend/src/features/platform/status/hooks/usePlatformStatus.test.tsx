import { renderHook, act, waitFor } from '@testing-library/react';
import { usePlatformStatus, STATUS_POLL_MS, RECONCILE_DEBOUNCE_MS } from './usePlatformStatus';
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

  describe('the poll is a genuine fallback, gated on the CHANNEL', () => {
    beforeEach(() => jest.useFakeTimers());
    afterEach(() => jest.useRealTimers());

    /** Deliver the message PlatformStatusChannel transmits when it accepts us. */
    const establishChannel = () =>
      act(() => {
        lastOnDataUpdate?.({
          channel: 'platformStatus',
          type: 'connection_established',
          data: { type: 'connection_established', scope: 'account' },
          timestamp: new Date(),
        });
      });

    it('does NOT poll once the channel has accepted the subscription', async () => {
      mockSocket(true);
      const { result } = renderHook(() => usePlatformStatus({}));
      await act(async () => {
        await Promise.resolve();
      });
      establishChannel();
      expect(result.current.isLive).toBe(true);
      const afterMount = mockedApi.fetchComponentStatuses.mock.calls.length;

      act(() => {
        jest.advanceTimersByTime(STATUS_POLL_MS * 3);
      });

      expect(mockedApi.fetchComponentStatuses).toHaveBeenCalledTimes(afterMount);
    });

    it('DOES poll while the cable is up but the channel has NOT accepted us', async () => {
      // The arm the C2 review found missing (M1). `PlatformStatusChannel`
      // rejects a subscription with no current_user and one naming an account
      // the viewer may not read; on both paths the CABLE stays up. A poll gated
      // on `isConnected` would stay off forever while the page silently stopped
      // updating — the same defect this design set out to avoid, from the other
      // side.
      mockSocket(true);
      const { result } = renderHook(() => usePlatformStatus({}));
      await act(async () => {
        await Promise.resolve();
      });
      expect(result.current.isConnected).toBe(true);
      expect(result.current.isLive).toBe(false);
      const afterMount = mockedApi.fetchComponentStatuses.mock.calls.length;

      act(() => {
        jest.advanceTimersByTime(STATUS_POLL_MS);
      });

      expect(mockedApi.fetchComponentStatuses.mock.calls.length).toBeGreaterThan(afterMount);
    });

    it('DOES poll while the cable is down', async () => {
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

    it('resumes polling when a live cable drops', async () => {
      // A dropped cable invalidates the subscription that was established over
      // it. Without the reset, a reconnect the channel REJECTS would keep the
      // poll off on the strength of a subscription that no longer exists.
      mockSocket(true);
      const { result, rerender } = renderHook(() => usePlatformStatus({}));
      await act(async () => {
        await Promise.resolve();
      });
      establishChannel();
      expect(result.current.isLive).toBe(true);

      mockSocket(false);
      rerender();
      expect(result.current.isLive).toBe(false);

      const afterDrop = mockedApi.fetchComponentStatuses.mock.calls.length;
      act(() => {
        jest.advanceTimersByTime(STATUS_POLL_MS);
      });
      expect(mockedApi.fetchComponentStatuses.mock.calls.length).toBeGreaterThan(afterDrop);
    });

    it('stays on the poll after a reconnect the channel never re-accepts (R7)', async () => {
      // The reconnect arm "resumes polling when a live cable drops" never
      // reached: the cable comes BACK, but PlatformStatusChannel does not send
      // connection_established again (it rejected us this time). Without the
      // reset-on-drop, the old acceptance would read as live and stop the poll.
      mockSocket(true);
      const { result, rerender } = renderHook(() => usePlatformStatus({}));
      await act(async () => {
        await Promise.resolve();
      });
      establishChannel();
      expect(result.current.isLive).toBe(true);

      mockSocket(false);
      rerender();
      mockSocket(true);
      rerender();

      expect(result.current.isConnected).toBe(true);
      expect(result.current.isLive).toBe(false);
      const afterReconnect = mockedApi.fetchComponentStatuses.mock.calls.length;
      act(() => {
        jest.advanceTimersByTime(STATUS_POLL_MS);
      });
      expect(mockedApi.fetchComponentStatuses.mock.calls.length).toBeGreaterThan(afterReconnect);
    });

    it("does not go live on ANOTHER channel's connection_established (R8)", async () => {
      // NotificationChannel transmits this message too (useNotificationWebSocket
      // handles it). Only the status channel's acceptance may stop the poll.
      mockSocket(true);
      const { result } = renderHook(() => usePlatformStatus({}));
      await act(async () => {
        await Promise.resolve();
      });

      act(() => {
        lastOnDataUpdate?.({
          channel: 'notifications',
          type: 'connection_established',
          data: { type: 'connection_established' },
          timestamp: new Date(),
        });
      });

      expect(result.current.isLive).toBe(false);
      const before = mockedApi.fetchComponentStatuses.mock.calls.length;
      act(() => {
        jest.advanceTimersByTime(STATUS_POLL_MS);
      });
      expect(mockedApi.fetchComponentStatuses.mock.calls.length).toBeGreaterThan(before);
    });

    it('coalesces a burst of transitions into ONE reconciling read', async () => {
      // C2 review L1. This is the property that keeps a forty-component sweep
      // from becoming forty list reads, and nothing asserted it. Both arms:
      // nothing inside the window, exactly one after it.
      mockSocket(true);
      renderHook(() => usePlatformStatus({}));
      await act(async () => {
        await Promise.resolve();
      });
      establishChannel();
      const before = mockedApi.fetchComponentStatuses.mock.calls.length;

      for (let i = 0; i < 6; i += 1) {
        act(() => {
          lastOnDataUpdate?.({
            channel: 'platformStatus',
            type: 'component_status_changed',
            data: {
              type: 'component_status_changed',
              component_kind: 'ai_provider',
              component_ref: 'provider-1',
              to_verdict: 'degraded',
            },
            timestamp: new Date(),
          });
          jest.advanceTimersByTime(50);
        });
      }
      expect(mockedApi.fetchComponentStatuses).toHaveBeenCalledTimes(before);

      await act(async () => {
        jest.advanceTimersByTime(RECONCILE_DEBOUNCE_MS);
        await Promise.resolve();
      });
      expect(mockedApi.fetchComponentStatuses).toHaveBeenCalledTimes(before + 1);
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
        'platform.status.drawer.node_instance.signals': () => null,
      });
    });

    await waitFor(() =>
      expect(mockedApi.fetchComponentStatuses.mock.calls.length).toBeGreaterThan(before)
    );
    await waitFor(() => expect(result.current.rows).toHaveLength(2));
  });

  it('keeps every KIND it has seen in the option set, even once a kind is selected', async () => {
    // C2 review M2 — the same union the plane selector got, for the same reason.
    // `rows` is the FILTERED response, so a Kind selector derived from it drops
    // to "All kinds" plus the one already chosen.
    mockedApi.fetchComponentStatuses.mockResolvedValueOnce(
      indexResult([
        row({ id: 'a', component_kind: 'ai_provider' }),
        row({ id: 'b', component_ref: 'h1', component_kind: 'docker_host' }),
      ])
    );
    const { result, rerender } = renderHook(({ q }) => usePlatformStatus(q), {
      initialProps: { q: {} as Record<string, string> },
    });
    await waitFor(() =>
      expect(result.current.knownKinds).toEqual(['ai_provider', 'docker_host'])
    );

    mockedApi.fetchComponentStatuses.mockResolvedValue(
      indexResult([row({ id: 'b', component_ref: 'h1', component_kind: 'docker_host' })])
    );
    rerender({ q: { kind: 'docker_host' } });

    await waitFor(() => expect(result.current.rows).toHaveLength(1));
    expect(result.current.knownKinds).toEqual(['ai_provider', 'docker_host']);
  });

  it('drops a stale response rather than letting it overwrite a newer one', async () => {
    // C2 review L2. Five things call `load` — the filter effect, the poll, the
    // reconcile, the registry bump and the Refresh button — and responses are
    // not ordered. Applying an older one on arrival would show the wrong rows
    // AND stamp `lastLoadedAt` with the wrong instant, which is the header's
    // "read Ns ago" basis.
    let releaseFirst: (value: api.ComponentStatusIndexResult) => void = () => {};
    const first = new Promise<api.ComponentStatusIndexResult>((resolve) => {
      releaseFirst = resolve;
    });

    mockedApi.fetchComponentStatuses.mockReturnValueOnce(first);
    mockedApi.fetchComponentStatuses.mockResolvedValue(
      indexResult([row({ id: 'new', display_name: 'the newer answer' })])
    );

    const { result } = renderHook(() => usePlatformStatus({}));

    // The second read starts and finishes while the first is still in flight.
    await act(async () => {
      result.current.refresh();
      await Promise.resolve();
      await Promise.resolve();
    });
    await waitFor(() => expect(result.current.rows[0]?.display_name).toBe('the newer answer'));

    // Now the older one lands. It must be discarded, not merged.
    await act(async () => {
      releaseFirst(indexResult([row({ id: 'old', display_name: 'the STALE answer' })]));
      await Promise.resolve();
      await Promise.resolve();
    });

    expect(result.current.rows[0]?.display_name).toBe('the newer answer');
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
