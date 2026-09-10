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
// going dark because of the least important of four panels.
//
// ── A SEQUENCE GUARD, FOR THE SAME REASON THE PAGE HAS ONE ─────────────────
//
// Following an edge re-points the drawer at a neighbour while the previous
// component's reads may still be in flight. Without the guard, a slow response
// for component A lands after the drawer is showing component B and paints A's
// runbook under B's title — a misattribution, which is worse than a blank.

export interface UseComponentDrawerExtrasReturn {
  runbook: ComponentRunbookData | null;
  route: RemediationRouteData | null;
  events: ComponentStatusEvent[];
  eventsTotal: number;
  investigations: InvestigationsData | null;
  loading: boolean;
  /** Re-read investigations only — called after one is opened. */
  refreshInvestigations: () => void;
}

export function useComponentDrawerExtras(id: string | null): UseComponentDrawerExtrasReturn {
  const [runbook, setRunbook] = useState<ComponentRunbookData | null>(null);
  const [route, setRoute] = useState<RemediationRouteData | null>(null);
  const [events, setEvents] = useState<ComponentStatusEvent[]>([]);
  const [eventsTotal, setEventsTotal] = useState(0);
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
    setInvestigations(null);

    if (!id) return;

    const current = ++seq.current;
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
      // envelope.
      if (eventsResult.status === 'fulfilled') {
        setEvents(eventsResult.value?.events ?? []);
        setEventsTotal(eventsResult.value?.pagination?.total_count ?? 0);
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

  const refreshInvestigations = useCallback(() => {
    if (!id) return;
    const current = seq.current;
    void fetchInvestigations(id)
      .then((data) => {
        if (current === seq.current) setInvestigations(data);
      })
      .catch((e) => logger.error('[PlatformStatus] investigations refresh failed', e));
  }, [id]);

  return { runbook, route, events, eventsTotal, investigations, loading, refreshInvestigations };
}

export default useComponentDrawerExtras;
