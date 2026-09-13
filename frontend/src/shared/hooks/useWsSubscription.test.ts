import { renderHook } from '@testing-library/react';
import { useWsSubscription } from './useWsSubscription';

jest.mock('@/shared/services/WebSocketManager', () => ({
  wsManager: {
    subscribe: jest.fn(),
  },
}));

import { wsManager } from '@/shared/services/WebSocketManager';

const mockedSubscribe = wsManager.subscribe as jest.Mock;

describe('useWsSubscription', () => {
  beforeEach(() => {
    mockedSubscribe.mockReset();
  });

  it('subscribes on mount with the given channel and params', () => {
    mockedSubscribe.mockReturnValue(jest.fn());
    const onMessage = jest.fn();
    const onError = jest.fn();

    renderHook(() =>
      useWsSubscription({ channel: 'SystemFleetChannel', params: { account_id: 'acct-1' }, onMessage, onError })
    );

    expect(mockedSubscribe).toHaveBeenCalledTimes(1);
    const call = mockedSubscribe.mock.calls[0][0];
    expect(call.channel).toBe('SystemFleetChannel');
    expect(call.params).toEqual({ account_id: 'acct-1' });
    expect(typeof call.onMessage).toBe('function');
    expect(typeof call.onError).toBe('function');
  });

  it('does not subscribe when enabled is false; subscribes once flipped to true', () => {
    mockedSubscribe.mockReturnValue(jest.fn());

    const { rerender } = renderHook(
      ({ enabled }) => useWsSubscription({ channel: 'SystemFleetChannel' }, { enabled, deps: [enabled] }),
      { initialProps: { enabled: false } }
    );

    expect(mockedSubscribe).not.toHaveBeenCalled();

    rerender({ enabled: true });

    expect(mockedSubscribe).toHaveBeenCalledTimes(1);
  });

  it('unsubscribes on unmount', () => {
    const unsubscribe = jest.fn();
    mockedSubscribe.mockReturnValue(unsubscribe);

    const { unmount } = renderHook(() => useWsSubscription({ channel: 'SystemFleetChannel' }));

    expect(unsubscribe).not.toHaveBeenCalled();
    unmount();
    expect(unsubscribe).toHaveBeenCalledTimes(1);
  });

  it('unsubscribes the old channel and subscribes a new one when deps change', () => {
    const firstUnsubscribe = jest.fn();
    const secondUnsubscribe = jest.fn();
    mockedSubscribe.mockReturnValueOnce(firstUnsubscribe).mockReturnValueOnce(secondUnsubscribe);

    const { rerender } = renderHook(
      ({ accountId }) =>
        useWsSubscription(
          { channel: 'SystemFleetChannel', params: { account_id: accountId } },
          { deps: [accountId] }
        ),
      { initialProps: { accountId: 'acct-1' } }
    );

    expect(mockedSubscribe).toHaveBeenCalledTimes(1);
    expect(firstUnsubscribe).not.toHaveBeenCalled();

    rerender({ accountId: 'acct-2' });

    // The old subscription was torn down (both arms: old cleared, new started).
    expect(firstUnsubscribe).toHaveBeenCalledTimes(1);
    expect(mockedSubscribe).toHaveBeenCalledTimes(2);
    expect(mockedSubscribe.mock.calls[1][0].params).toEqual({ account_id: 'acct-2' });
    expect(secondUnsubscribe).not.toHaveBeenCalled();
  });

  it('invokes the latest onMessage/onError without restarting the subscription when deps excludes them', () => {
    mockedSubscribe.mockReturnValue(jest.fn());
    const onMessageA = jest.fn();
    const onMessageB = jest.fn();

    const { rerender } = renderHook(
      ({ onMessage }) => useWsSubscription({ channel: 'SystemFleetChannel', onMessage }, { deps: [] }),
      { initialProps: { onMessage: onMessageA } }
    );

    expect(mockedSubscribe).toHaveBeenCalledTimes(1);
    const capturedOnMessage = mockedSubscribe.mock.calls[0][0].onMessage as (data: unknown) => void;

    rerender({ onMessage: onMessageB });

    // deps is `[]` — the effect must not have re-run, so no second subscribe call.
    expect(mockedSubscribe).toHaveBeenCalledTimes(1);

    // The wsManager-captured handler (identity fixed at subscribe time) must
    // still route to the LATEST render's onMessage via the ref, not the
    // stale onMessageA closure.
    capturedOnMessage({ hello: 'world' });
    expect(onMessageA).not.toHaveBeenCalled();
    expect(onMessageB).toHaveBeenCalledWith({ hello: 'world' });
  });
});
