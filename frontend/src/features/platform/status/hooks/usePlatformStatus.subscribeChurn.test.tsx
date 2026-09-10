import { renderHook, act } from '@testing-library/react';
import { usePlatformStatus } from './usePlatformStatus';
import * as api from '@/features/platform/status/api/platformStatusApi';
import { useWebSocket } from '@/shared/hooks/useWebSocket';
import type { ComponentStatusIndexResult } from '@/features/platform/status/api/platformStatusApi';

jest.mock('@/features/platform/status/api/platformStatusApi');
jest.mock('@/shared/hooks/useWebSocket');
jest.mock('react-redux', () => ({
  ...jest.requireActual('react-redux'),
  useSelector: (selector: (state: unknown) => unknown) =>
    selector({ auth: { user: { id: 'u-1', account: { id: 'acct-1' } } } }),
}));

const mockedApi = api as jest.Mocked<typeof api>;
const mockedWebSocket = useWebSocket as jest.MockedFunction<typeof useWebSocket>;

// THE SUBSCRIPTION-CHURN GUARD (C2 review H1).
//
// This spec deliberately does NOT mock `usePageWebSocket`. Every other suite in
// this feature does — which is exactly why none of them could see the defect it
// exists to catch, and why C2 shipped an infinite render loop that no test went
// red on.
//
// The mechanism: `usePageWebSocket` puts `subscribeTo` in the dependency list of
// `getChannelsToSubscribe`, which is in the dependency list of the auto-subscribe
// effect, whose cleanup AND body both call `setActiveChannels`. Pass a fresh
// array literal each render and that effect re-runs forever — in production
// tearing down and re-creating the ActionCable subscription on every iteration,
// on the one page an operator opens during an outage.
//
// The assertion is a BOUND on `subscribe` calls, not an exact count: the point is
// "it settles", and pinning the exact number would make this spec fail on an
// unrelated render-count change while still passing on a slow loop.

const indexResult = (): ComponentStatusIndexResult => ({
  component_statuses: [],
  filters: {},
  unknown_environment: false,
  pagination: { current_page: 1, per_page: 100, total_count: 0, total_pages: 1 },
});

describe('usePlatformStatus subscription churn', () => {
  let subscribe: jest.Mock;

  beforeEach(() => {
    jest.clearAllMocks();
    subscribe = jest.fn(() => jest.fn());
    mockedWebSocket.mockReturnValue({
      isConnected: true,
      error: null,
      subscribe,
    } as unknown as ReturnType<typeof useWebSocket>);
    mockedApi.fetchComponentStatuses.mockResolvedValue(indexResult());
    mockedApi.fetchStatusRollup.mockResolvedValue(undefined as never);
  });

  it('settles: subscribing to PlatformStatusChannel a bounded number of times', async () => {
    const { rerender } = renderHook(() => usePlatformStatus({}));

    await act(async () => {
      await Promise.resolve();
    });
    // Several parent re-renders, the way a page with live data actually behaves.
    for (let i = 0; i < 5; i += 1) {
      rerender();
    }
    await act(async () => {
      await Promise.resolve();
    });

    // With the module-level STATUS_CHANNELS constant this settles in the low
    // single digits. With an inline `subscribeTo: ['platformStatus']` literal
    // React aborts with "Maximum update depth exceeded" before reaching this
    // line at all, so the failure is loud rather than a number being off.
    // The page's pageType is 'dashboard', which brings `notifications` along, so
    // PlatformStatusChannel is one of the subscriptions rather than the first.
    const channels = subscribe.mock.calls.map((call) => call[0].channel);

    expect(channels).toContain('PlatformStatusChannel');
    expect(subscribe.mock.calls.length).toBeLessThan(10);
    // Bounded ON THE STATUS CHANNEL specifically: an overall bound could be met
    // while this one churned and another settled.
    expect(channels.filter((c) => c === 'PlatformStatusChannel').length).toBeLessThan(5);
  });
});
