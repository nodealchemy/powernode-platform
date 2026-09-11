import { useCallback, useEffect, useRef, useState } from 'react';
import { logger } from '@/shared/utils/logger';
import {
  fetchComponentRunbook,
  fetchRemediationRoute,
  fetchComponentEvents,
  fetchInvestigations,
} from '@/features/platform/status/api/platformStatusApi';
import type {
  ComponentRunbookData,
  ComponentStatusEvent,
  InvestigationsData,
  RemediationRouteData,
} from '@/shared/types/platformStatus';

// The drawer's A9 reads (C3 part 2): runbook, remediation route, events and
// investigations.
//
// ── EACH READ FAILS ON ITS OWN ─────────────────────────────────────────────
//
// `Promise.allSettled`, not `Promise.all`. These are four independent doors,
// and one of them failing — say the investigations route while the worker is
// down — must not blank the other three. Each result carries its own `null`,
// and each tab renders its own "could not be read" rather than the whole drawer
// going dark because of the least important of four panels. Events carries an
// explicit `eventsFailed`, because an empty events list is itself a claim ("no
// transitions") that a failed read must never make (C3p2 review R2).
//
// ── A SEQUENCE GUARD, FOR THE SAME REASON THE PAGE HAS ONE ─────────────────
//
// Following an edge re-points the drawer at a neighbour while the previous
// component's reads may still be in flight. Without the guard, a slow response
// for component A lands after the drawer is showing component B and paints A's
// runbook under B's title — a misattribution, which is worse than a blank.
//
// The guard covers the investigations RE-READ too, and that one is captured
// when the POST STARTS, not when it lands (C3p2 review R1). Reading the
// sequence at landing time let a POST begun on A, landing after the drawer had
// moved to B, pass B's check and show A's investigation in B's tab.

export interface UseComponentDrawerExtrasReturn {
  runbook: ComponentRunbookData | null;
  route: RemediationRouteData | null;
  events: ComponentStatusEvent[];
  eventsTotal: number;
  /** The events read failed or was malformed. Not the same fact as "no transitions". */
  eventsFailed: boolean;
  investigations: InvestigationsData | null;
  loading: boolean;
  /**
   * Call when an investigation POST STARTS. Captures the component and the read
   * sequence at that moment and returns the re-read to run once the POST lands;
   * that re-read does nothing if the drawer has moved on in between.
   */
  beginInvestigationRefresh: () => () => void;
}

export function useComponentDrawerExtras(id: string | null): UseComponentDrawerExtrasReturn {
  const [runbook, setRunbook] = useState<ComponentRunbookData | null>(null);
  const [route, setRoute] = useState<RemediationRouteData | null>(null);
  const [events, setEvents] = useState<ComponentStatusEvent[]>([]);
  const [eventsTotal, setEventsTotal] = useState(0);
  const [eventsFailed, setEventsFailed] = useState(false);
  const [investigations, setInvestigations] = useState<InvestigationsData | null>(null);
  const [loading, setLoading] = useState(false);
  const seq = useRef(0);

  useEffect(() => {
    // Cleared first, so a re-pointed drawer never shows the previous component's
    // runbook or events while the new ones load.
    setRunbook(null);
    setRoute(null);
    setEvents([]);
    setEventsTotal(0);
    setEventsFailed(false);
    setInvestigations(null);

    // Bumped on close as well as on every re-point, so nothing still in flight
    // — an initial read or an investigations re-read — can land afterwards.
    const current = ++seq.current;

    if (!id) {
      setLoading(false);
      return;
    }

    setLoading(true);

    void Promise.allSettled([
      fetchComponentRunbook(id),
      fetchRemediationRoute(id),
      fetchComponentEvents(id),
      fetchInvestigations(id),
    ]).then(([runbookResult, routeResult, eventsResult, investigationsResult]) => {
      if (current !== seq.current) return;

      if (runbookResult.status === 'fulfilled') setRunbook(runbookResult.value ?? null);
      if (routeResult.status === 'fulfilled') setRoute(routeResult.value ?? null);
      // Optional-chained: a fulfilled promise can still carry a malformed body,
      // and a TypeError thrown inside this `.then` would reject silently and
      // leave `loading` stuck on — a drawer that spins forever over one bad
      // envelope. (The events client itself rejects a body with no events
      // array, so a malformed events envelope arrives here as `rejected`.)
      if (eventsResult.status === 'fulfilled') {
        setEvents(eventsResult.value?.events ?? []);
        setEventsTotal(eventsResult.value?.pagination?.total_count ?? 0);
      } else {
        setEventsFailed(true);
      }
      if (investigationsResult.status === 'fulfilled') {
        setInvestigations(investigationsResult.value ?? null);
      }

      [runbookResult, routeResult, eventsResult, investigationsResult].forEach((result) => {
        if (result.status === 'rejected') {
          logger.error('[PlatformStatus] drawer read failed', result.reason);
        }
      });
      setLoading(false);
    });
  }, [id]);

  const beginInvestigationRefresh = useCallback(() => {
    // Captured NOW — when the POST starts — together with the component it is
    // for. Both are checked when the re-read runs and again when it lands.
    const targetId = id;
    const startedAt = seq.current;
    return () => {
      if (!targetId || startedAt !== seq.current) return;
      void fetchInvestigations(targetId)
        .then((data) => {
          if (startedAt === seq.current) setInvestigations(data ?? null);
        })
        .catch((e: unknown) => logger.error('[PlatformStatus] investigations refresh failed', e));
    };
  }, [id]);

  return {
    runbook,
    route,
    events,
    eventsTotal,
    eventsFailed,
    investigations,
    loading,
    beginInvestigationRefresh,
  };
}

export default useComponentDrawerExtras;
