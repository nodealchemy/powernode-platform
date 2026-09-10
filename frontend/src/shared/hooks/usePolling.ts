import { useEffect, useRef } from 'react';

export interface UsePollingOptions {
  /**
   * Whether the interval should be running. Recompute this on every render
   * from whatever condition gated the original site's `setInterval` call
   * (e.g. `sessions.some(s => s.status === 'active')`) — passing a fresh
   * value each render is what makes the interval start/stop exactly when the
   * condition flips. Default true (always polling).
   */
  enabled?: boolean;
  /**
   * Call `fn` once immediately when the interval (re)starts, in addition to
   * on each tick. About a third of the sites this hook consolidates did this
   * (a first-paint fetch alongside the recurring one); the rest relied on a
   * separate mount effect for the initial call. Default false.
   */
  immediate?: boolean;
  /**
   * Explicit dependency list controlling when the interval restarts (its
   * `useEffect` re-runs — clearing the old timer and starting a new one).
   * Default `[fn, intervalMs, enabled]`. Pass this when the original site's
   * `useEffect` dependency array included something beyond `fn` itself (e.g.
   * `[containers, loadContainers]` — restarting the countdown on every data
   * update, not just when the callback identity or `enabled` changed) so the
   * restart cadence is preserved exactly, not approximated.
   */
  deps?: React.DependencyList;
}

/**
 * Runs `fn` on a fixed interval while `enabled` is true; clears it on
 * unmount or whenever the effect's dependencies change. Consolidates ~20
 * near-identical local `useEffect(() => { ...; const interval =
 * setInterval(fn, ms); return () => clearInterval(interval); }, [...])`
 * polling scaffolds (IMP-01a082a3) that varied in real, load-bearing ways —
 * see {@link UsePollingOptions}. `intervalMs <= 0` never starts a timer
 * (matches the sites that guarded a variable interval this way).
 *
 * Two sites this consolidation surveyed were NOT migrated because they don't
 * fit this shape: `aiOrchestrationMonitor.ts`'s heartbeat is a plain class
 * method with no component lifecycle to hook into, and
 * `AuditLogExport.tsx`'s progress bar is an imperative, self-terminating
 * animation started from an event handler, not a mount-driven poll.
 *
 * @example
 * // Always-on poll with an immediate first call (TeamActivityCard.tsx):
 * usePolling(loadTeams, 30000, { immediate: true });
 *
 * @example
 * // Conditional poll restarted whenever the gating data changes
 * // (ContainerList.tsx):
 * const hasActive = containers.some(c => ACTIVE_STATUSES.has(c.status));
 * usePolling(loadContainers, 5000, { enabled: hasActive, deps: [containers, loadContainers] });
 */
export function usePolling(fn: () => void, intervalMs: number, options: UsePollingOptions = {}): void {
  const { enabled = true, immediate = false, deps } = options;

  // Held in a ref and refreshed every render so the timer always invokes the
  // latest `fn`, independent of whether `fn`'s identity is part of the
  // effect's dependency array. Without this, a caller that passes explicit
  // `deps` omitting `fn` (while `fn` is recreated each render) would keep
  // calling the first render's closure for the lifetime of that dep
  // generation — a stale-closure hazard review F4 flagged. This does not
  // change restart cadence for any existing call site: the effect below
  // still re-runs on exactly the same dependency array it did before.
  const fnRef = useRef(fn);
  fnRef.current = fn;

  useEffect(() => {
    if (!enabled || intervalMs <= 0) return;
    if (immediate) fnRef.current();
    const interval = setInterval(() => fnRef.current(), intervalMs);
    return () => clearInterval(interval);
    // Dependency array is intentionally caller-controlled — see `deps` doc above.
  }, deps ?? [fn, intervalMs, enabled]);
}
