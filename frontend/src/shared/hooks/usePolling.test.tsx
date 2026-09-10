import React from 'react';
import { renderHook, act } from '@testing-library/react';
import { usePolling } from './usePolling';

// Review F3 (review-lane4-c8.md): usePolling.ts shipped with 20 call sites
// and zero direct tests of its own polling contract. Each case below asserts
// both arms per the review's checklist ("a check that cannot fail
// differently is not a check").
describe('usePolling', () => {
  beforeEach(() => jest.useFakeTimers());
  afterEach(() => jest.useRealTimers());

  it('enabled: false starts no timer and never calls fn; flipping to true starts it', () => {
    const fn = jest.fn();
    const { rerender } = renderHook(({ enabled }) => usePolling(fn, 1000, { enabled }), {
      initialProps: { enabled: false },
    });

    act(() => {
      jest.advanceTimersByTime(5000);
    });
    expect(fn).not.toHaveBeenCalled();

    rerender({ enabled: true });
    act(() => {
      jest.advanceTimersByTime(1000);
    });
    expect(fn).toHaveBeenCalledTimes(1);
  });

  it('immediate: true calls fn once at t=0 and once per tick; immediate: false calls nothing at t=0', () => {
    const withImmediate = jest.fn();
    renderHook(() => usePolling(withImmediate, 1000, { immediate: true }));
    expect(withImmediate).toHaveBeenCalledTimes(1);
    act(() => {
      jest.advanceTimersByTime(1000);
    });
    expect(withImmediate).toHaveBeenCalledTimes(2);

    const withoutImmediate = jest.fn();
    renderHook(() => usePolling(withoutImmediate, 1000));
    expect(withoutImmediate).not.toHaveBeenCalled();
    act(() => {
      jest.advanceTimersByTime(1000);
    });
    expect(withoutImmediate).toHaveBeenCalledTimes(1);
  });

  it('intervalMs <= 0 starts no timer; intervalMs > 0 ticks normally', () => {
    const zeroFn = jest.fn();
    renderHook(() => usePolling(zeroFn, 0));
    act(() => {
      jest.advanceTimersByTime(10000);
    });
    expect(zeroFn).not.toHaveBeenCalled();

    const negativeFn = jest.fn();
    renderHook(() => usePolling(negativeFn, -500));
    act(() => {
      jest.advanceTimersByTime(10000);
    });
    expect(negativeFn).not.toHaveBeenCalled();

    const positiveFn = jest.fn();
    renderHook(() => usePolling(positiveFn, 1000));
    act(() => {
      jest.advanceTimersByTime(3000);
    });
    expect(positiveFn).toHaveBeenCalledTimes(3);
  });

  it('deps change clears the old timer (it never fires) and starts a fresh one', () => {
    const fn = jest.fn();
    const { rerender } = renderHook(({ tick }) => usePolling(fn, 1000, { deps: [tick] }), {
      initialProps: { tick: 0 },
    });

    act(() => {
      jest.advanceTimersByTime(500);
    });
    expect(fn).not.toHaveBeenCalled();

    // Changing deps mid-cycle must clear the original timer, not let it
    // fire alongside the new one.
    rerender({ tick: 1 });

    act(() => {
      jest.advanceTimersByTime(500);
    });
    // Original timer would have fired at the 1000ms mark (500 + 500) if it
    // had survived the deps change. It must not have.
    expect(fn).not.toHaveBeenCalled();

    act(() => {
      jest.advanceTimersByTime(500);
    });
    // The new timer, started fresh at the deps change, fires at its own
    // 1000ms mark (500ms after the second advance above).
    expect(fn).toHaveBeenCalledTimes(1);
  });

  it('unmount clears the timer; no further calls land', () => {
    const fn = jest.fn();
    const { unmount } = renderHook(() => usePolling(fn, 1000));

    act(() => {
      jest.advanceTimersByTime(1000);
    });
    expect(fn).toHaveBeenCalledTimes(1);

    unmount();

    act(() => {
      jest.advanceTimersByTime(5000);
    });
    expect(fn).toHaveBeenCalledTimes(1);
  });

  it('invokes the latest callback without restarting the timer when deps excludes fn', () => {
    // Review F4: fn is held in a ref and refreshed every render, so a caller
    // whose explicit `deps` omits `fn` still gets the current closure
    // without the effect (and its underlying setInterval) restarting.
    const fnA = jest.fn();
    const fnB = jest.fn();
    const setIntervalSpy = jest.spyOn(global, 'setInterval');

    const { rerender } = renderHook(({ fn }) => usePolling(fn, 1000, { deps: [] }), {
      initialProps: { fn: fnA },
    });
    expect(setIntervalSpy).toHaveBeenCalledTimes(1);

    rerender({ fn: fnB });
    // deps is `[]` — the effect must not have re-run, so no second timer.
    expect(setIntervalSpy).toHaveBeenCalledTimes(1);

    act(() => {
      jest.advanceTimersByTime(1000);
    });
    expect(fnA).not.toHaveBeenCalled();
    expect(fnB).toHaveBeenCalledTimes(1);

    setIntervalSpy.mockRestore();
  });

  it('is safe under StrictMode: no leaked duplicate interval from the double render-phase invoke', () => {
    // StrictMode double-invokes the render phase in this test environment
    // (verified: the component function body runs twice per mount), which
    // is where a bug would show up as two concurrent intervals — e.g. if
    // `fnRef.current = fn` inside render, rather than the effect itself,
    // were what started the timer. It doesn't: exactly one `immediate` call
    // lands at mount, and exactly one further call lands per subsequent
    // tick. Two intervals running concurrently would double the per-tick
    // count instead.
    const fn = jest.fn();
    renderHook(() => usePolling(fn, 1000, { immediate: true }), {
      wrapper: ({ children }) => <React.StrictMode>{children}</React.StrictMode>,
    });
    expect(fn).toHaveBeenCalledTimes(1);

    act(() => {
      jest.advanceTimersByTime(1000);
    });
    expect(fn).toHaveBeenCalledTimes(2);

    act(() => {
      jest.advanceTimersByTime(1000);
    });
    expect(fn).toHaveBeenCalledTimes(3);
  });
});
