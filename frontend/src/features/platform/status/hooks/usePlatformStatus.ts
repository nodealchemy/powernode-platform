import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import { usePolling } from '@/shared/hooks/usePolling';
import { featureRegistry } from '@/shared/services/featureRegistry';
import { logger } from '@/shared/utils/logger';
import {
  fetchComponentStatuses,
  fetchStatusRollup,
  type PlatformStatusQuery,
} from '@/features/platform/status/api/platformStatusApi';
import {
  UNHEALTHY_VERDICTS,
  isVerdict,
  type ComponentStatusSummary,
  type ComponentStatusRollupData,
  type StatusFilters,
  type Verdict,
} from '@/shared/types/platformStatus';

// The status page's data layer: one list read, one rollup read, a live channel,
// and a poll that is a genuine fallback rather than a second clock.
//
// ── THE POLL IS OFF WHILE THE SOCKET IS UP ─────────────────────────────────
//
// design §6 asks for "a 30 s poll as a genuine fallback". Genuine means it does
// not run alongside the channel: two live sources means every transition is
// fetched twice, and it also means a broken channel is invisible — the page
// still updates, so nobody notices the socket died until something that has no
// poll behind it stops working. `enabled: !isConnected` is the whole mechanism,
// and its two arms are asserted in the spec.
//
// ── WHAT THE BROADCAST ACTUALLY CARRIES ────────────────────────────────────
//
// `PlatformStatusChannel` does NOT broadcast a serialized row. Its payload is
//
//   { type: "component_status_changed", component_kind, component_ref,
//     from_verdict, to_verdict, removed, reason, shared, event_ids, occurred_at }
//
// — a notification that something changed, keyed by the registry pair, with no
// row id, no display name, no presentation, no remediation state and no
// observed_at. So "merge the row" is two steps, and conflating them would
// leave the page confidently wrong:
//
//   1. patch what the payload DOES carry onto the matching row, immediately, so
//      a verdict change is visible the instant it happens; and
//   2. schedule a reconciling refetch for everything it does not.
//
// The refetch is COALESCED behind one short timer because a single sweep
// transitions many components at once — forty payloads must not become forty
// list reads. That timer is a debounce, not a poll: it is armed by an incoming
// message and fires once, and there is no recurring interval anywhere in this
// file (`usePolling` owns the only one).

/** How long to wait for a burst of transitions to finish before reconciling. */
const RECONCILE_DEBOUNCE_MS = 750;

/** The fallback poll interval named by design §6. */
export const STATUS_POLL_MS = 30000;

/** The shape `PlatformStatusChannel` broadcasts on a transition. */
export interface ComponentStatusChangedPayload {
  type: string;
  component_kind?: string;
  component_ref?: string;
  from_verdict?: string | null;
  to_verdict?: string | null;
  removed?: boolean;
  reason?: string | null;
  shared?: boolean;
  occurred_at?: string;
}

export interface UsePlatformStatusReturn {
  rows: ComponentStatusSummary[];
  rollup: ComponentStatusRollupData | null;
  /** Echoed back by the server, so an empty page can name the question that produced it. */
  appliedFilters: StatusFilters;
  /** True when a plane was named that this account does not have — not the same as an empty plane. */
  unknownEnvironment: boolean;
  /** Total matching rows server-side, which may exceed the number loaded. */
  totalCount: number;
  loading: boolean;
  error: string | null;
  /** Live channel state. Drives the poll's `enabled` and the header's basis line. */
  isConnected: boolean;
  /** When the currently displayed data was fetched. Every number carries its basis. */
  lastLoadedAt: Date | null;
  /**
   * Every environment id seen this session, in first-seen order. A UNION rather
   * than the current response's set: once a plane is selected the response
   * contains only that plane plus the plane-less rows, so deriving the options
   * from it would collapse the selector to the option already chosen and strand
   * the operator there.
   */
  knownEnvironmentIds: string[];
  refresh: () => void;
}

/** Verdicts a row derives from its own verdict. `held_by_intent` is NOT one of them. */
const deriveFlags = (verdict: Verdict) => ({
  verdict,
  held: verdict === 'held',
  unhealthy: UNHEALTHY_VERDICTS.includes(verdict),
});

