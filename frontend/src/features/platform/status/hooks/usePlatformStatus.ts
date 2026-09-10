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
// ── THE POLL IS OFF WHILE THE CHANNEL IS LIVE ──────────────────────────────
//
// design §6 asks for "a 30 s poll as a genuine fallback". Genuine means it does
// not run alongside the channel: two live sources means every transition is
// fetched twice, and it also means a broken channel is invisible — the page
// still updates, so nobody notices the socket died until something that has no
// poll behind it stops working.
//
// "Live" here means the CHANNEL accepted us, not merely that the cable is up.
// The two come apart, and gating on the cable is a real hole rather than a
// nicety — see the gate near the bottom of this file. Both arms of both
// conditions are asserted in the spec.
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

/**
 * The channels this page subscribes to, at MODULE scope so the array identity is
 * stable across renders (C2 review H1).
 *
 * This is not a style preference. `usePageWebSocket` puts `subscribeTo` in the
 * dependency list of `getChannelsToSubscribe`, which is in the dependency list
 * of the auto-subscribe effect, whose cleanup and body both call
 * `setActiveChannels`. A fresh array literal each render therefore means:
 * effect re-runs → cleanup sets state → subscribe sets state → re-render → new
 * array → effect re-runs, forever. The review proved both arms by execution
 * against the real hook: a stable array settles at two `subscribe` calls, the
 * inline literal hits "Maximum update depth exceeded" and then exhausts the
 * heap. In production each iteration would tear down and re-create the
 * ActionCable subscription — on the one page an operator opens during an outage.
 *
 * `subscribeTo` had no other caller in the tree, so this hook was the option's
 * first user and the sharpness had never been exercised. Memoizing inside
 * `usePageWebSocket` would make every future caller safe; that file is not this
 * lane's, and is filed as a follow-up.
 */
const STATUS_CHANNELS = ['platformStatus'];

/**
 * The message `PlatformStatusChannel` transmits once it has ACCEPTED a
 * subscription. Receipt of this is the only client-visible proof that the
 * channel took us — see the poll gate below.
 */
const CHANNEL_ESTABLISHED = 'connection_established';

/** How long to wait for a burst of transitions to finish before reconciling. */
export const RECONCILE_DEBOUNCE_MS = 750;

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
  /**
   * The CABLE is up. Not the same question as `isLive`: the cable can be up
   * while `PlatformStatusChannel` has rejected the subscription.
   */
  isConnected: boolean;
  /**
   * The cable is up AND the channel accepted us. This is what "live" means on
   * this page, what gates the poll, and what the header reports — reporting the
   * cable instead would say "live" through a channel reject.
   */
  isLive: boolean;
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
  /** Every component kind seen this session, sorted. A union, for the same reason. */
  knownKinds: string[];
  /**
   * environment id → the plane's human name (A4b `environment_name`, else
   * `environment_slug`), accumulated over the session like the id union, so a
   * filtered response that no longer carries a plane's rows does not lose its
   * name. An id with no entry here has no name on the wire.
   */
  environmentLabels: Record<string, string>;
  refresh: () => void;
}

/**
 * Adds any new values to a session-long option set, preserving first-seen order
 * and returning the SAME array when nothing was added (so a `useMemo` keyed on it
 * does not churn).
 *
 * Every filter selector's options are built this way, because each of them is
 * derived from a FILTERED response: once a filter is applied the response only
 * contains what matches it, so options derived from the current response alone
 * collapse to the option already chosen.
 */
