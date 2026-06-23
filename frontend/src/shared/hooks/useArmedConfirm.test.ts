import { renderHook, act } from '@testing-library/react';
import { useArmedConfirm } from './useArmedConfirm';

describe('useArmedConfirm', () => {
  beforeEach(() => jest.useFakeTimers());
  afterEach(() => jest.useRealTimers());

  it('starts disarmed', () => {
    const { result } = renderHook(() => useArmedConfirm(jest.fn()));
    expect(result.current.armed).toBe(false);
  });

  it('arms on the first trigger without firing onConfirm', () => {
    const onConfirm = jest.fn();
    const { result } = renderHook(() => useArmedConfirm(onConfirm));

    act(() => result.current.trigger());

    expect(result.current.armed).toBe(true);
    expect(onConfirm).not.toHaveBeenCalled();
  });

  it('fires onConfirm exactly once on the second trigger within the window, then disarms', () => {
    const onConfirm = jest.fn();
    const { result } = renderHook(() => useArmedConfirm(onConfirm));

    act(() => result.current.trigger()); // arm
    act(() => result.current.trigger()); // confirm

    expect(onConfirm).toHaveBeenCalledTimes(1);
    expect(result.current.armed).toBe(false);
  });

  it('disarms and calls onTimeout when the arm window expires', () => {
    const onConfirm = jest.fn();
    const onTimeout = jest.fn();
    const { result } = renderHook(() =>
      useArmedConfirm(onConfirm, { armWindowMs: 1000, onTimeout })
    );

    act(() => result.current.trigger());
    expect(result.current.armed).toBe(true);

    act(() => {
      jest.advanceTimersByTime(1000);
    });

    expect(result.current.armed).toBe(false);
    expect(onTimeout).toHaveBeenCalledTimes(1);
    expect(onConfirm).not.toHaveBeenCalled();
  });

  it('reset() force-disarms and prevents a pending timeout from firing', () => {
    const onTimeout = jest.fn();
    const { result } = renderHook(() =>
      useArmedConfirm(jest.fn(), { armWindowMs: 1000, onTimeout })
    );

    act(() => result.current.trigger());
    act(() => result.current.reset());
    expect(result.current.armed).toBe(false);

    act(() => {
      jest.advanceTimersByTime(2000);
    });
    expect(onTimeout).not.toHaveBeenCalled();
  });

  it('clears the pending timer on unmount (no leaked callback)', () => {
    const onTimeout = jest.fn();
    const { result, unmount } = renderHook(() =>
      useArmedConfirm(jest.fn(), { armWindowMs: 1000, onTimeout })
    );

    act(() => result.current.trigger());
    unmount();

    act(() => {
      jest.advanceTimersByTime(2000);
    });
    expect(onTimeout).not.toHaveBeenCalled();
  });

  it('confirms with the latest onConfirm when the callback changes while armed (ref-based)', () => {
    const first = jest.fn();
    const second = jest.fn();
    const { result, rerender } = renderHook(({ cb }) => useArmedConfirm(cb), {
      initialProps: { cb: first },
    });

    act(() => result.current.trigger()); // arm while cb === first
    rerender({ cb: second }); // swap callback mid-window
    act(() => result.current.trigger()); // confirm

    expect(second).toHaveBeenCalledTimes(1);
    expect(first).not.toHaveBeenCalled();
  });
});
