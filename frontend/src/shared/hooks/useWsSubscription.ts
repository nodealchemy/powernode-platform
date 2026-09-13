import { useEffect, useRef } from 'react';
import { wsManager } from '@/shared/services/WebSocketManager';

/** A single WebSocket channel subscription — the same shape `wsManager.subscribe`
 *  and {@link useWebSocket}'s `subscribe` take. */
export interface WsSubscription {
  channel: string;
  params?: Record<string, unknown>;
  onMessage?: (data: unknown) => void;
  onError?: (error: string) => void;
}

export interface UseWsSubscriptionOptions {
  /**
   * Whether the subscription should be active. Recompute this on every
   * render from whatever condition gated the original site's raw
   * `wsManager.subscribe` call (most sites guarded on a resolved
   * `accountId`, e.g. `if (!accountId) return;`) — passing a fresh value
   * each render is what makes the subscription start/stop exactly when the
   * condition flips. Default true (always subscribed).
   */
  enabled?: boolean;
  /**
   * Explicit dependency list controlling when the subscription restarts
   * (unsubscribes the old channel and subscribes again — its `useEffect`
   * re-runs). Default `[subscription.channel, enabled]`. Pass this when the
   * original site's effect dependency array included something beyond the
   * channel itself (e.g. `[accountId, platform.id, refresh]`) so the
   * restart cadence is preserved exactly, not approximated.
   */
  deps?: React.DependencyList;
}

/**
 * Subscribes to a single WebSocket channel via the shared `wsManager`
 * singleton for the lifetime of the effect; unsubscribes on unmount or
 * whenever the effect's dependencies change. Consolidates the ~5 near-
 * identical raw `wsManager.subscribe({...})` call sites in the system
 * extension frontend (IMP-01a08c9b C8) onto the same shape `usePolling`
 * gives the core `setInterval` sites — deliberately NOT `useWebSocket`
 * (which needs a Redux `<Provider>` for its `useSelector`/`useDispatch`
 * calls) or `usePageWebSocket` (subscribes by a registered core/extension
 * channel *key*, not a raw ActionCable channel name + custom params, which
 * is what these sites need).
 *
 * `subscription` is held in a ref, refreshed every render, so the effect's
 * own dependency array controls *when* the subscription restarts while the
 * channel name, params, and handlers used at that moment are always the
 * latest render's — the same stale-closure protection `usePolling` gives
 * its callback (review F4, review-lane4-c8.md).
 *
 * @example
 * // FleetDashboardPage.tsx — subscribe only once accountId resolves,
 * // restart if accountId or the message handler's own deps change:
 * useWsSubscription(
 *   { channel: 'SystemFleetChannel', params: { account_id: accountId }, onMessage, onError },
 *   { enabled: !!accountId, deps: [accountId, addNotification] }
 * );
 */
export function useWsSubscription(
  subscription: WsSubscription,
  options: UseWsSubscriptionOptions = {}
): void {
  const { enabled = true, deps } = options;

  const subscriptionRef = useRef(subscription);
  subscriptionRef.current = subscription;

  useEffect(() => {
    if (!enabled) return;

    const unsubscribe = wsManager.subscribe({
      channel: subscriptionRef.current.channel,
      params: subscriptionRef.current.params,
      onMessage: (data: unknown) => subscriptionRef.current.onMessage?.(data),
      onError: (error: string) => subscriptionRef.current.onError?.(error),
    });

    return () => unsubscribe();
    // Dependency array is intentionally caller-controlled — see `deps` doc above.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps ?? [subscription.channel, enabled]);
}