export function usePlatformStatus(query: PlatformStatusQuery): UsePlatformStatusReturn {
  const [rows, setRows] = useState<ComponentStatusSummary[]>([]);
  const [rollup, setRollup] = useState<ComponentStatusRollupData | null>(null);
  const [appliedFilters, setAppliedFilters] = useState<StatusFilters>({});
  const [unknownEnvironment, setUnknownEnvironment] = useState(false);
  const [totalCount, setTotalCount] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [lastLoadedAt, setLastLoadedAt] = useState<Date | null>(null);
  const [knownEnvironmentIds, setKnownEnvironmentIds] = useState<string[]>([]);

  // The query is an object literal at the call site, so it is a new identity
  // every render. Serializing it gives the effects a primitive to depend on —
  // without this the load effect re-runs forever.
  const queryKey = JSON.stringify(query);
  const queryRef = useRef(query);
  queryRef.current = query;

  const load = useCallback(async () => {
    try {
      const [index, rollupData] = await Promise.all([
        fetchComponentStatuses(queryRef.current),
        fetchStatusRollup(queryRef.current),
      ]);

      setRows(index.component_statuses);
      setRollup(rollupData ?? null);
      setAppliedFilters(index.filters);
      setUnknownEnvironment(index.unknown_environment);
      setTotalCount(index.pagination.total_count);
      setLastLoadedAt(new Date());
      setError(null);

      setKnownEnvironmentIds((previous) => {
        const seen = new Set(previous);
        const additions = index.component_statuses
          .map((row) => row.environment_id)
          .filter((id): id is string => Boolean(id) && !seen.has(id as string));
        if (additions.length === 0) return previous;
        return [...previous, ...Array.from(new Set(additions))];
      });
    } catch (e) {
      // Kept as a message rather than swallowed: a status page that renders an
      // empty grid when the read FAILED is indistinguishable from a healthy
      // platform, which is the worst thing this page could do.
      const message = e instanceof Error ? e.message : 'Failed to load component status';
      setError(message);
      logger.error('[PlatformStatus] load failed', e);
    } finally {
      setLoading(false);
    }
  }, []);

  const refresh = useCallback(() => {
    void load();
  }, [load]);

  // Reload whenever the filters change. `loading` is set here rather than
  // inside `load` so the poll and the live reconcile do not flash a spinner
  // over data that is already on screen.
  useEffect(() => {
    setLoading(true);
    void load();
  }, [queryKey, load]);

  // ── Live reconcile, coalesced ────────────────────────────────────────────
  const reconcileTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const scheduleReconcile = useCallback(() => {
    if (reconcileTimer.current) clearTimeout(reconcileTimer.current);
    reconcileTimer.current = setTimeout(() => {
      reconcileTimer.current = null;
      void load();
    }, RECONCILE_DEBOUNCE_MS);
  }, [load]);

  useEffect(
    () => () => {
      if (reconcileTimer.current) clearTimeout(reconcileTimer.current);
    },
    []
  );

  const applyTransition = useCallback((payload: ComponentStatusChangedPayload) => {
    const kind = payload.component_kind;
    const ref = payload.component_ref;
    if (!kind || !ref) return;

    setRows((previous) => {
      const index = previous.findIndex(
        (row) => row.component_kind === kind && row.component_ref === ref
      );

      // A component this page has never seen. There is nothing to patch — the
      // payload carries no display name or presentation — so the reconcile is
      // the only thing that can render it. Dropping through is correct.
      if (index === -1) return previous;

      // `removed` means the sweep reaped the row: the component is gone, not
      // healthy. Rendering a stale verdict for a thing that no longer exists is
      // how a decommissioned node keeps showing green.
      if (payload.removed || !payload.to_verdict) {
        return previous.filter((_, i) => i !== index);
      }

      if (!isVerdict(payload.to_verdict)) return previous;

      const next = [...previous];
      next[index] = {
        ...previous[index],
        ...deriveFlags(payload.to_verdict),
        // `reason` comes from the transition. `held_by_intent`, `remediation_state`,
        // `condition_count` and `observed_at` are NOT in the payload and are
        // deliberately left stale until the reconcile lands — inventing them
        // here would be a guess the page presents as an observation.
        reason: payload.reason ?? previous[index].reason,
        last_transition_at: payload.occurred_at ?? previous[index].last_transition_at,
      };
      return next;
    });
  }, []);

  const { isConnected } = usePageWebSocket({
    pageType: 'dashboard',
    subscribeTo: ['platformStatus'],
    onDataUpdate: (update) => {
      if (update.channel !== 'platformStatus') return;
      if (update.type !== 'component_status_changed') return;
      applyTransition(update.data as ComponentStatusChangedPayload);
      scheduleReconcile();
    },
  });

  // The fallback. Off entirely while the channel is up — see the header.
  usePolling(refresh, STATUS_POLL_MS, { enabled: !isConnected, deps: [refresh, isConnected] });

  // A runtime extension that registers after first render brings its own
  // surfaces with it, and typically its backend contributors too, so the set of
  // component kinds the server can report is not fixed at mount. Re-reading on a
  // registry bump is what makes a late-registered kind appear without a reload
  // (the CostPage precedent, extended from "re-render" to "re-read" because the
  // rows come from the server rather than from the registry).
  const [registryVersion, setRegistryVersion] = useState(() => featureRegistry.getVersion());
  useEffect(
    () => featureRegistry.subscribe(() => setRegistryVersion(featureRegistry.getVersion())),
    []
  );
  const firstRegistryVersion = useRef(registryVersion);
  useEffect(() => {
    if (registryVersion === firstRegistryVersion.current) return;
    void load();
  }, [registryVersion, load]);

  return useMemo(
    () => ({
      rows,
      rollup,
      appliedFilters,
      unknownEnvironment,
      totalCount,
      loading,
      error,
      isConnected,
      lastLoadedAt,
      knownEnvironmentIds,
      refresh,
    }),
    [
      rows,
      rollup,
      appliedFilters,
      unknownEnvironment,
      totalCount,
      loading,
      error,
      isConnected,
      lastLoadedAt,
      knownEnvironmentIds,
      refresh,
    ]
  );
}

export default usePlatformStatus;
