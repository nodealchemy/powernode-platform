import { useCallback, useEffect, useRef, useState } from 'react';
import { logger } from '@/shared/utils/logger';
import {
  fetchComponentStatus,
  fetchComponentImpact,
} from '@/features/platform/status/api/platformStatusApi';
import type {
  ComponentStatusDetail,
  ComponentStatusImpactData,
} from '@/shared/types/platformStatus';

// The drawer's data (C3). Two reads, deliberately kept apart from the page's:
// the grid holds SUMMARIES, and the payloads a drawer needs — the conditions
// themselves, the dependency edges, remediation, links and actions — are only
// on the detail read. Merging the two into one page-level fetch would make every
// card carry a drawer's worth of payload it will probably never open.
//
// TWO CALLS, NOT ONE, and the reason is not laziness. `show` already returns an
// impact SUMMARY, but only `:id/impact` returns the ranked root-cause
// candidates and the `heuristic` / `heuristic_basis` labels the design requires
// the page to render beside them.
//
// ── A DRAWER SHOWING ONE COMPONENT'S ACTIONS UNDER ANOTHER'S NAME ──────────
//
// This file used to allow exactly that, twice over (C3 review F1, F2 — both
// HIGH, both proven by execution through the drawer's own "follow an edge"
// affordance):
//
//   F1  The clear ran only when `id` became null. Re-pointing the drawer from A
//       to B left A's detail in place until B's read landed, so the body showed
//       A's conditions — and A's ACTIONS, each carrying A's `path` — under B's
//       name and verdict. A click in that window would have actuated A while the
//       header said B.
//   F2  No request sequencing. A slow response for A, arriving after B's, won
//       and was never corrected: A's body and A's action buttons under B's
//       header, permanently.
//
// Both are fixed the way the page's own loader was fixed in the C2 review:
// clear on EVERY id change, and drop any response whose sequence number is not
// the current one. The Actions tab rendering `detail.actions` is what made this
// a safety defect rather than a cosmetic one, and it is why the clear happens
// synchronously in the effect rather than being left to the next response.

export interface UseComponentStatusDetailReturn {
  detail: ComponentStatusDetail | null;
  impact: ComponentStatusImpactData | null;
  loading: boolean;
  error: string | null;
  /** Re-read both. Called after an action succeeds, so the drawer shows the result. */
  refresh: () => void;
}

export function useComponentStatusDetail(id: string | null): UseComponentStatusDetailReturn {
  const [detail, setDetail] = useState<ComponentStatusDetail | null>(null);
  const [impact, setImpact] = useState<ComponentStatusImpactData | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Monotonic: every read takes the next number, and only the holder of the
  // latest number may write. Bumped on close too, so a response for a component
  // the operator has already dismissed cannot re-populate a closed drawer.
  const seq = useRef(0);

  const load = useCallback(async (componentId: string) => {
    const current = ++seq.current;
    const isStale = () => current !== seq.current;
    setLoading(true);

    try {
      const [show, impactData] = await Promise.all([
        fetchComponentStatus(componentId),
        fetchComponentImpact(componentId),
      ]);
      if (isStale()) return;
      setDetail(show?.component_status ?? null);
      setImpact(impactData ?? null);
      setError(null);
    } catch (e) {
      if (isStale()) return;
      const message = e instanceof Error ? e.message : 'Failed to load component detail';
      setError(message);
      logger.error('[PlatformStatus] detail load failed', e);
    } finally {
      if (!isStale()) setLoading(false);
    }
  }, []);

  useEffect(() => {
    // Cleared on EVERY change of id, not only on null (F1). Synchronous, so the
    // frame after a re-point shows "loading" under B's header rather than A's
    // body and A's action buttons.
    setDetail(null);
    setImpact(null);
    setError(null);

    if (!id) {
      seq.current += 1; // invalidate anything still in flight for the old id
      setLoading(false);
      return;
    }
    void load(id);
  }, [id, load]);

  const refresh = useCallback(() => {
    if (id) void load(id);
  }, [id, load]);

  return { detail, impact, loading, error, refresh };
}

export default useComponentStatusDetail;
