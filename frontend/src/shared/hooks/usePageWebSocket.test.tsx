import { renderHook, act } from '@testing-library/react';
import { usePageWebSocket } from './usePageWebSocket';
import { useWebSocket } from '@/shared/hooks/useWebSocket';

jest.mock('@/shared/hooks/useWebSocket');
jest.mock('react-redux', () => ({
  ...jest.requireActual('react-redux'),
  useSelector: (selector: (state: unknown) => unknown) =>
    selector({ auth: { user: { id: 'u-1', account: { id: 'acct-1' } } } }),
}));

const mockedWebSocket = useWebSocket as jest.MockedFunction<typeof useWebSocket>;

// THE HOOK'S OWN SHARP EDGE (C13 follow-up / C2 review H1).
//
// `getChannelsToSubscribe` used to put `subscribeTo` in its dependency array
// by ARRAY IDENTITY. A caller passing an inline literal (`subscribeTo: ['x']`)
// hands the hook a fresh array every render, which recreated the callback,
// which re-ran the auto-subscribe effect, whose own `setActiveChannels` call
// triggers the next render — an infinite subscribe/unsubscribe loop. Lane 11
// worked around it caller-side (a module-level constant array); this fixes it
// inside the hook, on `subscribeTo`/`unsubscribeFrom` CONTENT, so every future
// caller is safe regardless of how it constructs the array.
//
// The assertion is a BOUND, not an exact count — the point is "it settles".

describe('usePageWebSocket subscription churn', () => {
  let subscribe: jest.Mock;

  beforeEach(() => {
    jest.clearAllMocks();
    subscribe = jest.fn(() => jest.fn());
    mockedWebSocket.mockReturnValue({
      isConnected: true,
      error: null,
      subscribe,
    } as unknown as ReturnType<typeof useWebSocket>);
  });

  it('settles when the caller passes a fresh inline subscribeTo literal every render', () => {
    // No module-level constant here — a brand new array literal each render,
    // exactly the caller shape that used to loop forever.
    const { rerender } = renderHook(() =>
      usePageWebSocket({ pageType: 'dashboard', subscribeTo: ['platformStatus'] })
    );

    act(() => {
      for (let i = 0; i < 5; i += 1) {
        rerender();
      }
    });

    const channels = subscribe.mock.calls.map((call) => call[0].channel);
    expect(channels).toContain('PlatformStatusChannel');
    expect(subscribe.mock.calls.length).toBeLessThan(10);
    expect(channels.filter((c) => c === 'PlatformStatusChannel').length).toBeLessThan(5);
  });
});