const unionWith = (previous: string[], incoming: (string | null | undefined)[]): string[] => {
  const seen = new Set(previous);
  const additions: string[] = [];
  for (const value of incoming) {
    if (!value || seen.has(value)) continue;
    seen.add(value);
    additions.push(value);
  }
  return additions.length === 0 ? previous : [...previous, ...additions];
};

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
  const [knownKinds, setKnownKinds] = useState<string[]>([]);
  const [environmentLabels, setEnvironmentLabels] = useState<Record<string, string>>({});
  // Whether PlatformStatusChannel has ACCEPTED our subscription — see the poll
  // gate at the bottom of this hook.
  const [channelEstablished, setChannelEstablished] = useState(false);

  // The query is an object literal at the call site, so it is a new identity
  // every render. Serializing it gives the effects a primitive to depend on —
  // without this the load effect re-runs forever.
  const queryKey = JSON.stringify(query);
  const queryRef = useRef(query);
  queryRef.current = query;

  // Monotonic request counter (C2 review L2). FIVE things call `load`: the
  // filter effect, the poll, the coalesced reconcile, the registry-bump effect
  // and the Refresh button. Without a sequence number a slow older response
  // applied after a newer one silently wins, and `lastLoadedAt` — the header's
  // "read Ns ago" basis — would name the wrong instant. A stale response is
  // dropped rather than merged: it is not a partial answer, it is an answer to a
  // question that has been superseded.
  const requestSeq = useRef(0);

  const load = useCallback(async () => {
    const seq = ++requestSeq.current;
    const isStale = () => seq !== requestSeq.current;

    try {
      const [index, rollupData] = await Promise.all([
        fetchComponentStatuses(queryRef.current),
        fetchStatusRollup(queryRef.current),
      ]);

      if (isStale()) return;

      setRows(index.component_statuses);
      setRollup(rollupData ?? null);
      setAppliedFilters(index.filters);
      setUnknownEnvironment(index.unknown_environment);
      setTotalCount(index.pagination.total_count);
      setLastLoadedAt(new Date());
      setError(null);

      setKnownEnvironmentIds((previous) =>
        unionWith(previous, index.component_statuses.map((row) => row.environment_id))
      );
      // Plane names from A4b. Name first, slug second, and NEVER the id: a
      // missing name is recorded as a missing entry, so the selector can decide
      // what an unnamed plane looks like instead of this map inventing a label.
      setEnvironmentLabels((previous) => {
        let next = previous;
        for (const row of index.component_statuses) {
          const label = row.environment_name || row.environment_slug;
          if (!row.environment_id || !label || previous[row.environment_id] === label) continue;
          if (next === previous) next = { ...previous };
          next[row.environment_id] = label;
        }
        return next;
      });
      // The SAME union, for the same reason (C2 review M2). `rows` is the
      // FILTERED response, so choosing `kind=docker_host` makes the next
      // response contain only docker hosts — and a Kind selector derived from it
      // would collapse to the option already chosen. Milder than the plane case
      // because "All kinds" always remains, so the operator escapes in two steps
      // rather than being stranded; wrong for the same reason all the same.
      setKnownKinds((previous) =>
        unionWith(
          previous,
          index.component_statuses.map((row) => row.component_kind)
        ).sort()
      );
    } catch (e) {
      if (isStale()) return;
      // Kept as a message rather than swallowed: a status page that renders an
      // empty grid when the read FAILED is indistinguishable from a healthy
      // platform, which is the worst thing this page could do.
      const message = e instanceof Error ? e.message : 'Failed to load component status';
      setError(message);
      logger.error('[PlatformStatus] load failed', e);
    } finally {
      if (!isStale()) setLoading(false);
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
    subscribeTo: STATUS_CHANNELS,
    onDataUpdate: (update) => {
      if (update.channel !== 'platformStatus') return;
      if (update.type === CHANNEL_ESTABLISHED) {
        setChannelEstablished(true);
        return;
      }
      if (update.type !== 'component_status_changed') return;
      applyTransition(update.data as ComponentStatusChangedPayload);
      scheduleReconcile();
    },
  });

  // A dropped cable invalidates any subscription that was established over it.
  // Without this reset a reconnect that the channel REJECTS would keep the poll
  // off on the strength of a subscription that no longer exists.
  useEffect(() => {
    if (!isConnected) setChannelEstablished(false);
  }, [isConnected]);

  // THE FALLBACK, gated on the CHANNEL rather than on the cable (C2 review M1).
  //
  // `isConnected` mirrors wsManager's connection-level state. It says nothing
  // about whether `PlatformStatusChannel` accepted us — and that channel rejects
  // a subscription with no `current_user` and one naming an account the viewer
  // may not read. On either path the cable stays up, `isConnected` stays true,
  // and a poll gated on it would stay off forever while the page silently
  // stopped updating. That is the same defect this design set out to avoid, from
  // the other side: not "the poll hides a dead channel" but "the cable hides a
  // dead channel".
  //
  // So the gate is receipt of the channel's own `connection_established`
  // message, which is the only client-visible proof of acceptance.
  // `activeChannels` would not do: `usePageWebSocket` sets it client-side
  // without waiting for the server, so it reads true through a reject too.
  const live = isConnected && channelEstablished;
  usePolling(refresh, STATUS_POLL_MS, { enabled: !live, deps: [refresh, live] });

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
      isLive: live,
      lastLoadedAt,
      knownEnvironmentIds,
      knownKinds,
      environmentLabels,
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
      live,
      lastLoadedAt,
      knownEnvironmentIds,
      knownKinds,
      environmentLabels,
      refresh,
    ]
  );
}

export default usePlatformStatus;
