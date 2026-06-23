import { renderHook, act } from '@testing-library/react';
import { useOnlineStatus } from './useOnlineStatus';

describe('useOnlineStatus', () => {
  beforeEach(() => jest.useFakeTimers());
  afterEach(() => {
    jest.useRealTimers();
    jest.restoreAllMocks();
  });

  it('initializes from navigator.onLine (online in jsdom) with no timestamps', () => {
    const { result } = renderHook(() => useOnlineStatus());
    expect(result.current.isOnline).toBe(true);
    expect(result.current.wasOffline).toBe(false);
    expect(result.current.lastOnlineAt).toBeNull();
    expect(result.current.lastOfflineAt).toBeNull();
  });

  it('flips to offline on the offline event and stamps lastOfflineAt', () => {
    const { result } = renderHook(() => useOnlineStatus());

    act(() => {
      window.dispatchEvent(new Event('offline'));
    });

    expect(result.current.isOnline).toBe(false);
    expect(result.current.wasOffline).toBe(true);
    expect(result.current.lastOfflineAt).toBeInstanceOf(Date);
  });

  it('flips back to online on the online event and stamps lastOnlineAt (wasOffline still set)', () => {
    const { result } = renderHook(() => useOnlineStatus());

    act(() => {
      window.dispatchEvent(new Event('offline'));
    });
    act(() => {
      window.dispatchEvent(new Event('online'));
    });

    expect(result.current.isOnline).toBe(true);
    expect(result.current.lastOnlineAt).toBeInstanceOf(Date);
    expect(result.current.wasOffline).toBe(true);
  });

  it('auto-clears wasOffline 5s after reconnecting', () => {
    const { result } = renderHook(() => useOnlineStatus());

    act(() => {
      window.dispatchEvent(new Event('offline'));
    });
    act(() => {
      window.dispatchEvent(new Event('online'));
    });
    expect(result.current.wasOffline).toBe(true);

    act(() => {
      jest.advanceTimersByTime(5000);
    });
    expect(result.current.wasOffline).toBe(false);
  });

  it('removes the online/offline listeners on unmount', () => {
    const removeSpy = jest.spyOn(window, 'removeEventListener');
    const { unmount } = renderHook(() => useOnlineStatus());

    unmount();

    expect(removeSpy).toHaveBeenCalledWith('online', expect.any(Function));
    expect(removeSpy).toHaveBeenCalledWith('offline', expect.any(Function));
  });
});
